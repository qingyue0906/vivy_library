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
  bool _showControls = true;
  bool _showPlaylist = true;
  Timer? _hideTimer;

  double _volume = 100;
  bool _muted = false;
  double _rate = 1.0;
  _RepeatMode _repeat = _RepeatMode.all;

  VideoFolderNode? _selectedFolder;
  final Random _random = Random();
  bool _probing = false;

  bool _dragging = false;
  double _dragValue = 0;

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
    if (widget.playlist.tree.isNotEmpty) {
      _selectedFolder = widget.playlist.tree.first;
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

  /// 后台渐进探测所有视频元数据（优先 ffprobe）。
  void _startMetadataProbe() {
    if (widget.playlist.entries.isEmpty) return;
    _probing = true;
    if (mounted) setState(() {});
    () async {
      for (final e in widget.playlist.entries) {
        if (!mounted) return;
        final meta = await VideoMetadataService.probe(e.path);
        if (meta != null && mounted) {
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

  Future<void> _toggleFullscreen() async {
    _isFullscreen = !_isFullscreen;
    await windowManager.setFullScreen(_isFullscreen);
    setState(() {});
  }

  void _onMouseMove() {
    if (!_showControls) setState(() => _showControls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _close() {
    if (_isFullscreen) {
      windowManager.setFullScreen(false);
    }
    Navigator.of(context).pop();
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullscreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullscreen = false);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    windowManager.removeListener(this);
    if (_isFullscreen) {
      windowManager.setFullScreen(false);
    }
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
          onHover: (_) => _onMouseMove(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: _buildVideoArea()),
                    AnimatedOpacity(
                      opacity: (!_isFullscreen || _showControls) ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: _buildControlBar(cs),
                    ),
                  ],
                ),
              ),
              if (_showPlaylist && !_isFullscreen) _buildPlaylistPanel(cs),
            ],
          ),
        ),
      ),
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
    final current = widget.playlist.entries.isEmpty
        ? null
        : widget.playlist.entries[_currentIndex];
    return Stack(
      children: [
        GestureDetector(
          onTap: _onMouseMove,
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
        ),
        Positioned(
          top: 8,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${widget.title}  ·  ${current?.name ?? ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlBar(ColorScheme cs) {
    final current = widget.playlist.entries.isEmpty
        ? null
        : widget.playlist.entries[_currentIndex];
    final playing = player.state.playing;
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        children: [
          _buildProgress(cs),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                color: Colors.white,
                tooltip: playing ? Strings.t('pause') : Strings.t('play'),
                onPressed: _togglePlay,
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous),
                color: Colors.white,
                tooltip: Strings.t('prevTrack'),
                onPressed: _prev,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                color: Colors.white,
                tooltip: Strings.t('nextTrack'),
                onPressed: () => _next(),
              ),
              _buildVolume(cs),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  current?.name ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildSpeedButton(),
              _buildRepeatButton(),
              _buildAudioMenu(),
              _buildSubtitleMenu(),
              IconButton(
                icon: Icon(_showPlaylist ? Icons.playlist_add_check : Icons.playlist_play),
                color: Colors.white,
                tooltip: Strings.t('playlist'),
                onPressed: () => setState(() => _showPlaylist = !_showPlaylist),
              ),
              IconButton(
                icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                color: Colors.white,
                tooltip: _isFullscreen ? Strings.t('exitFullscreen') : Strings.t('fullscreen'),
                onPressed: _toggleFullscreen,
              ),
              IconButton(
                icon: const Icon(Icons.folder_open),
                color: Colors.white,
                tooltip: Strings.t('openFolder'),
                onPressed: _openLocalFolder,
              ),
              IconButton(
                icon: const Icon(Icons.file_open),
                color: Colors.white,
                tooltip: Strings.t('openFile'),
                onPressed: _openLocalFile,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                color: Colors.red,
                tooltip: Strings.t('closePlayer'),
                onPressed: _close,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(ColorScheme cs) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (context, posSnap) {
        return StreamBuilder<Duration?>(
          stream: player.stream.duration,
          builder: (context, durSnap) {
            final duration = durSnap.data ?? Duration.zero;
            final position = _dragging
                ? Duration(seconds: _dragValue.round())
                : (posSnap.data ?? Duration.zero);
            final max = duration.inSeconds.toDouble();
            final value = max > 0 ? position.inSeconds.toDouble().clamp(0, max).toDouble() : 0.0;
            return Row(
              children: [
                Text(
                  VideoMeta.formatDuration(position),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Expanded(
                  child: Slider(
                    value: value,
                    max: max > 0 ? max : 1.0,
                    activeColor: cs.primary,
                    onChangeStart: (_) => setState(() => _dragging = true),
                    onChanged: (v) => setState(() => _dragValue = v),
                    onChangeEnd: (v) {
                      _dragging = false;
                      player.seek(Duration(seconds: v.round()));
                    },
                  ),
                ),
                Text(
                  VideoMeta.formatDuration(duration),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildVolume(ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(_muted || _volume == 0 ? Icons.volume_off : Icons.volume_up),
          color: Colors.white,
          tooltip: Strings.t('mute'),
          onPressed: _toggleMute,
        ),
        SizedBox(
          width: 90,
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
      ],
    );
  }

  Widget _buildSpeedButton() {
    return PopupMenuButton<double>(
      tooltip: Strings.t('speed'),
      icon: Text(
        '${_rate.toStringAsFixed(2)}x',
        style: const TextStyle(color: Colors.white, fontSize: 12),
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

  Widget _buildRepeatButton() {
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
      color: Colors.white,
      tooltip: tip,
      onPressed: _cycleRepeat,
    );
  }

  Widget _buildAudioMenu() {
    final tracks = player.state.tracks.audio;
    return PopupMenuButton<AudioTrack>(
      tooltip: Strings.t('audioTrack'),
      icon: const Icon(Icons.audiotrack, color: Colors.white),
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

  Widget _buildSubtitleMenu() {
    final tracks = player.state.tracks.subtitle;
    return PopupMenuButton<SubtitleTrack>(
      tooltip: Strings.t('subtitle'),
      icon: const Icon(Icons.subtitles, color: Colors.white),
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

  Widget _buildPlaylistPanel(ColorScheme cs) {
    return Container(
      width: 360,
      color: cs.surface,
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
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
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 150, child: _buildTreePane(cs)),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                Expanded(child: _buildListPane(cs)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreePane(ColorScheme cs) {
    if (widget.playlist.tree.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _treeTile(widget.playlist.tree.first, cs, isRoot: true),
      ],
    );
  }

  Widget _treeTile(VideoFolderNode node, ColorScheme cs, {bool isRoot = false}) {
    final hasChildren = node.children.isNotEmpty || node.videos.isNotEmpty;
    final isSelected = _selectedFolder == node;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _selectedFolder = node),
          child: Container(
            color: isSelected ? cs.primary.withValues(alpha: 0.18) : null,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.folder_open : Icons.folder,
                  size: 16,
                  color: isSelected ? cs.primary : Colors.amber.shade400,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isRoot ? Strings.t('allVideos') : node.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? cs.primary : cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasChildren)
          ...node.children.map((c) => _treeTile(c, cs)),
      ],
    );
  }

  List<VideoEntry> _visibleVideos() {
    if (_selectedFolder == null) return widget.playlist.entries;
    final out = <VideoEntry>[];
    void collect(VideoFolderNode n) {
      out.addAll(n.videos);
      for (final c in n.children) collect(c);
    }

    collect(_selectedFolder!);
    return out;
  }

  Widget _buildListPane(ColorScheme cs) {
    final videos = _visibleVideos();
    if (videos.isEmpty) {
      return Center(
        child: Text(
          Strings.t('playListEmpty'),
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
      );
    }
    final headerStyle = TextStyle(
      fontSize: 11,
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(flex: 4, child: Text('Name', style: headerStyle)),
              Expanded(flex: 2, child: Text(Strings.t('videoCodec'), style: headerStyle)),
              Expanded(flex: 2, child: Text(Strings.t('videoResolution'), style: headerStyle)),
              Expanded(flex: 1, child: Text(Strings.t('videoFps'), style: headerStyle)),
              Expanded(flex: 2, child: Text(Strings.t('videoDuration'), style: headerStyle)),
              Expanded(flex: 2, child: Text(Strings.t('videoSize'), style: headerStyle)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: videos.length,
            itemBuilder: (context, index) {
              final e = videos[index];
              final globalIndex = widget.playlist.entries.indexOf(e);
              final isCurrent = globalIndex == _currentIndex;
              return InkWell(
                onTap: () => _playIndex(globalIndex),
                child: Container(
                  color: isCurrent ? cs.primary.withValues(alpha: 0.18) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Row(
                          children: [
                            if (isCurrent)
                              Icon(Icons.play_arrow, size: 14, color: cs.primary)
                            else
                              const SizedBox(width: 14),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                e.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isCurrent ? cs.primary : cs.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(flex: 2, child: _metaText(e.meta?.codecText ?? Strings.t('loadingMeta'), cs)),
                      Expanded(flex: 2, child: _metaText(e.meta?.resolutionText ?? '--', cs)),
                      Expanded(flex: 1, child: _metaText(e.meta?.fpsText ?? '--', cs)),
                      Expanded(flex: 2, child: _metaText(e.meta?.durationText ?? '--', cs)),
                      Expanded(flex: 2, child: _metaText(e.sizeText, cs)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _metaText(String text, ColorScheme cs) {
    return Text(
      text,
      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      overflow: TextOverflow.ellipsis,
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
    );
    widget.playlist.entries.add(entry);
    if (widget.playlist.tree.isNotEmpty) {
      widget.playlist.tree.first.videos.add(entry);
    }
    _selectedFolder = widget.playlist.tree.isNotEmpty
        ? widget.playlist.tree.first
        : _selectedFolder;
    setState(() {});
    _playIndex(widget.playlist.entries.length - 1);
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
    _selectedFolder = newPlaylist.tree.isNotEmpty ? newPlaylist.tree.first : null;
    _currentIndex = 0;
    _openCurrent();
    setState(() {});
    _startMetadataProbe();
  }
}
