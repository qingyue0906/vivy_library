import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import '../models/video_entry.dart';
import '../services/video_metadata_service.dart';
import '../services/video_playlist_service.dart';
import '../services/translations.dart';

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
  bool _showTop = false;
  bool _showBottom = false;
  bool _showPlaylist = true;
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

  Player? _probePlayer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    player = Player();
    controller = VideoController(player);
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
    _startMetadataProbe();
  }

  void _initPlayer() {
    player.stream.completed.listen((_) => _onCompleted());
    player.stream.tracks.listen((_) => _updateCurrentMetaFromPlayer());
    player.stream.duration.listen((_) => _updateCurrentMetaFromPlayer());
    _openCurrent();
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
    final v = player.state.tracks.video;
    if (v.isNotEmpty) {
      final t = v.first;
      meta = meta.copyWith(width: t.w, height: t.h, codec: t.codec, fps: t.fps);
    }
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

  /// 后台渐进探测所有视频元数据：
  /// - 优先用 ffprobe（最快最全）；
  /// - 无 ffprobe 时退化为用单个后台 Player 逐一读取轨道信息。
  void _startMetadataProbe() {
    if (widget.playlist.entries.isEmpty) return;
    _probing = true;
    if (mounted) setState(() {});
    final gen = ++_probeGen;
    () async {
      final ff = await VideoMetadataService.hasFfprobe;
      for (final e in widget.playlist.entries) {
        if (!mounted || gen != _probeGen) return;
        VideoMeta? meta;
        if (ff) {
          meta = await VideoMetadataService.probe(e.path);
        } else {
          meta = await _probeOne(e.path);
        }
        if (meta != null && mounted && gen == _probeGen) {
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

  /// 用后台 Player 读取单个视频的轨道信息（无 ffprobe 时的回退方案）。
  Future<VideoMeta?> _probeOne(String path) async {
    try {
      _probePlayer ??= Player();
      final p = _probePlayer!;
      final completer = Completer<Tracks>();
      late final StreamSubscription sub;
      sub = p.stream.tracks.listen((t) {
        if (!completer.isCompleted) completer.complete(t);
      });
      await p.open(Media(path), play: false);
      final tracks = await completer.future.timeout(const Duration(seconds: 8));
      var meta = const VideoMeta();
      if (tracks.video.isNotEmpty) {
        final t = tracks.video.first;
        meta = meta.copyWith(width: t.w, height: t.h, codec: t.codec, fps: t.fps);
      }
      final w = p.state.width;
      final h = p.state.height;
      if (w != null && h != null) meta = meta.copyWith(width: w, height: h);
      meta = meta.copyWith(duration: p.state.duration);
      await sub.cancel();
      try {
        await p.stop();
      } catch (_) {}
      return meta;
    } catch (_) {
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
    setState(() {});
  }

  void _toggleMute() {
    _muted = !_muted;
    player.setVolume(_muted ? 0 : _volume);
    setState(() {});
  }

  void _cycleRepeat() {
    _repeat = _RepeatMode.values[(_repeat.index + 1) % _RepeatMode.values.length];
    setState(() {});
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
          child: Row(
            children: [
              Expanded(child: _buildPlayerArea(cs)),
              if (_showPlaylist && !_isFullscreen) ...[
                _buildResizeHandle(cs),
                _buildPlaylistPanel(cs),
              ],
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
        if (_isFullscreen) {
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
      onTap: _revealOnTap,
      onDoubleTap: _toggleFullscreen,
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
  /// 整条可拖拽移动窗口（仅标题，避免与底栏按钮重复）。
  Widget _buildTopBar(ColorScheme cs) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: DragToMoveArea(
        child: Container(
          height: 38,
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
    );
  }

  /// 全屏模式下顶部悬浮条：仅显示标题（按钮统一在底部控制条，避免重复）。
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
                IconButton(
                  icon: Icon(_showPlaylist
                      ? Icons.playlist_add_check
                      : Icons.playlist_play),
                  color: iconColor,
                  tooltip: Strings.t('playlist'),
                  onPressed: () =>
                      setState(() => _showPlaylist = !_showPlaylist),
                ),
                IconButton(
                  icon: Icon(
                      _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                  color: iconColor,
                  tooltip: _isFullscreen
                      ? Strings.t('exitFullscreen')
                      : Strings.t('fullscreen'),
                  onPressed: _toggleFullscreen,
                ),
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
                  icon: const Icon(Icons.close),
                  color: Colors.redAccent,
                  tooltip: Strings.t('closePlayer'),
                  onPressed: _close,
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
    return _ProgressSlider(player, cs);
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

  /// 播放区与播放列表之间的可拖拽分隔条：左右拖动改变播放列表宽度。
  Widget _buildResizeHandle(ColorScheme cs) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: (details) {
        // 播放列表在右侧，分隔条左移(dx<0)时列表变宽。
        final next = (_playlistWidth - details.delta.dx).clamp(220.0, 640.0);
        if (next != _playlistWidth) {
          setState(() => _playlistWidth = next);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Container(
          width: 5,
          color: Colors.transparent,
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
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: widget.playlist.tree
                        .map((r) => _treeNode(r, cs, 0))
                        .toList(),
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
                    const SizedBox(height: 2),
                    Text(
                      '${f.meta?.codecText ?? '--'} · ${f.meta?.resolutionText ?? '--'} · ${f.meta?.fpsText ?? '--'}',
                      style:
                          TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
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

/// 进度条组件：独立状态，自身订阅播放位置流。
/// 拖拽期间忽略外部流更新，避免父级重建打断拖拽手势导致进度条卡死。
class _ProgressSlider extends StatefulWidget {
  final Player player;
  final ColorScheme cs;

  const _ProgressSlider(this.player, this.cs);

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
          VideoMeta.formatDuration(position),
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
          VideoMeta.formatDuration(duration),
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
