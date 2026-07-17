import 'package:flutter/foundation.dart';

import '../models/video_entry.dart';
import 'fvp_player.dart';

/// 视频元数据探测：基于 fvp 的 libmdk（[FvpPlayer.probeVideoMeta]），
/// 通过 [VideoPlayerController.getMediaInfo()] 一次性拿到编码/分辨率/帧率/时长等信息。
///
/// 不再依赖系统 ffprobe（当前环境不可用），改为播放器内核直接提供。
///
/// 性能要点：列表里视频很多时，绝不能一次性为成百上千个文件创建 fvp/libmdk
/// 播放器实例——每个 `initialize()` 都会在平台线程上做 demux/解码器/GL 初始化，
/// 长串串行调用会占满平台线程，导致窗口最小化/最大化/全屏/退出无响应、正在播放的
/// 视频掉帧。
///
/// 因此采用「页面级静默慢扫 + 单并发 + 限速 + 可见优先 + 滚动暂停」：
/// - 探测与条目挂载彻底**解耦**：播放列表叶子挂载时不再发起探测，只登记可见性；
///   真正发起探测的是一个页面级后台扫描器，打开列表时遍历全部未探测视频慢慢跑。
///   滚动时不再产生任何新探测请求，因此滚动纯 UI、不卡。
/// - 同时只有 **1 个**探测在跑（临时 controller 用完即释放），其余排队；平台线程
///   在两次探测之间的 [gap] 间隙里正常解码正在播放的视频，不再被持续抢占。
/// - [gap] 让出平台线程；滚动时通过 [setPaused] 完全暂停扫描，彻底消除滚动掉帧。
/// - 按路径缓存结果（跨页面持续有效），当前正在播放的视频（解码器/时长已由播放器
///   回填）通过 [putCache]/[setActivePath] 排除出扫描，避免重复建播放器实例。
class VideoMetadataService {
  /// 是否仍有探测任务在跑或待跑；供播放列表头部显示忙碌指示。
  static final ValueNotifier<bool> busy = ValueNotifier(false);

  /// 同时只有 **1 个**探测在跑（临时 controller 用完即释放），其余排队；平台线程
  /// 在两次探测之间的 [gap] 间隙里正常解码正在播放的视频，不再被持续抢占。
  /// 提速只能调小 [gap]，而非提高并发（并发提高会与正在播放的视频抢同一平台线程）。

  /// 两次探测之间的间隔：让平台线程在间隙里正常解码正在播放的视频，避免持续抢占导致掉帧。
  /// 调小可更快填满列表，但会更频繁地抢占平台线程。
  static const Duration _gap = Duration(milliseconds: 300);

  /// 空闲/暂停轮询间隔：没有可探测项或滚动暂停时，每隔这么久再检查一下是否恢复。
  static const Duration _poll = Duration(milliseconds: 200);

  /// 已完成的探测结果缓存（路径 → 元数据）。跨页面持续有效，重复进入直接命中。
  static final Map<String, VideoMeta?> _cache = {};

  /// 正在探测中的路径集合（去重，避免重复 initialize 同一文件）。
  static final Set<String> _inflight = {};

  /// 尚未探测的路径集合（页面级扫描器从中取任务；可见优先）。
  static final Set<String> _remaining = {};

  /// 当前可见（已挂载进视口）的路径集合；扫描时优先探测这些，让屏幕内条目最快填满。
  static final Set<String> _visible = {};

  /// 路径 → 条目对象：探测完成后直接回填元数据并通知挂载中的叶子自更新，
  /// 不依赖叶子的回调，彻底解耦挂载时机。
  static Map<String, VideoEntry> _entriesByPath = const {};

  /// 当前正在播放的视频路径：其编码/时长已由播放器内核回填，后台扫描应排除，避免重复建播放器。
  static String? _activePath;

  static int _active = 0;
  static bool _paused = false;
  static bool _scanning = false;

  /// 置 true 时扫描循环退出（页面 dispose 时调用）。
  static bool _stop = false;

  /// 探测单个视频的元数据；失败返回 null。
  static Future<VideoMeta?> probe(String path) => FvpPlayer.probeVideoMeta(path);

  /// 注册/注销某个条目的可见性（由播放列表叶子在挂载/卸载时调用）。
  /// 可见项在扫描中被优先探测，但**不触发任何立即探测**——真正的探测由页面级
  /// 后台慢扫按「可见优先 + 限速」进行，从而与滚动解耦，滚动纯 UI、不卡。
  static void markVisible(String path, bool visible) {
    if (visible) {
      _visible.add(path);
    } else {
      _visible.remove(path);
    }
  }

  /// 登记当前正在播放的视频：其元数据由播放器内核直接回填，后台扫描排除它，
  /// 避免对同一文件再建一个临时探测 controller。
  static void setActivePath(String? path) {
    _activePath = path;
  }

  /// 播放器已通过 getMediaInfo 回填元数据（当前播放项）时登记缓存，并移出待扫队列，
  /// 使后台扫描不重复探测该文件。
  static void putCache(String path, VideoMeta? meta) {
    _cache[path] = meta;
    _remaining.remove(path);
    _updateBusy();
  }

  /// 启动/重新规划一次「静默慢扫」：把全部未探测且非当前播放的视频路径入队，
  /// 单并发、限速、可见优先地慢慢探测，并在滚动时通过 [setPaused] 暂停。
  ///
  /// 可多次调用（如打开新文件夹、新增本地文件）：每次只重置待扫集合与条目映射，
  /// 已运行的扫描循环会自动接着处理新加入的项，不会启动第二个循环。
  static void scanAll(List<VideoEntry> entries) {
    _stop = false;
    // 播放器已回填的（当前播放项）直接视为已探测，避免重复建播放器。
    for (final e in entries) {
      if (e.meta != null) _cache[e.path] = e.meta;
    }
    // 【修复】跨页面缓存立即回灌：重新进入页面时条目被重建（meta 重新为 null），
    // 但 _cache 跨页面保留；命中缓存的条目无需再次探测即可恢复信息。
    for (final e in entries) {
      if (!e.isVideo) continue;
      if (!_cache.containsKey(e.path)) continue;
      final c = _cache[e.path];
      if (e.meta != c) e.setMeta(c);
    }
    _remaining.clear();
    for (final e in entries) {
      if (!e.isVideo) continue;
      if (_cache.containsKey(e.path)) continue; // 已探测（含本次扫描前已回填的）
      if (e.path == _activePath) continue; // 当前正在播放，交给播放器内核
      _remaining.add(e.path);
    }
    _entriesByPath = {for (final e in entries) e.path: e};
    _updateBusy();
    if (!_scanning) {
      _scanning = true;
      _run();
    }
  }

  /// 滚动时暂停/恢复后台扫描。暂停期间零探测，彻底消除滚动掉帧。
  static void setPaused(bool paused) {
    _paused = paused;
  }

  /// 页面销毁时停止扫描循环并清场，避免后台 timer/探测泄漏。
  /// 注意：保留 [_cache]（路径→元数据）跨页面持续有效，重新打开文件夹可直接命中，
  /// 不重复探测；只清空本轮的待扫/可见/在途集合中状态。
  static void dispose() {
    _stop = true;
    _scanning = false;
    _paused = false;
    _activePath = null;
    _remaining.clear();
    _visible.clear();
    _inflight.clear();
    _entriesByPath = const {};
    _active = 0;
    _updateBusy();
  }

  /// 扫描主循环：单并发、限速、可见优先。直到 [dispose] 前一直存活，
  /// 空闲时仅以 [_poll] 间隔轻量轮询，不会空转占用平台线程。
  static Future<void> _run() async {
    while (!_stop) {
      if (_paused) {
        await Future.delayed(_poll);
        continue;
      }
      final path = _pickNext();
      if (path == null) {
        // 没有可探测项（可能已全部完成）。轻量轮询，等待新项注入或页面销毁。
        await Future.delayed(_poll);
        continue;
      }
      _inflight.add(path);
      _active = 1;
      _updateBusy();
      VideoMeta? m;
      try {
        m = await FvpPlayer.probeVideoMeta(path);
      } catch (_) {
        m = null;
      }
      // 探测期间可能发生了 dispose/重新规划：以最新状态为准。
      if (_stop) {
        _inflight.remove(path);
        _active = 0;
        return;
      }
      _cache[path] = m;
      _inflight.remove(path);
      _remaining.remove(path);
      _active = 0;
      _updateBusy();
      // 直接回填条目，通知挂载中的叶子自更新；离屏叶子未挂载，无所谓重建。
      _entriesByPath[path]?.setMeta(m);
      // 让出平台线程，给正在播放的视频的正常解码留喘息空间。
      await Future.delayed(_gap);
    }
    _scanning = false;
  }

  /// 优先返回「可见且未探测」的路径；其次任意「未探测」路径；都没有返回 null。
  /// 已缓存、正在探测中、或当前正在播放的路径一律跳过。
  static String? _pickNext() {
    String? visible;
    String? any;
    for (final p in _remaining) {
      if (_cache.containsKey(p) || _inflight.contains(p) || p == _activePath) {
        continue;
      }
      any ??= p;
      if (_visible.contains(p)) {
        visible = p;
        break;
      }
    }
    return visible ?? any;
  }

  static void _updateBusy() {
    final b = _active > 0 || (_remaining.isNotEmpty && !_paused);
    if (busy.value != b) busy.value = b;
  }
}
