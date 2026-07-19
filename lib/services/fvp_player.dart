import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:fvp/fvp.dart' as fvp;

import '../models/video_entry.dart';
import 'translations.dart';

/// 基于 fvp (libmdk) 的播放器封装，对外暴露与 media_kit [Player] 近似的接口，
/// 让播放页只做“调用替换”而不必关心 video_player / fvp 后端细节。
///
/// 关键：元数据（编码/分辨率/帧率/时长/音轨/字幕轨）全部来自 fvp 的
/// [VideoPlayerController.getMediaInfo()]（libmdk MediaInfo），不依赖任何外部工具。
class FvpPlayer {
  VideoPlayerController? _controller;

  // 各平台硬件解码器优先级（与 fvp 默认列表一致，软件解码则用纯 FFmpeg）。
  static final Map<String, List<String>> _hwDecoders = {
    'windows': ['MFT:d3d=11', 'D3D11', 'DXVA', 'CUDA', 'FFmpeg', 'dav1d'],
    'linux': ['VAAPI', 'CUDA', 'VDPAU', 'FFmpeg', 'dav1d'],
    'macos': ['VT', 'FFmpeg', 'dav1d'],
  };
  static const List<String> _swDecoders = ['FFmpeg'];

  bool _useHardwareDecode = true;

  // 暂存音量(0-100)与倍速，open 完成前设置的也应在 initialize 后应用。
  double _volume = 100.0;
  double _rate = 1.0;

  // 当前已注册的外置音频文件路径（同名音频文件），供音轨菜单列为「外部」轨。
  List<String> _externalAudioPaths = const [];
  // 当前音频选择：null = 自动(默认首条音轨)；int = 指定轨索引；_audioOff = 关闭音频。
  int? _activeAudioIndex;
  bool _audioOff = false;

  // 音轨待落实标记：默认轨（含内嵌/外置）在打开早期 setAudioTracks 可能被 libmdk
  // 忽略，播放后启动重试循环周期性重设直到生效。无待落实轨时为 false，零副作用。
  bool _pendingAudioSelection = false;
  // 重试循环要落实的目标音轨索引，与显示态 [_activeAudioIndex](null=Auto) 解耦：
  // 重试时必须携带真实索引，不能用「Auto」这种无具体索引的状态。
  int? _pendingAudioTarget;
  // 选择令牌：每次打开/切换/取消重试都自增，让上一次未结束的重试循环自行退出，
  // 避免多次打开或切轨时并发叠加。
  int _selectionToken = 0;

  final _positionCtl = StreamController<Duration>.broadcast();
  final _durationCtl = StreamController<Duration>.broadcast();
  final _playingCtl = StreamController<bool>.broadcast();
  final _completedCtl = StreamController<void>.broadcast();
  final _tracksCtl = StreamController<FvpTracks>.broadcast();

  FvpTracks _tracks = const FvpTracks();
  FvpPlayerState _state = const FvpPlayerState();
  Duration _lastPos = Duration.zero;
  Duration _lastDur = Duration.zero;
  bool _lastPlaying = false;
  bool _completedFired = false;

  /// 供 [VideoPlayer] 控件使用。未 open 时为 null。
  VideoPlayerController? get controller => _controller;

  bool get isInitialized => _controller?.value.isInitialized ?? false;

  FvpPlayerState get state => _state;

  /// 当前选中的音轨索引；null = 自动(首条音轨)。仅供音轨菜单显示打勾状态。
  int? get activeAudioIndex => _activeAudioIndex;

  /// 是否处于「关闭音频」状态。仅供音轨菜单显示打勾状态。
  bool get audioDisabled => _audioOff;

  /// 已注册的外置音频文件路径列表。
  List<String> get externalAudioPaths => _externalAudioPaths;

  Stream<Duration> get positionStream => _positionCtl.stream;
  Stream<Duration> get durationStream => _durationCtl.stream;
  Stream<bool> get playingStream => _playingCtl.stream;
  Stream<void> get completedStream => _completedCtl.stream;
  Stream<FvpTracks> get tracksStream => _tracksCtl.stream;

  /// 打开并（可选）立即播放一个媒体文件。
  /// [externalAudio] 为同名外置音频文件路径列表（由 [findExternalAudio] 得出），
  /// 会注册为「外部音轨」（libmdk 负责与视频时钟对齐同步播放），并在音轨菜单以
  /// 「外部」标识列出。切换文件时复用式地创建新 controller，旧 controller 延后一帧释放。
  Future<void> open(String path,
      {bool play = true, List<String> externalAudio = const []}) async {
    final old = _controller;
    final c = VideoPlayerController.file(File(path));
    _controller = c;
    // 取消上一次打开遗留的音轨重试循环，避免它作用于新 controller。
    _selectionToken++;
    _pendingAudioSelection = false;
    // 必须在 initialize()（打开媒体）之前设置解码器，否则本次打开会回退到默认
    // auto 选择：在 Windows 上可能落到低效解码路径，表现为「一帧一帧」卡顿；
    // 而重播因前次已写入解码器列表才流畅。
    c.setVideoDecoders(_useHardwareDecode ? _currentHwList : _swDecoders);
    try {
      await c.initialize();
    } catch (e) {
      // 打开/初始化失败（如不受支持的音频格式 midi）：
      // 必须把上一首仍在播放的 controller 释放掉，否则它会在后台继续播放，
      // 反复切换会叠加多路音频，且退出播放器时旧 controller 不会被释放、不会停止。
      _controller = null;
      await c.dispose(); // 释放本次新建但未初始化成功的 controller
      if (old != null) {
        // 等当前帧把旧 VideoPlayer 控件卸载后再释放旧 controller，停止后台播放。
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      // 复位状态，避免播放控件仍显示“正在播放”。
      _lastPos = Duration.zero;
      _lastDur = Duration.zero;
      _lastPlaying = false;
      _audioOff = false;
      _activeAudioIndex = null;
      _externalAudioPaths = const [];
      _state = const FvpPlayerState();
      _positionCtl.add(Duration.zero);
      _durationCtl.add(Duration.zero);
      _playingCtl.add(false);
      rethrow; // 让上层提示“无法播放该文件”。
    }
    c.addListener(_onUpdate);
    // 应用已暂存的音量/倍速，保证 open 前设置的值不丢失。
    // 注意：解码器已移至 initialize() 之前设置，勿在此处重复 setVideoDecoders。
    c.setVolume(_volume / 100);
    c.setPlaybackSpeed(_rate);
    _completedFired = false;
    // 先读取内嵌音轨（此时尚未加外置音频，计数不含外置）。
    final embedded = _readAudioTracks(c);
    // 逐个把同名外置音频注册为外部音轨；单个失败不影响其余与播放。
    _externalAudioPaths = <String>[];
    final externalTracks = <FvpTrack>[];
    for (final ext in externalAudio) {
      try {
        // fvp 原生层对外部音频 URI 不做 decode（与主视频 _toUri 对 file 的处理
        // 不一致）。主视频走的是解码后的原始路径，故这里也传解码后的路径，
        // 避免中文/全角标点被百分号编码导致 libmdk 打不开文件、外部轨为空。
        c.setExternalAudio(Uri.decodeComponent(Uri.file(ext).toString()));
        _externalAudioPaths.add(ext);
        // 外部轨在 libmdk 中与主音轨共用同一索引空间，按「内嵌数 + i」续编。
        // mediaInfo 不会回显外部轨，故直接用合成索引，播放后用重试落实选中。
        externalTracks.add(FvpTrack(
          index: embedded.length + externalTracks.length,
          title: ext.split(RegExp(r'[/\\]')).last,
          external: true,
        ));
      } catch (_) {
        // 忽略无效的外置音频文件。
      }
    }
    _buildTracks(c, embedded, externalTracks);
    _applyDefaultAudioSelection();
    _emitState();
    if (old != null) {
      // 等当前帧把旧 VideoPlayer 控件卸载后再释放旧 controller。
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    if (play) await c.play();
    // 外置音频由 libmdk 异步加载，播放前 setAudioTracks 选中的轨可能尚未就绪被忽略。
    // 播放开始后再周期性重试让目标轨生效；非阻塞，不影响开头播放。
    _requestAudioSelection();
  }

  List<String> get _currentHwList =>
      _hwDecoders[Platform.operatingSystem] ?? _swDecoders;

  /// 当前平台的硬件解码器列表（默认启用）。供 [fvp.registerWith] 全局预设兜底，
  /// 让未显式 setVideoDecoders 的离屏探测（如元数据扫描 probeVideoMeta）也走硬件解码。
  static List<String> get defaultHardwareDecoders =>
      _hwDecoders[Platform.operatingSystem] ?? _swDecoders;

  /// 视作「同名外置音频」的扩展名白名单（按常见度排序）。
  /// 与视频自身后缀相同者会被跳过（避免把视频本身当外置音轨）。
  static const List<String> _audioExtensions = [
    'm4a', 'aac', 'mp3', 'opus', 'ogg', 'flac', 'wav', 'wma', 'ape',
    'ac3', 'eac3', 'dts', 'mka', 'wv', 'tta', 'mp2', 'mpa', 'aiff', 'caf',
  ];

  /// 查找与 [videoPath] 同目录、同名(去后缀)、不同后缀的音频文件。
  /// 返回按白名单顺序命中的全部路径（可能多条，如同时存在 .mp3 与 .flac）。
  static List<String> findExternalAudio(String videoPath) {
    final file = File(videoPath);
    final dir = file.parent;
    final fileName = videoPath.split(RegExp(r'[/\\]')).last;
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return const [];
    final nameNoExt = fileName.substring(0, dot);
    final videoExt = fileName.substring(dot + 1).toLowerCase();
    final results = <String>[];
    if (!dir.existsSync()) return results;
    for (final ext in _audioExtensions) {
      if (ext == videoExt) continue;
      final candidate =
          '${dir.path}${Platform.pathSeparator}$nameNoExt.$ext';
      if (File(candidate).existsSync()) results.add(candidate);
    }
    return results;
  }

  Future<void> play() async {
    await _controller?.play();
    // 覆盖 open(play:false) 后手动恢复播放的场景，确保外部轨在真正播放时被落实。
    _requestAudioSelection();
  }
  Future<void> pause() async => _controller?.pause();

  /// [v] 为 0–100，映射到 video_player 的 0–1。暂存以便 open 时应用。
  /// 关闭音频期间不把音量透传到 controller（避免拖动音量条意外解除「关闭音频」）。
  void setVolume(double v) {
    _volume = v.clamp(0, 100);
    if (!_audioOff) _controller?.setVolume(_volume / 100);
  }

  Future<void> setRate(double r) async {
    _rate = r;
    await _controller?.setPlaybackSpeed(r);
  }

  Future<void> seek(Duration pos) async => _controller?.seekTo(pos);

  /// 设置硬件/软件解码偏好；实际生效在下次 [open]（与 media_kit hwdec 行为一致）。
  void setHardwareDecode(bool hardware) => _useHardwareDecode = hardware;

  bool get useHardwareDecode => _useHardwareDecode;

  /// 选择音轨：null = 自动（默认首条音轨，优先内嵌），否则按 [FvpTrack.index]。
  ///
  /// 手动选择发生在音轨已加载(正在播放)之后，setAudioTracks 立即生效，无需重试；
  /// 重试仅在 [open] 早期针对「外置轨异步加载未就绪」启用，避免手动切换时反复调用
  /// setAudioTracks 触发流重配导致卡顿。
  void setAudioTrackIndex(int? index) {
    _audioOff = false;
    _selectionToken++;
    // 恢复音量：关闭音频是经由 setVolume(0) 静音的，切回时若仍为 0 则依旧无声。
    _controller?.setVolume(_volume / 100);
    if (index == null) {
      final first = _tracks.audio.isNotEmpty ? _tracks.audio.first : null;
      _activeAudioIndex = null;
      final target = first?.index;
      _pendingAudioTarget = target;
      _controller?.setAudioTracks(target != null ? [target] : const []);
    } else {
      _activeAudioIndex = index;
      _pendingAudioTarget = index;
      _controller?.setAudioTracks([index]);
    }
    // 手动选择已加载的音轨立即生效，不再进入重试循环（也避免覆盖 open 早期的外置重试）。
    _pendingAudioSelection = false;
  }

  /// 关闭音频（音量静音，不停止视频，也不卸载外置音频轨）。
  /// 注意：不能用 setAudioTracks([]) 静音——libmdk 会因此卸载外置音频轨，
  /// 导致「关闭→再开」后外置 .m4a 无法恢复出声。音量 0 静音可保留轨绑定，
  /// 恢复音量即重新出声。
  void disableAudio() {
    _audioOff = true;
    _controller?.setVolume(0);
  }

  /// 选择字幕轨：null = 关闭，否则按 [FvpTrack.index]。
  void setSubtitleTrackIndex(int? index) {
    if (index == null) {
      _controller?.setSubtitleTracks(const []);
    } else {
      _controller?.setSubtitleTracks([index]);
    }
  }

  /// 当前媒体的元数据快照（编码/分辨率/帧率/时长），来自 getMediaInfo()。
  VideoMeta? snapshotVideoMeta() {
    final c = _controller;
    if (c == null) return null;
    return _map(c.getMediaInfo(), c.value.duration);
  }

  void _onUpdate() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    if (v.position != _lastPos) {
      _lastPos = v.position;
      _positionCtl.add(v.position);
    }
    if (v.duration != _lastDur) {
      _lastDur = v.duration;
      _durationCtl.add(v.duration);
    }
    if (v.isPlaying != _lastPlaying) {
      _lastPlaying = v.isPlaying;
      _playingCtl.add(v.isPlaying);
    }
    _checkCompleted(v);
    _state = FvpPlayerState(
      position: v.position,
      duration: v.duration,
      playing: v.isPlaying,
      width: v.size.width > 0 ? v.size.width.round() : null,
      height: v.size.height > 0 ? v.size.height.round() : null,
      tracks: _tracks,
    );
  }

  void _checkCompleted(VideoPlayerValue v) {
    if (v.duration > Duration.zero &&
        v.isPlaying &&
        v.position >= v.duration - const Duration(milliseconds: 300)) {
      if (!_completedFired) {
        _completedFired = true;
        _completedCtl.add(null);
      }
    } else if (v.position < v.duration - const Duration(milliseconds: 800)) {
      _completedFired = false;
    }
  }

  /// 读取内嵌音轨（来自 getMediaInfo，不含外置音频）。
  ///
  /// 关键：setAudioTracks 底层是 libmdk 的 setActiveTracks(Audio, {n})，其 tracks
  /// 参数为「音频轨内 0 起相对序号」(track number 0~N)；而 mediaInfo.audio[].index
  /// 是 libmdk 的全局流序号（视频流为 0 时，首条音轨通常为 1）。若直接把全局序号传
  /// 进去，会选到不存在/错误的音轨→被 libmdk 忽略默认轨→静音。因此这里改用列表位置
  /// (音频相对序号) 作为 index，与外置轨合成索引(embedded.length + i)保持同一套编号。
  static List<FvpTrack> _readAudioTracks(VideoPlayerController c) {
    final info = c.getMediaInfo();
    final list = <FvpTrack>[];
    final a = info?.audio as List?;
    if (a != null) {
      for (int i = 0; i < a.length; i++) {
        final s = a[i];
        list.add(FvpTrack(
          index: i, // 音频轨内相对序号(0 起)，而非全局流序号 s.index
          title: _meta(s.metadata, 'title'),
          language: _meta(s.metadata, 'language'),
          codec: s.codec?.codec as String?,
        ));
      }
    }
    return list;
  }

  /// 读取内嵌字幕轨（来自 getMediaInfo）。
  static List<FvpTrack> _readSubtitleTracks(VideoPlayerController c) {
    final info = c.getMediaInfo();
    final list = <FvpTrack>[];
    final su = info?.subtitle as List?;
    if (su != null) {
      for (final s in su) {
        list.add(FvpTrack(
          index: s.index as int,
          title: _meta(s.metadata, 'title'),
          language: _meta(s.metadata, 'language'),
          codec: s.codec?.codec as String?,
        ));
      }
    }
    return list;
  }

  /// 合成完整音轨列表：内嵌在前（来自 getMediaInfo），外置音频（带真实索引）续在后。
  void _buildTracks(
      VideoPlayerController c, List<FvpTrack> embedded, List<FvpTrack> external) {
    final audio = <FvpTrack>[...embedded, ...external];
    _tracks = FvpTracks(audio: audio, subtitle: _readSubtitleTracks(c));
    _tracksCtl.add(_tracks);
  }

  /// 让 libmdk 真正落实「当前想用的音轨」。外置音频在播放开始后才异步加载，
  /// 播放前 setAudioTracks 选中的轨可能尚未就绪被忽略；这里周期性重设直到超时被打断。
  /// 仅在有音轨待落实时启用（_pendingAudioSelection），普通场景不重试、零副作用。
  /// 用 _selectionToken 取消上一次未结束的重试，避免并发叠加。
  void _requestAudioSelection() {
    if (!_pendingAudioSelection || _audioOff) return;
    _selectionToken++;
    final token = _selectionToken;
    _ensureAudioSelection(token);
  }

  Future<void> _ensureAudioSelection(int token) async {
    final c = _controller;
    if (c == null) return;
    final deadline = DateTime.now().add(const Duration(milliseconds: 1500));
    while (DateTime.now().isBefore(deadline)) {
      if (token != _selectionToken) return; // 被新的选择/打开覆盖
      if (_controller != c) return; // 已切换或释放
      if (_audioOff) return; // 用户关闭音频
      if (!_pendingAudioSelection) return; // 手动选了其它轨
      // 每轮按目标轨重试；libmdk 加载好音轨后该调用才会真正生效。
      // 用 _pendingAudioTarget 携带真实索引，避免「Auto」(null) 退化为 0 选错轨。
      c.setAudioTracks([_pendingAudioTarget ?? _activeAudioIndex ?? 0]);
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  /// 落实默认音轨选择：
  /// - 无内嵌音轨且有外置 → 默认选中第一条外置；外部轨异步加载，打开早期
  ///   setAudioTracks 可能被忽略，故显式选中并进入重试循环兜底；
  /// - 其余（有内嵌 / 只有内嵌）→ Auto（首条内嵌音轨），**不调用 setAudioTracks**：
  ///   libmdk 默认即播首条内嵌轨；打开早期用错误/未就绪序号调用会丢弃默认轨→静音，
  ///   且重试循环反复调用会触发流重配→再现 00c6f5ff 修复的一帧一帧卡顿。
  void _applyDefaultAudioSelection() {
    _audioOff = false;
    final externalTracks = _tracks.audio.where((t) => t.external).toList();
    final embeddedCount = _tracks.audio.length - externalTracks.length;
    if (embeddedCount == 0 && externalTracks.isNotEmpty) {
      // 无内嵌音轨：默认选中第一条外置轨。外部音频异步加载，播放前 setAudioTracks
      // 可能因轨未就绪被忽略，故启用重试循环，待 libmdk 加载好后落实选中。
      _activeAudioIndex = externalTracks.first.index;
      _pendingAudioTarget = externalTracks.first.index;
      _controller?.setAudioTracks([externalTracks.first.index]);
      _pendingAudioSelection = true;
    } else {
      // 有内嵌/只有内嵌：Auto（首条内嵌音轨）。不调用 setAudioTracks——交还 libmdk
      // 默认行为即可出声，且避免重试循环在首开期间反复触发流重配导致卡顿复发。
      _activeAudioIndex = null; // Auto：交给 libmdk 默认首条内嵌轨
      _pendingAudioTarget = null;
      _pendingAudioSelection = false;
    }
  }

  void _emitState() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    _lastPos = v.position;
    _lastDur = v.duration;
    _lastPlaying = v.isPlaying;
    _positionCtl.add(v.position);
    _durationCtl.add(v.duration);
    _playingCtl.add(v.isPlaying);
    _state = FvpPlayerState(
      position: v.position,
      duration: v.duration,
      playing: v.isPlaying,
      width: v.size.width > 0 ? v.size.width.round() : null,
      height: v.size.height > 0 ? v.size.height.round() : null,
      tracks: _tracks,
    );
  }

  static String? _meta(dynamic metadata, String key) {
    if (metadata is Map) {
      final v = metadata[key];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  /// 把 libmdk MediaInfo 映射为 [VideoMeta]。用 dynamic 避免直接依赖 mdk 类型。
  static VideoMeta? _map(dynamic info, Duration fallbackDuration) {
    if (info == null) return null;
    final videos = info.video as List?;
    final v = videos != null && videos.isNotEmpty ? videos.first : null;
    final codec = v?.codec?.codec as String?;
    final width = v?.codec?.width as int?;
    final height = v?.codec?.height as int?;
    final fps = v?.codec?.frameRate as double?;
    final durRaw = info.duration;
    Duration? duration =
        durRaw is int && durRaw > 0 ? Duration(milliseconds: durRaw) : null;
    if (duration == null || duration == Duration.zero) {
      if (fallbackDuration > Duration.zero) duration = fallbackDuration;
    }
    if (codec == null &&
        width == null &&
        height == null &&
        fps == null &&
        duration == null) {
      return null;
    }
    return VideoMeta(
      codec: codec,
      width: width,
      height: height,
      fps: fps,
      duration: duration,
    );
  }

  /// 离屏探测单个文件的元数据：创建临时 controller → initialize → getMediaInfo → 释放。
  /// 不挂载 VideoPlayer 控件，等价于 media_kit 的无窗口探测，但只需一次 getMediaInfo 调用。
  static Future<VideoMeta?> probeVideoMeta(String path) async {
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      return _map(c.getMediaInfo(), c.value.duration);
    } catch (_) {
      return null;
    } finally {
      await c.dispose();
    }
  }

  Future<void> dispose() async {
    await _positionCtl.close();
    await _durationCtl.close();
    await _playingCtl.close();
    await _completedCtl.close();
    await _tracksCtl.close();
    await _controller?.dispose();
    _controller = null;
  }
}

/// 与 media_kit [PlayerState] 近似的快照。
class FvpPlayerState {
  final Duration position;
  final Duration duration;
  final bool playing;
  final int? width;
  final int? height;
  final FvpTracks tracks;

  const FvpPlayerState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.width,
    this.height,
    this.tracks = const FvpTracks(),
  });
}

class FvpTracks {
  final List<FvpTrack> audio;
  final List<FvpTrack> subtitle;

  const FvpTracks({this.audio = const [], this.subtitle = const []});
}

class FvpTrack {
  final int index;
  final String? title;
  final String? language;
  final String? codec;
  final bool external;

  const FvpTrack({
    required this.index,
    this.title,
    this.language,
    this.codec,
    this.external = false,
  });

  String get label =>
      external && title != null && title!.isNotEmpty
          ? '$title  ·  ${Strings.t('externalAudio')}'
          : [title, language, codec]
              .where((e) => e != null && e.isNotEmpty)
              .join(' · ');
}
