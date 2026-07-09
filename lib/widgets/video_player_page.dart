import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/src/player/native/player/real.dart' // ignore: implementation_imports
    show NativePlayer;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import '../models/video_entry.dart';
import '../services/video_playlist_service.dart';
import '../services/translations.dart';
import '../services/settings_service.dart';
import 'player_settings_page.dart';
import 'smooth_scroll.dart';

enum _RepeatMode { off, all, one, shuffle }

class VideoPlayerPage extends StatefulWidget {
  final VideoPlaylist playlist;
  final int initialIndex;
  final String title;

  const VideoPlayerPage({
    super.key,
    required this.playlist,
    this.initialIndex = 0,
    required this.title,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with WindowListener {
  late final Player player;
  late final VideoController controller;

  late int _currentIndex;
  bool _isFullscreen = false;
  bool _isMaximized = false;
  bool _showTop = false;
  bool _showBottom = false;
  bool _showPlaylist = true;
  bool _showSettings = false;
  bool _showMilliseconds = false;
  double _playlistWidth = 340;
  Timer? _hideTimer;

  double _volume = 100;
  bool _muted = false;
  double _rate = 1.0;
  _RepeatMode _repeat = _RepeatMode.all;

  /// 已展开的文件夹路径集合（用于树形播放列表的收起/展开）。
  final Set<String> _expanded = {};
  final Random _random = Random();
  bool _probing = false;
  int _probeGen = 0;

  /// 是否使用硬件解码。默认开启；切换时重新载入当前视频以生效。
  bool _useHardwareDecode = true;

  Player? _probePlayer;

  /// 播放列表滚动控制器（配合 SmoothScroll 与 Scrollbar 实现平滑滚动）。
  final ScrollController _playlistScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    player = Player();
    controller = VideoController(player);
    if (widget.playlist.entries.isNotEmpty) _initProbePlayer();
    _currentIndex = widget.initialIndex.clamp(
      0,
      max(0, widget.playlist.entries.length - 1),
    );
    // 默认展开根节点，并展开当前播放视频所在的目录链，保证其可见。
    for (final r in widget.playlist.tree) {
      _expanded.add(r.path);
    }
    if (widget.playlist.entries.isNotEmpty) {
      _ensureExpanded(widget.playlist.entries[_currentIndex]);
    }
    _initPlayer();
    _initPlayback();
    _startMetadataProbe();
    SettingsService.loadPlayerShowMilliseconds()
        .then((v) => setState(() => _showMilliseconds = v));
    SettingsService.loadPlayerShowPlaylist()
        .then((v) => setState(() => _showPlaylist = v));
    SettingsService.loadPlayerPlaylistWidth()
        .then((v) => setState(() => _playlistWidth = v));
    windowManager.isMaximized()
        .then((v) => setState(() => _isMaximized = v));
    // 载入并应用持久化的音量与静音状态。
    () async {
      _volume = await SettingsService.loadPlayerVolume();
      _muted = await SettingsService.loadPlayerMuted();
      player.setVolume(_muted ? 0 : _volume);
      if (mounted) setState(() {});
    }();
  }

  /// 创建后台探测用的 [Player]。
  ///
  /// 关键点：不使用 [VideoController]、**不创建任何视频输出窗口**。
  /// media_kit 的 [Player] 在没挂 [VideoController] 时默认 `vo=null`（解码即丢弃，
  /// 不需要窗口/GPU）。但编码名、分辨率(demux-w/h)、帧率(demux-fps)、时长都来自
  /// 容器解析层(track-list / duration)，无需真正解码画面即可拿到。
  /// 之前把探测挂到离屏的 [VideoController] 上，在 Windows 上需要真实可见窗口初始化
  /// GPU 输出，离屏窗口初始化失败导致文件永远加载不出、元数据永远为空。
  void _initProbePlayer() {
    _probePlayer = Player();
  }

  void _initPlayer() {
    player.stream.completed.listen((_) => _onCompleted());
    player.stream.tracks.listen((_) => _updateCurrentMetaFromPlayer());
    player.stream.duration.listen((_) => _updateCurrentMetaFromPlayer());
  }

  /// 先读取硬件解码偏好并写入 mpv 的 hwdec 选项，再打开当前视频，
  /// 保证解码方式从首次播放起即生效（hwdec 改变需重新载入文件）。
  Future<void> _initPlayback() async {
    _useHardwareDecode = await SettingsService.loadPlayerHardwareDecode();
    await _setHwdecOption(_useHardwareDecode);
    if (!mounted) return;
    setState(() {});
    _openCurrent();
  }

  /// 通过 media_kit 内部 [NativePlayer.setProperty]（公开但未在基类暴露）写入 mpv 的
  /// hwdec 选项。media_kit 未提供公开的解码方式 API，这里走其官方的“escape hatch”。
  Future<void> _setHwdecOption(bool hardware) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty('hwdec', hardware ? 'auto' : 'no');
    } catch (_) {}
  }

  void _openCurrent() {
    if (_currentIndex < 0 || _currentIndex >= widget.playlist.entries.length) {
      return;
    }
    final entry = widget.playlist.entries[_currentIndex];
    player.open(Media(entry.path), play: true);
  }

  /// 当播放器解析出当前视频的轨道信息/分辨率/时长时，回填到播放列表条目。
  void _updateCurrentMetaFromPlayer() {
    if (_currentIndex < 0 || _currentIndex >= widget.playlist.entries.length) {
      return;
    }
    final entry = widget.playlist.entries[_currentIndex];
    var meta = entry.meta ?? const VideoMeta();
    // 取真正的视频轨（跳过 auto/no 占位轨）以拿到干净编码名与 demux 分辨率/帧率。
    final t = _realVideoTrack(player);
    if (t != null) {
      meta = meta.copyWith(codec: t.codec, fps: t.fps);
      if (t.w != null && t.h != null) {
        meta = meta.copyWith(width: t.w, height: t.h);
      }
    }
    // 解码出的真实分辨率（video-params）优先于 demux 分辨率。
    final w = player.state.width;
    final h = player.state.height;
    if (w != null && h != null) {
      meta = meta.copyWith(width: w, height: h);
    }
    final dur = player.state.duration;
    meta = meta.copyWith(duration: dur);
    if (entry.meta != meta) {
      entry.meta = meta;
      if (mounted) setState(() {});
    }
  }

  /// 后台渐进探测所有视频元数据（纯 media_kit，不使用系统 ffprobe）。
  /// 仅用单个无窗口的 [Player] 打开每个文件、读取容器层信息（编码/分辨率/帧率/时长），
  /// 读不到的视频保持 N/A 而非崩溃。当前播放项优先探测。
  void _startMetadataProbe() {
    if (widget.playlist.entries.isEmpty) return;
    _probing = true;
    if (mounted) setState(() {});
    final gen = ++_probeGen;
    () async {
      // 优先探测当前播放项（用户最关心的），其余随后。
      final ordered = [...widget.playlist.entries]
        ..sort((a, b) => _isCurrent(a) == _isCurrent(b)
            ? 0
            : _isCurrent(a)
                ? -1
                : 1);
      for (final e in ordered) {
        if (!mounted || gen != _probeGen) return;
        final meta = await _probeOne(e.path);
        if (meta != null &&
            mounted &&
            gen == _probeGen &&
            (meta.codec != null && meta.codec!.isNotEmpty ||
                meta.width != null && meta.width! > 0 ||
                (meta.duration != null && meta.duration! > Duration.zero))) {
          e.meta = VideoMeta(
            codec: meta.codec ?? e.meta?.codec,
            width: meta.width ?? e.meta?.width,
            height: meta.height ?? e.meta?.height,
            fps: meta.fps ?? e.meta?.fps,
            duration: meta.duration ?? e.meta?.duration,
          );
          setState(() {});
        }
      }
      _probing = false;
      if (mounted) setState(() {});
    }();
  }

  bool _isCurrent(VideoEntry e) =>
      _currentIndex >= 0 &&
      _currentIndex < widget.playlist.entries.length &&
      widget.playlist.entries[_currentIndex] == e;

  /// 从 track-list 中挑出真正的视频轨（跳过 media_kit 永远前置的
  /// [VideoTrack.auto]/[VideoTrack.no] 占位轨，它们的 codec/分辨率/帧率都是 null）。
  VideoTrack? _realVideoTrack(Player p) {
    for (final t in p.state.tracks.video) {
      if (t.codec != null && t.codec!.isNotEmpty) return t;
    }
    return null;
  }

  /// 从后台 Player 的当前状态读取轨道元数据。
  /// track-list 的 [Track.codec] 是干净编码名（av1/h264/hevc 等，而非解码器名）。
  VideoMeta _readMetaFromState(Player p) {
    var meta = const VideoMeta();
    final t = _realVideoTrack(p);
    if (t != null) {
      meta = meta.copyWith(
        codec: t.codec,
        width: t.w,
        height: t.h,
        fps: t.fps,
      );
    }
    final dur = p.state.duration;
    if (dur > Duration.zero) meta = meta.copyWith(duration: dur);
    return meta;
  }

  /// 用后台（无窗口）[Player] 读取单个视频的容器层信息：编码/分辨率/帧率/时长。
  /// 这些均来自 demuxer，无需解码画面，故不挂 [VideoController] 也能拿到。
  Future<VideoMeta?> _probeOne(String path) async {
    try {
      if (_probePlayer == null) {
        _initProbePlayer();
        // media_kit 默认给无窗口 Player 设 --vid=no，需显式选上视频轨，
        // 保证 track-list 解析出编码/分辨率/帧率。
        await _probePlayer!.setVideoTrack(VideoTrack.auto());
      }
      final p = _probePlayer!;
      await p.setVolume(0); // 探测期间不发声
      final completer = Completer<void>();
      late final StreamSubscription sub;
      sub = p.stream.tracks.listen((t) {
        // 必须等到真正的视频轨（有 codec）出现，而非 media_kit 前置的 auto/no 占位轨。
        final hasReal = t.video.any((v) => v.codec != null && v.codec!.isNotEmpty);
        if (hasReal && !completer.isCompleted) completer.complete();
      });
      await p.open(Media(path), play: false);
      // 等待真正有编码的视频轨解析完成。
      try {
        await completer.future.timeout(const Duration(seconds: 5));
      } catch (_) {}
      await sub.cancel();
      var meta = _readMetaFromState(p);
      // 时长有时比 track-list 稍晚到达；若尚未拿到则补等一小段（最多约 3s）。
      if (meta.duration == null || meta.duration == Duration.zero) {
        for (var i = 0; i < 15; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          final m = _readMetaFromState(p);
          if (m.duration != null && m.duration! > Duration.zero) {
            meta = m;
            break;
          }
        }
      }
      try {
        await p.stop();
      } catch (_) {}
      return meta;
    } catch (e) {
      return null;
    }
  }

  void _onCompleted() {
    switch (_repeat) {
      case _RepeatMode.one:
        player.seek(Duration.zero);
        player.play();
      case _RepeatMode.all:
        _next(loop: true);
      case _RepeatMode.shuffle:
        _playRandom();
      case _RepeatMode.off:
        if (_currentIndex < widget.playlist.entries.length - 1) {
          _next();
        }
    }
  }

  void _playIndex(int i) {
    if (i < 0 || i >= widget.playlist.entries.length) return;
    _currentIndex = i;
    _openCurrent();
    _updateCurrentMetaFromPlayer();
    _ensureExpanded(widget.playlist.entries[i]);
    setState(() {});
  }

  void _next({bool loop = false}) {
    if (widget.playlist.entries.isEmpty) return;
    var i = _currentIndex + 1;
    if (i >= widget.playlist.entries.length) {
      i = loop ? 0 : widget.playlist.entries.length - 1;
    }
    _playIndex(i);
  }

  void _prev() {
    if (widget.playlist.entries.isEmpty) return;
    var i = _currentIndex - 1;
    if (i < 0) i = widget.playlist.entries.length - 1;
    _playIndex(i);
  }

  void _playRandom() {
    if (widget.playlist.entries.length <= 1) return;
    int i;
    do {
      i = _random.nextInt(widget.playlist.entries.length);
    } while (i == _currentIndex);
    _playIndex(i);
  }

  void _togglePlay() {
    if (player.state.playing) {
      player.pause();
    } else {
      player.play();
    }
    setState(() {});
  }

  void _changeVolume(double delta) {
    _volume = (_volume + delta).clamp(0, 100);
    _muted = _volume == 0;
    player.setVolume(_volume);
    SettingsService.savePlayerVolume(_volume);
    SettingsService.savePlayerMuted(_muted);
    setState(() {});
  }

  void _toggleMute() {
    _muted = !_muted;
    player.setVolume(_muted ? 0 : _volume);
    SettingsService.savePlayerMuted(_muted);
    setState(() {});
  }

  void _cycleRepeat() {
    _repeat = _RepeatMode.values[(_repeat.index + 1) % _RepeatMode.values.length];
    setState(() {});
  }

  void _toggleDecode() {
    _useHardwareDecode = !_useHardwareDecode;
    SettingsService.savePlayerHardwareDecode(_useHardwareDecode);
    setState(() {});
    _applyHwdec();
  }

  /// 切换硬件/软件解码：mpv 的 hwdec 选项改变需重新载入文件才生效。
  /// 重新打开当前视频并恢复到切换前的播放位置。
  Future<void> _applyHwdec() async {
    if (widget.playlist.entries.isEmpty) return;
    if (_currentIndex < 0 || _currentIndex >= widget.playlist.entries.length) {
      return;
    }
    final pos = player.state.position;
    await _setHwdecOption(_useHardwareDecode);
    final entry = widget.playlist.entries[_currentIndex];
    await player.open(Media(entry.path), play: true);
    if (pos > Duration.zero) {
      // 等待媒体载入后再 seek，避免被重置。
      await player.seek(pos).catchError((_) {});
    }
  }

  /// 真正的 OS 全屏：调用 window_manager 缩放窗口铺满屏幕（隐藏任务栏）。
  Future<void> _toggleFullscreen() async {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        _showTop = false;
        _showBottom = false;
      }
    });
    await windowManager.setFullScreen(_isFullscreen);
  }

  @override
  void onWindowEnterFullScreen() {
    // 进入真全屏后强制重建并常显控件，避免命中测试错位/控件被隐藏。
    if (mounted) {
      setState(() {
        _isFullscreen = true;
        _showTop = false;
        _showBottom = false;
      });
    }
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) {
      setState(() {
        _isFullscreen = false;
        _showTop = false;
        _showBottom = false;
      });
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  /// 全屏模式：按鼠标所在区域（顶部/底部）分别显示对应浮层，静止后自动隐藏。
  void _onHover(PointerHoverEvent event) {
    if (!_isFullscreen) return;
    final h = MediaQuery.of(context).size.height;
    final dy = event.localPosition.dy;
    final topZone = dy < 90;
    final bottomZone = dy > h - 120;
    if (_showTop != topZone || _showBottom != bottomZone) {
      setState(() {
        _showTop = topZone;
        _showBottom = bottomZone;
      });
    }
    _hideTimer?.cancel();
    if (topZone || bottomZone) {
      _hideTimer = Timer(const Duration(seconds: 3), _hideAll);
    }
  }

  void _hideAll() {
    if (mounted) {
      setState(() {
        _showTop = false;
        _showBottom = false;
      });
    }
  }

  /// 点击视频区域临时唤出顶/底栏（全屏模式）。
  void _revealOnTap() {
    if (!_isFullscreen) return;
    setState(() {
      _showTop = true;
      _showBottom = true;
    });
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), _hideAll);
  }

  void _close() {
    if (_isFullscreen) {
      windowManager.setFullScreen(false);
    }
    Navigator.of(context).pop();
  }

  /// 将 [v] 所在目录链上的所有文件夹节点标记为展开，使其可见。
  void _ensureExpanded(VideoEntry v) {
    final dir = v.dirPath;
    void walk(VideoFolderNode n) {
      if (dir == n.path || dir.startsWith(n.path + Platform.pathSeparator)) {
        _expanded.add(n.path);
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    for (final r in widget.playlist.tree) {
      walk(r);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    windowManager.removeListener(this);
    if (_isFullscreen) {
      windowManager.setFullScreen(false);
    }
    _playlistScrollController.dispose();
    _probePlayer?.dispose();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: _onHover,
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(child: _buildPlayerArea(cs)),
                  if (_showPlaylist && !_isFullscreen) ...[
                    _buildResizeHandle(),
                    _buildPlaylistPanel(cs),
                  ],
                ],
              ),
              if (_showSettings)
                Positioned.fill(
                  child: PlayerSettingsPage(
                    showMilliseconds: _showMilliseconds,
                    onMillisecondsChanged: (v) {
                      setState(() => _showMilliseconds = v);
                      SettingsService.savePlayerShowMilliseconds(v);
                    },
                    onBack: () => setState(() => _showSettings = false),
                    trailing: _buildWindowControls(cs, iconColor: cs.onSurface),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 播放区：窗口模式为「顶栏 + 视频 + 底栏」独立成行的竖向布局；
  /// 全屏模式为视频铺满 + 顶/底浮层（半透明，鼠标悬停显示）。
  Widget _buildPlayerArea(ColorScheme cs) {
    if (_isFullscreen) {
      return Stack(
        children: [
          _buildVideoArea(),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showTop ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showTop,
                child: _buildTopOverlay(cs),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showBottom ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showBottom,
                child: _buildControlBar(cs, overlay: true),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        _buildTopBar(cs),
        Expanded(child: _buildVideoArea()),
        _buildControlBar(cs),
      ],
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        _togglePlay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _seekBy(10);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _seekBy(-10);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _changeVolume(10);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _changeVolume(-10);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        if (_showSettings) {
          setState(() => _showSettings = false);
        } else if (_isFullscreen) {
          _toggleFullscreen();
        } else {
          _close();
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _seekBy(int seconds) {
    final pos = player.state.position;
    final dur = player.state.duration;
    final target = pos + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > dur ? dur : target);
    player.seek(clamped);
  }

  Widget _buildVideoArea() {
    return GestureDetector(
      onTap: () {
        _togglePlay();
        _revealOnTap();
      },
      onSecondaryTap: _close,
      child: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Video(
          controller: controller,
          fit: BoxFit.contain,
          controls: null,
        ),
      ),
    );
  }

  /// 窗口模式下的顶栏：跟随主题(surface)，与播放列表(surfaceContainerHigh)区分层次；
  /// 标题区域可拖拽移动窗口，右上角为最小化/最大化/全屏/关闭窗口控件。
  Widget _buildTopBar(ColorScheme cs) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Container(
                height: 32,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Icon(Icons.play_circle_outline, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(fontSize: 13, color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildWindowControls(cs, iconColor: cs.onSurface),
        ],
      ),
    );
  }

  /// 右上角窗口控件：最小化 / 最大化 / 全屏 / 关闭。供窗口顶栏与全屏浮层、设置页复用。
  Widget _buildWindowControls(ColorScheme cs, {required Color iconColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.horizontal_rule),
          color: iconColor,
          iconSize: 18,
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: Strings.t('minimize'),
          onPressed: () => windowManager.minimize(),
        ),
        IconButton(
          icon: Icon(_isMaximized ? Icons.crop_square : Icons.crop_16_9),
          color: iconColor,
          iconSize: 18,
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: Strings.t('maximize'),
          onPressed: _toggleMaximize,
        ),
        IconButton(
          icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
          color: iconColor,
          iconSize: 18,
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: _isFullscreen ? Strings.t('exitFullscreen') : Strings.t('fullscreen'),
          onPressed: _toggleFullscreen,
        ),
        IconButton(
          icon: const Icon(Icons.close),
          color: Colors.redAccent,
          iconSize: 18,
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: Strings.t('closePlayer'),
          onPressed: _close,
        ),
      ],
    );
  }

  /// 全屏模式下顶部悬浮条：显示标题与右上角窗口控件（鼠标靠近顶部时显示）。
  Widget _buildTopOverlay(ColorScheme cs) {
    final current = widget.playlist.entries.isEmpty
        ? null
        : widget.playlist.entries[_currentIndex];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${widget.title}  ·  ${current?.name ?? ''}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _buildWindowControls(cs, iconColor: Colors.white),
        ],
      ),
    );
  }

  /// 底部控制条。窗口模式跟随主题（surface，独立成行）；全屏模式使用半透明深色浮层。
  Widget _buildControlBar(ColorScheme cs, {bool overlay = false}) {
    final current = widget.playlist.entries.isEmpty
        ? null
        : widget.playlist.entries[_currentIndex];
    final playing = player.state.playing;
    // 窗口模式用 surface，与播放列表(surfaceContainerHigh)形成层次；全屏用半透明深色浮层。
    final Color iconColor = overlay ? Colors.white : cs.onSurface;
    return Container(
      decoration: BoxDecoration(
        color: overlay
            ? Colors.black.withValues(alpha: 0.82)
            : cs.surface,
        border: overlay
            ? null
            : Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            iconSize: 20,
            minimumSize: const Size(32, 32),
            padding: const EdgeInsets.all(4),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProgress(cs),
            Row(
              children: [
                IconButton(
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  color: iconColor,
                  tooltip: playing ? Strings.t('pause') : Strings.t('play'),
                  onPressed: _togglePlay,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  color: iconColor,
                  tooltip: Strings.t('prevTrack'),
                  onPressed: _prev,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  color: iconColor,
                  tooltip: Strings.t('nextTrack'),
                  onPressed: () => _next(),
                ),
                _buildVolume(cs, iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    current?.name ?? '',
                    style: TextStyle(
                      color: iconColor.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildSpeedButton(iconColor),
                _buildRepeatButton(iconColor),
                _buildAudioMenu(iconColor),
                _buildSubtitleMenu(iconColor),
                _buildDecodeButton(iconColor),
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  color: iconColor,
                  tooltip: Strings.t('openFolder'),
                  onPressed: _openLocalFolder,
                ),
                IconButton(
                  icon: const Icon(Icons.file_open),
                  color: iconColor,
                  tooltip: Strings.t('openFile'),
                  onPressed: _openLocalFile,
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  color: iconColor,
                  tooltip: Strings.t('playerSettings'),
                  onPressed: () => setState(() => _showSettings = true),
                ),
                IconButton(
                  icon: Icon(_showPlaylist
                      ? Icons.playlist_add_check
                      : Icons.playlist_play),
                  color: iconColor,
                  tooltip: Strings.t('playlist'),
                  onPressed: () {
                    setState(() => _showPlaylist = !_showPlaylist);
                    SettingsService.savePlayerShowPlaylist(_showPlaylist);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 进度条：独立 StatefulWidget，自身订阅 position 流。
  /// 拖拽时暂停外部流更新，避免父级频繁 setState 重建 Slider 导致拖拽中断/卡死。
  Widget _buildProgress(ColorScheme cs) {
    return _ProgressSlider(player, cs, showMilliseconds: _showMilliseconds);
  }

  Widget _buildVolume(ColorScheme cs, Color iconColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(_muted || _volume == 0 ? Icons.volume_off : Icons.volume_up),
          color: iconColor,
          tooltip: Strings.t('mute'),
          onPressed: _toggleMute,
        ),
        SizedBox(
          width: 78,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: _volume,
              max: 100,
              activeColor: cs.primary,
              onChanged: (v) {
                _volume = v;
                _muted = v == 0;
                player.setVolume(v);
                SettingsService.savePlayerVolume(_volume);
                SettingsService.savePlayerMuted(_muted);
                setState(() {});
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedButton(Color iconColor) {
    return PopupMenuButton<double>(
      tooltip: Strings.t('speed'),
      icon: Text(
        '${_rate.toStringAsFixed(2)}x',
        style: TextStyle(color: iconColor, fontSize: 12),
      ),
      itemBuilder: (ctx) {
        return [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map((r) {
          return PopupMenuItem<double>(
            value: r,
            child: Text('${r.toStringAsFixed(2)}x${r == _rate ? '  ✓' : ''}'),
          );
        }).toList();
      },
      onSelected: (r) {
        _rate = r;
        player.setRate(r);
        setState(() {});
      },
    );
  }

  Widget _buildRepeatButton(Color iconColor) {
    IconData icon;
    String tip;
    switch (_repeat) {
      case _RepeatMode.off:
        icon = Icons.repeat_one;
        tip = Strings.t('repeatOff');
      case _RepeatMode.all:
        icon = Icons.repeat;
        tip = Strings.t('repeatAll');
      case _RepeatMode.one:
        icon = Icons.repeat_one_on;
        tip = Strings.t('repeatOne');
      case _RepeatMode.shuffle:
        icon = Icons.shuffle;
        tip = Strings.t('shuffle');
    }
    return IconButton(
      icon: Icon(icon),
      color: iconColor,
      tooltip: tip,
      onPressed: _cycleRepeat,
    );
  }

  Widget _buildAudioMenu(Color iconColor) {
    final tracks = player.state.tracks.audio;
    return PopupMenuButton<AudioTrack>(
      tooltip: Strings.t('audioTrack'),
      icon: Icon(Icons.audiotrack, color: iconColor),
      enabled: tracks.isNotEmpty,
      itemBuilder: (ctx) {
        return [
          PopupMenuItem<AudioTrack>(
            value: AudioTrack.auto(),
            child: const Text('Auto'),
          ),
          ...tracks.map(
            (t) => PopupMenuItem<AudioTrack>(
              value: t,
              child: Text(t.title ?? t.language ?? t.id),
            ),
          ),
        ];
      },
      onSelected: (t) => player.setAudioTrack(t),
    );
  }

  Widget _buildSubtitleMenu(Color iconColor) {
    final tracks = player.state.tracks.subtitle;
    return PopupMenuButton<SubtitleTrack>(
      tooltip: Strings.t('subtitle'),
      icon: Icon(Icons.subtitles, color: iconColor),
      enabled: tracks.isNotEmpty,
      itemBuilder: (ctx) {
        return [
          PopupMenuItem<SubtitleTrack>(
            value: SubtitleTrack.no(),
            child: const Text('Off'),
          ),
          PopupMenuItem<SubtitleTrack>(
            value: SubtitleTrack.auto(),
            child: const Text('Auto'),
          ),
          ...tracks.map(
            (t) => PopupMenuItem<SubtitleTrack>(
              value: t,
              child: Text(t.title ?? t.language ?? t.id),
            ),
          ),
        ];
      },
      onSelected: (t) => player.setSubtitleTrack(t),
    );
  }

  /// 解码方式切换：硬件解码(图标 memory) / 软件解码(图标 computer)。
  /// tooltip 显示当前模式，点击在两者间切换并重新载入当前视频。
  Widget _buildDecodeButton(Color iconColor) {
    final isHw = _useHardwareDecode;
    return IconButton(
      icon: Icon(isHw ? Icons.memory : Icons.computer),
      color: isHw ? iconColor : iconColor.withValues(alpha: 0.55),
      tooltip: isHw ? Strings.t('hardwareDecode') : Strings.t('softwareDecode'),
      onPressed: _toggleDecode,
    );
  }

  /// 播放区与播放列表之间的拖拽热区：平时不可见，悬停时显示一条细高亮线作提示，
  /// 左右拖动改变播放列表宽度。
  Widget _buildResizeHandle() {
    return _ResizeHandle(
      onDrag: (dx) {
        // 播放列表在右侧，热区左移(dx<0)时列表变宽。
        final next = (_playlistWidth - dx).clamp(220.0, 640.0);
        if (next != _playlistWidth) {
          setState(() => _playlistWidth = next);
        }
      },
      onDragEnd: () => SettingsService.savePlayerPlaylistWidth(_playlistWidth),
    );
  }

  Widget _buildPlaylistPanel(ColorScheme cs) {
    return Container(
      width: _playlistWidth,
      color: cs.surfaceContainerHigh,
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(Icons.queue_music, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  Strings.t('playlist'),
                  style: TextStyle(fontSize: 13, color: cs.onSurface),
                ),
                const Spacer(),
                if (_probing)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  '${widget.playlist.entries.length}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.playlist.tree.isEmpty
                ? Center(
                    child: Text(
                      Strings.t('playListEmpty'),
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  )
                : Scrollbar(
                    controller: _playlistScrollController,
                    thumbVisibility: true,
                    child: SmoothScroll(
                      controller: _playlistScrollController,
                      builder: (context, controller, physics) => ListView(
                        controller: controller,
                        physics: physics,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: widget.playlist.tree
                            .map((r) => _treeNode(r, cs, 0))
                            .toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 递归渲染文件夹树节点（含展开/收起）。
  Widget _treeNode(VideoFolderNode node, ColorScheme cs, int depth) {
    final hasKids = node.children.isNotEmpty || node.files.isNotEmpty;
    final expanded = _expanded.contains(node.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasKids
              ? () => setState(() {
                    if (expanded) {
                      _expanded.remove(node.path);
                    } else {
                      _expanded.add(node.path);
                    }
                  })
              : null,
          child: Container(
            padding: EdgeInsets.only(
              left: 8.0 + depth * 14,
              right: 8,
              top: 4,
              bottom: 4,
            ),
            child: Row(
              children: [
                if (hasKids)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 4),
                Icon(
                  expanded ? Icons.folder_open : Icons.folder,
                  size: 16,
                  color: expanded ? cs.primary : Colors.amber.shade400,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(fontSize: 12, color: cs.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasKids && expanded)
          ...[
            for (final c in node.children) _treeNode(c, cs, depth + 1),
            for (final f in node.files) _fileLeaf(f, cs, depth + 1),
          ],
      ],
    );
  }

  /// 树中的文件叶（视频可点击播放；非视频灰显）。
  Widget _fileLeaf(VideoEntry f, ColorScheme cs, int depth) {
    final globalIndex = widget.playlist.entries.indexOf(f);
    final isCurrent = globalIndex == _currentIndex && f.isVideo;
    final playable = f.isVideo;
    return InkWell(
      onTap: playable ? () => _playIndex(globalIndex) : null,
      child: Container(
        decoration: isCurrent
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(color: cs.primary, width: 3),
                ),
                color: cs.primary.withValues(alpha: 0.16),
              )
            : null,
        padding: EdgeInsets.only(
          left: 8.0 + depth * 14 + 14,
          right: 8,
          top: 6,
          bottom: 6,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              playable ? Icons.movie : Icons.insert_drive_file,
              size: 15,
              color: playable
                  ? (isCurrent ? cs.primary : cs.onSurfaceVariant)
                  : cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: playable
                          ? (isCurrent ? cs.primary : cs.onSurface)
                          : cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (playable) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _codecChip(cs, f.meta?.codecText),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${f.meta?.resolutionText ?? '--'} · ${f.meta?.fpsText ?? '--'}',
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${f.meta?.durationText ?? '--'} · ${f.sizeText}',
                      style:
                          TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else
                    Text(
                      f.sizeText,
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            if (isCurrent)
              const Icon(Icons.volume_up, size: 14, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  /// 编码格式：普通文本显示（不再用主题色高亮徽标）。
  Widget _codecChip(ColorScheme cs, String? codec) {
    final label = (codec != null && codec != '--') ? codec : 'N/A';
    return Text(
      label,
      style: TextStyle(
        fontSize: 10,
        color: cs.onSurfaceVariant,
      ),
    );
  }

  Future<void> _openLocalFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path == null) return;
    int size = 0;
    try {
      size = File(path).lengthSync();
    } catch (_) {}
    final name = path.split(RegExp(r'[/\\]')).last;
    final entry = VideoEntry(
      path: path,
      name: name,
      dirPath: File(path).parent.path,
      sizeInBytes: size,
      isVideo: true,
    );
    widget.playlist.entries.add(entry);
    if (widget.playlist.tree.isNotEmpty) {
      widget.playlist.tree.first.files.add(entry);
    }
    setState(() {});
    _playIndex(widget.playlist.entries.length - 1);
    _startMetadataProbe();
  }

  Future<void> _openLocalFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final newPlaylist = await VideoPlaylistService.buildFromPath(dir);
    if (newPlaylist.entries.isEmpty) return;
    widget.playlist.entries
      ..clear()
      ..addAll(newPlaylist.entries);
    widget.playlist.tree
      ..clear()
      ..addAll(newPlaylist.tree);
    _expanded
      ..clear()
      ..addAll(newPlaylist.tree.map((r) => r.path));
    _currentIndex = 0;
    _openCurrent();
    setState(() {});
    _startMetadataProbe();
  }
}

/// 播放区与播放列表之间的可拖拽分隔条。常驻显示一条细线，左/右拖动通过 [onDrag]
/// 回调上报位移量（dx），由父级换算为播放列表宽度；拖拽结束时触发 [onDragEnd]。
class _ResizeHandle extends StatefulWidget {
  final void Function(double dx) onDrag;
  final VoidCallback? onDragEnd;

  const _ResizeHandle({required this.onDrag, this.onDragEnd});

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: (d) => widget.onDrag(d.delta.dx),
      onPanEnd: (_) => widget.onDragEnd?.call(),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: SizedBox(
          width: 5,
          child: Center(
            child: Container(
              width: 1,
              color: cs.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 进度条组件：独立状态，自身订阅播放位置流。
/// 拖拽期间忽略外部流更新，避免父级重建打断拖拽手势导致进度条卡死。
class _ProgressSlider extends StatefulWidget {
  final Player player;
  final ColorScheme cs;
  final bool showMilliseconds;

  const _ProgressSlider(this.player, this.cs, {this.showMilliseconds = false});

  @override
  State<_ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends State<_ProgressSlider> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _dragging = false;
  double _dragValue = 0;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;

  @override
  void initState() {
    super.initState();
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _posSub = widget.player.stream.position.listen((p) {
      if (!_dragging && mounted) setState(() => _position = p);
    });
    _durSub = widget.player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = _duration;
    final position =
        _dragging ? Duration(seconds: _dragValue.round()) : _position;
    final max = duration.inSeconds.toDouble();
    final value = max > 0
        ? position.inSeconds.toDouble().clamp(0, max).toDouble()
        : 0.0;
    return Row(
      children: [
        Text(
          widget.showMilliseconds
              ? VideoMeta.formatClock(position)
              : VideoMeta.formatDuration(position),
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value,
              max: max > 0 ? max : 1.0,
              activeColor: widget.cs.primary,
              onChangeStart: (_) => setState(() => _dragging = true),
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                _dragging = false;
                widget.player.seek(Duration(seconds: v.round()));
              },
            ),
          ),
        ),
        Text(
          widget.showMilliseconds
              ? VideoMeta.formatClock(duration)
              : VideoMeta.formatDuration(duration),
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
