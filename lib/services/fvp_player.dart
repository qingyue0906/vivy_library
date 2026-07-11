import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:fvp/fvp.dart' as fvp;

import '../models/video_entry.dart';

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

  Stream<Duration> get positionStream => _positionCtl.stream;
  Stream<Duration> get durationStream => _durationCtl.stream;
  Stream<bool> get playingStream => _playingCtl.stream;
  Stream<void> get completedStream => _completedCtl.stream;
  Stream<FvpTracks> get tracksStream => _tracksCtl.stream;

  /// 打开并（可选）立即播放一个媒体文件。
  /// 切换文件时复用式地创建新 controller，旧 controller 延后一帧释放，避免控件引用已释放对象。
  Future<void> open(String path, {bool play = true}) async {
    final old = _controller;
    final c = VideoPlayerController.file(File(path));
    _controller = c;
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
      _state = const FvpPlayerState();
      _positionCtl.add(Duration.zero);
      _durationCtl.add(Duration.zero);
      _playingCtl.add(false);
      rethrow; // 让上层提示“无法播放该文件”。
    }
    c.addListener(_onUpdate);
    // 应用解码偏好（on-the-fly 切换；软件解码需随后重载，由调用方负责 open 当前项）。
    c.setVideoDecoders(_useHardwareDecode ? _currentHwList : _swDecoders);
    // 应用已暂存的音量/倍速，保证 open 前设置的值不丢失。
    c.setVolume(_volume / 100);
    c.setPlaybackSpeed(_rate);
    _completedFired = false;
    _updateTracks();
    _emitState();
    if (old != null) {
      // 等当前帧把旧 VideoPlayer 控件卸载后再释放旧 controller。
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    if (play) await c.play();
  }

  List<String> get _currentHwList =>
      _hwDecoders[Platform.operatingSystem] ?? _swDecoders;

  Future<void> play() async => _controller?.play();
  Future<void> pause() async => _controller?.pause();

  /// [v] 为 0–100，映射到 video_player 的 0–1。暂存以便 open 时应用。
  void setVolume(double v) {
    _volume = v.clamp(0, 100);
    _controller?.setVolume(_volume / 100);
  }

  Future<void> setRate(double r) async {
    _rate = r;
    await _controller?.setPlaybackSpeed(r);
  }

  Future<void> seek(Duration pos) async => _controller?.seekTo(pos);

  /// 设置硬件/软件解码偏好；实际生效在下次 [open]（与 media_kit hwdec 行为一致）。
  void setHardwareDecode(bool hardware) => _useHardwareDecode = hardware;

  bool get useHardwareDecode => _useHardwareDecode;

  /// 选择音轨：null = 自动（默认首条），否则按 [FvpTrack.index]。
  void setAudioTrackIndex(int? index) {
    if (index == null) {
      final first = _tracks.audio.isNotEmpty ? _tracks.audio.first.index : null;
      _controller?.setAudioTracks(first != null ? [first] : const []);
    } else {
      _controller?.setAudioTracks([index]);
    }
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

  void _updateTracks() {
    final c = _controller;
    if (c == null) return;
    final info = c.getMediaInfo();
    if (info == null) return;
    final audio = <FvpTrack>[];
    final a = info.audio as List?;
    if (a != null) {
      for (final s in a) {
        audio.add(FvpTrack(
          index: s.index as int,
          title: _meta(s.metadata, 'title'),
          language: _meta(s.metadata, 'language'),
          codec: s.codec?.codec as String?,
        ));
      }
    }
    final sub = <FvpTrack>[];
    final su = info.subtitle as List?;
    if (su != null) {
      for (final s in su) {
        sub.add(FvpTrack(
          index: s.index as int,
          title: _meta(s.metadata, 'title'),
          language: _meta(s.metadata, 'language'),
          codec: s.codec?.codec as String?,
        ));
      }
    }
    _tracks = FvpTracks(audio: audio, subtitle: sub);
    _tracksCtl.add(_tracks);
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

  const FvpTrack({
    required this.index,
    this.title,
    this.language,
    this.codec,
  });

  String get label =>
      [title, language, codec].where((e) => e != null && e.isNotEmpty).join(' · ');
}
