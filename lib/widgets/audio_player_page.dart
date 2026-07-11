import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import '../models/audio_track.dart';
import '../services/audio_playlist_service.dart';
import '../services/audio_tag_service.dart';
import '../services/translations.dart';
import '../services/settings_service.dart';
import '../services/fvp_player.dart';
import 'smooth_scroll.dart';

enum _RepeatMode { off, all, one, shuffle }

class AudioPlayerPage extends StatefulWidget {
  final AudioPlaylist playlist;
  final int initialIndex;
  final String title;
  final double? initialPlaylistWidth;

  const AudioPlayerPage({
    super.key,
    required this.playlist,
    this.initialIndex = 0,
    required this.title,
    this.initialPlaylistWidth,
  });

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage>
    with WindowListener {
  late final FvpPlayer player;

  late int _currentIndex;
  bool _isFullscreen = false;
  bool _isMaximized = false;
  bool _showTop = false;
  bool _showBottom = false;
  bool _showPlaylist = SettingsService.loadAudioShowPlaylistSync();
  bool _showLyrics = SettingsService.loadAudioShowLyricsSync();
  double _playlistWidth = SettingsService.loadAudioPlaylistWidthSync();
  Timer? _hideTimer;

  double _volume = 100;
  bool _muted = false;
  double _rate = 1.0;
  _RepeatMode _repeat = _RepeatMode.all;

  final Set<String> _expanded = {};
  final Random _random = Random();

  /// 已展开的文件夹路径集合（用于树形播放列表的收起/展开）。
  final ScrollController _playlistScrollController = ScrollController();
  final ScrollController _lyricScrollController = ScrollController();

  // 标签/时长渐进探测
  bool _probing = false;
  int _probeGen = 0;

  // 歌词
  List<LyricLine> _lyrics = const [];
  int _lyricIndex = -1;
  final List<GlobalKey> _lyricKeys = [];

  DateTime? _lastOpenAt;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    player = FvpPlayer();
    _currentIndex = widget.initialIndex.clamp(
      0,
      max(0, widget.playlist.entries.length - 1),
    );
    for (final r in widget.playlist.tree) {
      _expanded.add(r.path);
    }
    if (widget.playlist.entries.isNotEmpty) {
      _ensureExpanded(widget.playlist.entries[_currentIndex]);
    }
    _initPlayer();
    _initPlayback();
    _startMetaProbe();
    if (widget.initialPlaylistWidth != null) {
      _playlistWidth = widget.initialPlaylistWidth!;
    } else {
      SettingsService.loadAudioPlaylistWidth()
          .then((v) => setState(() => _playlistWidth = v));
    }
    windowManager.isMaximized().then((v) => setState(() => _isMaximized = v));
    () async {
      _volume = await SettingsService.loadAudioVolume();
      _muted = await SettingsService.loadAudioMuted();
      _rate = await SettingsService.loadAudioSpeed();
      _repeat = _RepeatMode
          .values[(await SettingsService.loadAudioRepeatMode()).clamp(0, 3)];
      player.setVolume(_muted ? 0 : _volume);
      player.setRate(_rate);
      if (mounted) setState(() {});
    }();
  }

  void _initPlayer() {
    player.completedStream.listen((_) => _onCompleted());
    player.positionStream.listen((pos) => _updateLyric(pos));
    player.durationStream.listen((_) => _refreshCurrentMetaFromState());
  }

  Future<void> _initPlayback() async {
    if (!mounted) return;
    setState(() {});
    _openCurrent();
  }

  void _openCurrent() {
    if (_currentIndex < 0 || _currentIndex >= widget.playlist.entries.length) {
      return;
    }
    final entry = widget.playlist.entries[_currentIndex];
    _lastOpenAt = DateTime.now();
    _openEntry(entry);
    _onEntryChanged();
  }

  /// 打开指定曲目；若格式不受支持导致打开失败，播放器内部已停止并释放上一首，
  /// 这里仅弹出提示，避免 PlatformException 作为未捕获异常刷屏。
  Future<void> _openEntry(AudioEntry entry) async {
    try {
      await player.open(entry.path, play: true);
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Strings.t('audioOpenFailed')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 当前曲目切换/打开后：重新解析歌词、刷新元信息。
  void _onEntryChanged() {
    final entry = _currentEntry;
    _lyrics = entry?.meta?.lyrics != null
        ? LyricParser.parse(entry!.meta!.lyrics)
        : const [];
    _lyricIndex = -1;
    _lyricKeys
      ..clear()
      ..addAll(List.generate(_lyrics.length, (_) => GlobalKey()));
    if (mounted) setState(() {});
  }

  AudioEntry? get _currentEntry =>
      (_currentIndex >= 0 && _currentIndex < widget.playlist.entries.length)
          ? widget.playlist.entries[_currentIndex]
          : null;

  void _refreshCurrentMetaFromState() {
    final entry = _currentEntry;
    if (entry == null) return;
    final dur = player.state.duration;
    if (dur > Duration.zero) {
      entry.meta = (entry.meta ?? const AudioMeta())
          .copyWith(duration: dur);
      if (mounted) setState(() {});
    }
  }

  /// 后台渐进加载标签（标题/艺人/封面/歌词）与时长。
  /// 标签来自纯 Dart 的 [AudioTagService]；时长来自 fvp 的 getMediaInfo() 离屏探测。
  void _startMetaProbe() {
    if (widget.playlist.entries.isEmpty) return;
    _probing = true;
    if (mounted) setState(() {});
    final gen = ++_probeGen;
    () async {
      final ordered = [...widget.playlist.entries]
        ..sort((a, b) => _isCurrent(a) == _isCurrent(b)
            ? 0
            : _isCurrent(a)
                ? -1
                : 1);
      for (final e in ordered) {
        if (!mounted || gen != _probeGen) return;
        final tag = await AudioTagService.read(e.path);
        Duration? dur;
        try {
          dur = (await FvpPlayer.probeVideoMeta(e.path))?.duration;
        } catch (_) {}
        if (!mounted || gen != _probeGen) return;
        e.meta = (e.meta ?? const AudioMeta()).copyWith(
          title: tag.title ?? e.meta?.title,
          artist: tag.artist ?? e.meta?.artist,
          album: tag.album ?? e.meta?.album,
          coverBytes: tag.coverBytes ?? e.meta?.coverBytes,
          lyrics: tag.lyrics ?? e.meta?.lyrics,
          duration: dur ?? tag.duration ?? e.meta?.duration,
        );
        // 当前曲目：歌词可能刚刚加载，重新解析。
        if (_isCurrent(e)) _onEntryChanged();
        setState(() {});
      }
      _probing = false;
      if (mounted) setState(() {});
    }();
  }

  bool _isCurrent(AudioEntry e) =>
      _currentIndex >= 0 &&
      _currentIndex < widget.playlist.entries.length &&
      widget.playlist.entries[_currentIndex] == e;

  void _onCompleted() {
    final justOpened = _lastOpenAt != null &&
        DateTime.now().difference(_lastOpenAt!) <
            const Duration(milliseconds: 1500);
    if (justOpened || player.state.position < const Duration(seconds: 1)) {
      return;
    }
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
    SettingsService.saveAudioVolume(_volume);
    SettingsService.saveAudioMuted(_muted);
    setState(() {});
  }

  void _toggleMute() {
    _muted = !_muted;
    player.setVolume(_muted ? 0 : _volume);
    SettingsService.saveAudioMuted(_muted);
    setState(() {});
  }

  void _setRate(double r) {
    _rate = r;
    player.setRate(r);
    SettingsService.saveAudioSpeed(r);
    setState(() {});
  }

  void _cycleRepeat() {
    _repeat = _RepeatMode.values[(_repeat.index + 1) % _RepeatMode.values.length];
    SettingsService.saveAudioRepeatMode(_repeat.index);
    setState(() {});
  }

  void _toggleLyrics() {
    _showLyrics = !_showLyrics;
    SettingsService.saveAudioShowLyrics(_showLyrics);
    setState(() {});
  }

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

  void _ensureExpanded(AudioEntry v) {
    final dir = v.dirPath;
    void walk(AudioFolderNode n) {
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
    _lyricScrollController.dispose();
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
        backgroundColor: cs.surface,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerArea(ColorScheme cs) {
    if (_isFullscreen) {
      return Stack(
        children: [
          _buildStage(cs),
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
        Expanded(child: _buildStage(cs)),
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

  /// 中央舞台：大封面 + 标题/艺人–专辑 + 同步歌词面板（含 midi 无声提示）。
  Widget _buildStage(ColorScheme cs) {
    final current = _currentEntry;
    final cover = current?.meta?.coverBytes;
    final title =
        current?.displayTitle ?? Strings.t('unknownTitle');
    final artist = current?.displayArtist ?? '';
    final album = current?.meta?.album ?? '';
    final isMidi = current != null &&
        const {'mid', 'midi'}.contains(
            current.path.toLowerCase().split('.').last);

    return GestureDetector(
      onSecondaryTap: _close,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withValues(alpha: 0.18),
              cs.surface,
            ],
          ),
        ),
        child: Row(
        children: [
          // 封面 + 元信息块
          Container(
            width: 340,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    _togglePlay();
                    _revealOnTap();
                  },
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: cover != null
                        ? Image.memory(cover, fit: BoxFit.cover)
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  cs.primary.withValues(alpha: 0.45),
                                  cs.surfaceContainerHighest,
                                ],
                              ),
                            ),
                            child: Icon(
                              Icons.album,
                              size: 96,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (artist.isNotEmpty) artist,
                    if (album.isNotEmpty) album,
                  ].join('  ·  '),
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (isMidi)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      Strings.t('midiNoSound'),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
          // 歌词面板
          if (_showLyrics)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _buildLyrics(cs),
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildLyrics(ColorScheme cs) {
    if (_lyrics.isEmpty) {
      return Center(
        child: Text(
          Strings.t('noLyrics'),
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      );
    }
    return SmoothScroll(
      controller: _lyricScrollController,
      builder: (context, controller, physics) => ListView.builder(
        controller: controller,
        physics: physics,
        padding: const EdgeInsets.symmetric(vertical: 40),
        itemCount: _lyrics.length,
        itemBuilder: (ctx, i) {
          final line = _lyrics[i];
          final active = i == _lyricIndex;
          return Container(
            key: _lyricKeys[i],
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              line.text.isEmpty ? '♪' : line.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: active ? 17 : 14,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: active ? 1.0 : 0.5),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 根据播放位置高亮当前歌词行并滚动至可见区域。
  void _updateLyric(Duration pos) {
    if (_lyrics.isEmpty) return;
    var idx = -1;
    for (var i = 0; i < _lyrics.length; i++) {
      final t = _lyrics[i].time;
      if (t != null && t <= pos) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx == _lyricIndex) return;
    _lyricIndex = idx;
    if (idx >= 0 && idx < _lyricKeys.length) {
      final ctx = _lyricKeys[idx].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.4,
          duration: const Duration(milliseconds: 250),
        );
      }
    } else if (idx < 0 && _lyricScrollController.hasClients) {
      _lyricScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    if (mounted) setState(() {});
  }

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
                    Icon(Icons.audio_file, size: 16, color: cs.primary),
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

  Widget _buildTopOverlay(ColorScheme cs) {
    final current = _currentEntry;
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
              '${widget.title}  ·  ${current?.displayTitle ?? ''}',
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

  Widget _buildControlBar(ColorScheme cs, {bool overlay = false}) {
    final current = _currentEntry;
    final playing = player.state.playing;
    final Color iconColor = overlay ? Colors.white : cs.onSurface;
    return Container(
      decoration: BoxDecoration(
        color: overlay ? Colors.black.withValues(alpha: 0.82) : cs.surface,
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
                    current?.displayTitle ?? '',
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
                IconButton(
                  icon: Icon(_showLyrics ? Icons.lyrics : Icons.lyrics_outlined),
                  color: _showLyrics ? cs.primary : iconColor,
                  tooltip: Strings.t('showLyrics'),
                  onPressed: _toggleLyrics,
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
                  icon: Icon(_showPlaylist
                      ? Icons.playlist_add_check
                      : Icons.playlist_play),
                  color: iconColor,
                  tooltip: Strings.t('playlist'),
                  onPressed: () {
                    setState(() => _showPlaylist = !_showPlaylist);
                    SettingsService.saveAudioShowPlaylist(_showPlaylist);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
                SettingsService.saveAudioVolume(_volume);
                SettingsService.saveAudioMuted(_muted);
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
      onSelected: _setRate,
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

  Widget _buildResizeHandle() {
    return _ResizeHandle(
      onDrag: (dx) {
        final next = (_playlistWidth - dx).clamp(220.0, 640.0);
        if (next != _playlistWidth) {
          setState(() => _playlistWidth = next);
        }
      },
      onDragEnd: () => SettingsService.saveAudioPlaylistWidth(_playlistWidth),
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

  Widget _treeNode(AudioFolderNode node, ColorScheme cs, int depth) {
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
                  color:
                      expanded ? cs.primary : Colors.amber.shade400,
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

  Widget _fileLeaf(AudioEntry f, ColorScheme cs, int depth) {
    final globalIndex = widget.playlist.entries.indexOf(f);
    final isCurrent = globalIndex == _currentIndex && f.isAudio;
    final playable = f.isAudio;
    final cover = f.meta?.coverBytes;
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
            if (cover != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(
                  cover,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _fileIcon(cs, playable, isCurrent),
                ),
              )
            else
              _fileIcon(cs, playable, isCurrent, size: 32),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.displayTitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: playable
                          ? (isCurrent ? cs.primary : cs.onSurface)
                          : cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  if (f.displayArtist.isNotEmpty)
                    Text(
                      f.displayArtist,
                      style: TextStyle(
                          fontSize: 10, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 1),
                  Text(
                    '${f.meta?.durationText ?? '--:--'} · ${f.sizeText}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
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

  Widget _fileIcon(ColorScheme cs, bool playable, bool isCurrent, {double size = 32}) {
    return Icon(
      playable ? Icons.audio_file : Icons.insert_drive_file,
      size: size * 0.7,
      color: playable
          ? (isCurrent ? cs.primary : cs.onSurfaceVariant)
          : cs.onSurfaceVariant.withValues(alpha: 0.6),
    );
  }

  Future<void> _openLocalFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path == null) return;
    int size = 0;
    try {
      size = File(path).lengthSync();
    } catch (_) {}
    final name = path.split(RegExp(r'[/\\]')).last;
    final entry = AudioEntry(
      path: path,
      name: name,
      dirPath: File(path).parent.path,
      sizeInBytes: size,
      isAudio: true,
    );
    widget.playlist.entries.add(entry);
    if (widget.playlist.tree.isNotEmpty) {
      widget.playlist.tree.first.files.add(entry);
    }
    setState(() {});
    _playIndex(widget.playlist.entries.length - 1);
    _startMetaProbe();
  }

  Future<void> _openLocalFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final newPlaylist = await AudioPlaylistService.buildFromPath(dir);
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
    _startMetaProbe();
  }
}

/// 播放区与播放列表之间的可拖拽分隔条。
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
class _ProgressSlider extends StatefulWidget {
  final FvpPlayer player;
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
    _posSub = widget.player.positionStream.listen((p) {
      if (!_dragging && mounted) setState(() => _position = p);
    });
    _durSub = widget.player.durationStream.listen((d) {
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
          AudioMeta.formatDuration(position),
          style: TextStyle(
            color: widget.cs.onSurface.withValues(alpha: 0.8),
            fontSize: 11,
          ),
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
          AudioMeta.formatDuration(duration),
          style: TextStyle(
            color: widget.cs.onSurface.withValues(alpha: 0.8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
