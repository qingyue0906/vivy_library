import 'package:flutter/foundation.dart';

import '../models/audio_track.dart';
import 'audio_tag_service.dart';

/// 音频标签 + 时长 的渐进探测与跨页面缓存。
///
/// 对齐 [VideoMetadataService] 的设计：
/// - 页面级静默慢扫：单并发、限速、滚动/交互暂停，避免抢占平台线程导致掉帧；
/// - 按 path 缓存「组合元数据」（标签 + 时长），**跨页面持续有效**：
///   重开同一项目时直接回灌命中，封面/时长/标题即时显示，不再全量重探；
/// - 标签与时长统一由 [AudioTagService]（底层纯 Dart 的 [audio_metadata_reader]）
///   一次读取，结果写回缓存，避免每次重开都重复探测；
/// - [dispose] 只停后台扫描循环、清本轮状态集合，**保留 [_cache]**，使反复打开
///   不会持续升高内存，也无需重复探测。
///
/// 修复点（相对旧 _startMetaProbe）：
/// 1. 旧实现每次打开都全量重建条目并重跑时长探测，且没有任何跨页面缓存 → 体验上
///    「重开不回灌 + 时长重探」；本服务把组合元数据缓存到进程级，重开直接命中。
/// 2. 旧实现的标签缓存（AudioTagService._cache）曾被改为 LRU 限容，这里再叠加一层
///    跨页面组合缓存，使封面只在首次读取时解析一次。
class AudioMetadataService {
  /// 是否仍有探测任务在跑或待跑；供播放列表头部显示忙碌指示。
  static final ValueNotifier<bool> busy = ValueNotifier(false);

  /// 同时只有 1 个探测在跑（临时 controller 用完即释放），其余排队。
  static const Duration _gap = Duration(milliseconds: 120);

  /// 空闲/暂停轮询间隔：没有可探测项或滚动暂停时，每隔这么久再检查一次。
  static const Duration _poll = Duration(milliseconds: 200);

  /// 组合元数据缓存（path → AudioMeta，含标签+时长）。跨页面持续有效，重复进入直接命中。
  /// LRU 限容：封顶 + 超出淘汰最旧，封面字节内存有界，不会随打开项目数无限增长。
  static const int _maxCache = 1500;
  static final Map<String, AudioMeta?> _cache = {};
  static final List<String> _cacheLru = []; // 队头最旧，队尾最新

  static void _cachePut(String path, AudioMeta? meta) {
    _cache[path] = meta;
    _cacheLru.remove(path);
    _cacheLru.add(path);
    while (_cacheLru.length > _maxCache) {
      final old = _cacheLru.removeAt(0);
      _cache.remove(old);
    }
  }

  /// 退出应用时彻底清场（可选）。正常 dispose 保留缓存以复用，无需调用。
  static void clearCache() {
    _cache.clear();
    _cacheLru.clear();
  }

  /// 正在探测中的路径集合（去重，避免重复 initialize 同一文件）。
  static final Set<String> _inflight = {};

  /// 尚未探测的路径集合（扫描器从中取任务；当前曲目优先）。
  static final Set<String> _remaining = {};

  /// 路径 → 条目对象：探测完成后直接回填元数据并通知叶子自更新。
  static Map<String, AudioEntry> _entriesByPath = const {};

  /// 当前正在播放的音频路径：其时长已由播放器内核回填，后台扫描排除它，避免重复探测。
  static String? _activePath;

  static int _active = 0;
  static bool _paused = false;
  static bool _scanning = false;

  /// 置 true 时扫描循环退出（页面 dispose 时调用）。
  static bool _stop = false;

  /// 探测单个音频：标签与时长均来自 [AudioTagService]（底层纯 Dart 的
  /// [audio_metadata_reader] 一次按需读取，不再用 fvp/libmdk 逐个整文件离屏探测）。
  /// 二者本就合并在 [AudioMeta] 内，直接返回即可，去除原 libmdk 探测造成的大量
  /// 原生内存驻留（约数百 MB~1GB）。
  static Future<AudioMeta?> probe(String path) async {
    return AudioTagService.read(path);
  }

  /// 登记当前正在播放的音频：其时长由播放器内核回填，后台扫描排除它，
  /// 避免对同一文件再建一个临时探测 controller。
  static void setActivePath(String? path) {
    _activePath = path;
  }

  /// 播放器已通过 getMediaInfo 回填元数据（当前播放项）时登记缓存，并移出待扫队列，
  /// 使后台扫描不重复探测该文件。
  static void putCache(String path, AudioMeta? meta) {
    _cachePut(path, meta);
    _remaining.remove(path);
    _updateBusy();
  }

  /// 启动/重新规划一次「静默慢扫」：把全部未探测且非当前播放的音频路径入队，
  /// 单并发、限速、当前曲目优先地慢慢探测，并在滚动时通过 [setPaused] 暂停。
  ///
  /// 可多次调用（如打开新文件夹、新增本地文件）：每次只重置待扫集合与条目映射，
  /// 已运行的扫描循环会自动接着处理新加入的项，不会启动第二个循环。
  static void scanAll(List<AudioEntry> entries, {String? currentPath}) {
    _stop = false;
    // 条目自带 meta（如当前播放项已由播放器内核回填时长）直接视为已探测，避免重探。
    for (final e in entries) {
      if (e.meta != null) _cachePut(e.path, e.meta);
    }
    // 跨页面缓存立即回灌：重新进入页面时条目被重建（meta 重新为 null），
    // 但 _cache 跨页面保留；命中缓存的条目无需再次探测即可恢复信息。
    for (final e in entries) {
      if (!_cache.containsKey(e.path)) continue;
      final c = _cache[e.path];
      if (e.meta != c) e.setMeta(c);
    }
    _remaining.clear();
    for (final e in entries) {
      if (_cache.containsKey(e.path)) continue; // 已探测（含本次扫描前已回填的）
      if (e.path == _activePath) continue; // 当前正在播放，交给播放器内核
      _remaining.add(e.path);
    }
    _entriesByPath = {for (final e in entries) e.path: e};
    _updateBusy();
    if (!_scanning) {
      _scanning = true;
      _run(currentPath: currentPath);
    }
  }

  /// 滚动/拖动窗口/缩放窗口时暂停/恢复后台扫描。暂停期间零探测，彻底消除掉帧。
  static void setPaused(bool paused) {
    _paused = paused;
  }

  /// 页面销毁时停止扫描循环并清场，避免后台 timer/探测泄漏。
  /// 注意：保留 [_cache]（path→组合元数据）跨页面持续有效，重新打开项目可直接命中，
  /// 不重复探测；只清空本轮的待扫/在途集合中状态。
  static void dispose() {
    _stop = true;
    _scanning = false;
    _paused = false;
    _activePath = null;
    _remaining.clear();
    _inflight.clear();
    _entriesByPath = const {};
    _active = 0;
    _updateBusy();
  }

  /// 扫描主循环：单并发、限速、当前优先。直到 [dispose] 前一直存活，
  /// 空闲时仅以 [_poll] 间隔轻量轮询，不会空转占用平台线程。
  static Future<void> _run({String? currentPath}) async {
    while (!_stop) {
      if (_paused) {
        await Future.delayed(_poll);
        continue;
      }
      final path = _pickNext(currentPath);
      if (path == null) {
        // 没有可探测项（可能已全部完成）。轻量轮询，等待新项注入或页面销毁。
        await Future.delayed(_poll);
        continue;
      }
      _inflight.add(path);
      _active = 1;
      _updateBusy();
      AudioMeta? m;
      try {
        m = await probe(path);
      } catch (_) {
        m = null;
      }
      // 探测期间可能发生了 dispose/重新规划：以最新状态为准。
      if (_stop) {
        _inflight.remove(path);
        _active = 0;
        return;
      }
      _cachePut(path, m);
      _inflight.remove(path);
      _remaining.remove(path);
      _active = 0;
      _updateBusy();
      // 直接回填条目，通知挂载中的叶子自更新；离屏叶子未挂载，无所谓重建。
      _entriesByPath[path]?.setMeta(m);
      // 让出平台线程，给正在播放的音频的正常解码留喘息空间。
      await Future.delayed(_gap);
    }
    _scanning = false;
  }

  /// 优先返回当前曲目路径；其次任意「未探测且非当前播放」路径；都没有返回 null。
  static String? _pickNext(String? currentPath) {
    if (currentPath != null &&
        _remaining.contains(currentPath) &&
        !_inflight.contains(currentPath) &&
        currentPath != _activePath) {
      return currentPath;
    }
    for (final p in _remaining) {
      if (_inflight.contains(p) || p == _activePath) continue;
      return p;
    }
    return null;
  }

  static void _updateBusy() {
    final b = _active > 0 || (_remaining.isNotEmpty && !_paused);
    if (busy.value != b) busy.value = b;
  }
}
