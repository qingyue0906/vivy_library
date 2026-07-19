import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import '../models/audio_track.dart';
import '../services/audio_playlist_service.dart';
import '../services/audio_metadata_service.dart';
import '../services/audio_tag_service.dart';
import '../services/translations.dart';
import '../services/settings_service.dart';
import '../services/fvp_player.dart';
import '../services/playlist_sort.dart';
import '../providers/library_state.dart';
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
  // 播放列表排序偏好（持久化，音频/视频各自独立）。
  SortField _sortField = SettingsService.loadAudioSortFieldSync();
  SortOrder _sortOrder = SettingsService.loadAudioSortOrderSync();
  Timer? _hideTimer;

  double _volume = 100;
  bool _muted = false;
  double _rate = 1.0;
  _RepeatMode _repeat = _RepeatMode.all;

  final Set<String> _expanded = {};
  final Random _random = Random();

  /// 路径 → 全局播放序号。供播放列表叶子 O(1) 定位，避免原 `entries.indexOf` 的 O(n) 查找
  /// （整棵树每次重建都会对每个叶子做一次，列表大时是 O(n²) 的重建开销）。
  final Map<String, int> _entryIndex = {};

  /// 播放列表「扁平化」缓存：仅含当前展开状态下可见的文件夹头/文件叶，供 ListView.builder
  /// 虚拟化渲染。随展开状态或列表内容变化置脏重建，平时直接复用，避免反复遍历整棵大树。
  List<_FlatItem>? _flatList;
  bool _flatDirty = true;

  /// 已展开的文件夹路径集合（用于树形播放列表的收起/展开）。
  final ScrollController _playlistScrollController = ScrollController();
  final ScrollController _lyricScrollController = ScrollController();

  /// 扫描暂停定时器：滚动/拖动窗口/缩放窗口时触发，交互停止 400ms 后恢复后台探测。
  /// 暂停期间 [AudioMetadataService] 的后台扫描循环挂起，让出平台线程避免掉帧。
  Timer? _scanPauseTimer;

  // 标签/时长渐进探测（由 AudioMetadataService 负责；_probing 仅用于头部忙碌指示）
  bool _probing = false;
  void _onBusyChanged() {
    if (mounted && _probing != AudioMetadataService.busy.value) {
      setState(() => _probing = AudioMetadataService.busy.value);
    }
  }

  /// 当前曲目元数据变化监听：回灌或后台探测完成时刷新歌词（歌词来自 meta.lyrics）。
  AudioEntry? _watchedEntry;
  void _onCurrentMetaChanged() {
    if (mounted) _onEntryChanged();
  }

  /// 已请求过标签解析的当前曲目路径集合（含「无标签」的空结果），避免对已播放曲目
  /// 反复读盘解析。当前曲目被后台扫描排除，但其封面/标题/艺人/歌词只能来自标签解析，故补一份。
  final Set<String> _tagRequestedPaths = {};

  void _watchCurrentMeta() {
    if (_watchedEntry == _currentEntry) return;
    _watchedEntry?.metaNotifier.removeListener(_onCurrentMetaChanged);
    _watchedEntry = _currentEntry;
    _watchedEntry?.metaNotifier.addListener(_onCurrentMetaChanged);
  }

  // 歌词
  List<LyricLine> _lyrics = const [];
  int _lyricIndex = -1;
  final List<GlobalKey> _lyricKeys = [];

  DateTime? _lastOpenAt;

  /// 是否已启动媒体初始化。用于把 open/元数据探测推迟到入场动画结束后，
  /// 且保证只触发一次。
  bool _mediaStarted = false;

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
    _applySort();
    _flatDirty = true;
    _initPlayer();
    AudioMetadataService.busy.addListener(_onBusyChanged);
    _probing = AudioMetadataService.busy.value;
    _initPlayback();
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
    // 订阅播放状态流：VideoPlayerController 每帧只更新 player.state，不会触发本页
    // setState；不订阅则按钮图标会滞后一拍（首次显示暂停、需点两次才刷新）。
    player.playingStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// 真正的媒体初始化（open + 元数据探测）推迟到本页入场转场动画【完全结束】后，
  /// 避免缩放动画期间执行 c.initialize() 等重原生调用阻塞主线程导致掉帧。
  Future<void> _initPlayback() async {
    if (!mounted) return;
    setState(() {});
    _startMediaAfterEnter();
  }

  /// 等待本页入场转场动画结束后再真正初始化媒体，
  /// 让缩放动画期间主线程/GPU 不被解码初始化抢占，保证动画流畅。
  void _startMediaAfterEnter() {
    if (_mediaStarted) return;
    // 首帧后再访问 ModalRoute（此时依赖已就绪），并根据入场动画状态决定时机。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mediaStarted || !mounted) return;
      final anim = ModalRoute.of(context)?.animation;
      void run() {
        if (_mediaStarted || !mounted) return;
        _mediaStarted = true;
        _openCurrent();
        _startMetaProbe();
      }

      if (anim == null || anim.status == AnimationStatus.completed) {
        run();
        return;
      }
      void listener(AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          anim.removeStatusListener(listener);
          run();
        }
      }

      anim.addStatusListener(listener);
    });
  }

  void _openCurrent() {
    if (_currentIndex < 0 || _currentIndex >= widget.playlist.entries.length) {
      return;
    }
    final entry = widget.playlist.entries[_currentIndex];
    _lastOpenAt = DateTime.now();
    _watchCurrentMeta();
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
    AudioMetadataService.setActivePath(entry.path);
    final dur = player.state.duration;
    if (dur > Duration.zero) {
      entry.setMeta((entry.meta ?? const AudioMeta())
          .copyWith(duration: dur));
      // 当前曲目时长已由播放器内核回填，登记进跨页面缓存，
      // 重开本曲目时直接命中，无需再次离屏探测。
      AudioMetadataService.putCache(entry.path, entry.meta);
      if (mounted) setState(() {});
    }
    // 当前曲目被后台扫描排除（避免重复建播放器），但其封面/标题/艺人/歌词只能来自标签解析，
    // 播放器内核不提供。若尚未加载到标签，这里异步补一份，使正在播放的曲目也能显示缩略图。
    _ensureActiveTag(entry);
  }

  /// 为当前曲目异步补解析标签（封面/标题/艺人/专辑/歌词）。后台扫描已排除当前曲目，
  /// 不在此补则会永久缺失封面。保留播放器权威时长，仅回填标签字段。
  void _ensureActiveTag(AudioEntry entry) {
    if (_tagRequestedPaths.contains(entry.path)) return; // 已解析过（含空结果）
    _tagRequestedPaths.add(entry.path);
    AudioTagService.read(entry.path).then((tag) {
      if (!mounted) return;
      final e = _currentEntry;
      if (e == null || e.path != entry.path) return; // 已切走，丢弃结果
      // 舞台大图额外按需取内嵌封面原图（不缩放，高清显示）。
      final coverFull = AudioTagService.readFullCover(entry.path);
      // 保留播放器权威时长，回填标签的封面/标题/艺人/专辑/歌词。
      final merged = (e.meta ?? const AudioMeta()).copyWith(
        title: tag.title,
        artist: tag.artist,
        album: tag.album,
        coverBytes: tag.coverBytes,
        coverFullBytes: coverFull,
        lyrics: tag.lyrics,
      );
      e.setMeta(merged);
      // 高清原图不进跨页面缓存（防止全部曲目常驻高清字节 → 内存回升）；
      // 缓存只留 128px 缩略图供列表/重开回灌，重开本曲目时直接命中。
      AudioMetadataService.putCache(entry.path, merged.copyWith(coverFullBytes: null));
      _onEntryChanged(); // 重新解析歌词（若标签含内嵌歌词）
      if (mounted) setState(() {});
    });
  }

  /// 后台渐进加载标签（标题/艺人/封面/歌词）与时长，委托给 [AudioMetadataService]。
  /// 该服务复用跨页面组合缓存：重开同一项目时命中缓存直接回灌，封面/时长即时显示，
  /// 不再全量重探；且按「单并发 + 限速 + 交互暂停」运行，不抢占平台线程掉帧。
  /// 探测与挂载解耦：每个条目完成后经 [AudioEntry.setMeta] → [AudioEntry.metaNotifier]
  /// 通知对应叶子自更新，不触发父级整树重建（虚拟化后只刷新单个可见条目）。
  void _startMetaProbe() {
    if (widget.playlist.entries.isEmpty) return;
    // 当前曲目优先探测；其余按列表顺序慢慢扫。
    AudioMetadataService.scanAll(
      widget.playlist.entries,
      currentPath: _currentEntry?.path,
    );
  }

  /// 暂停后台元数据扫描，并在停止一切交互（滚动/拖动窗口/缩放窗口）400ms 后自动恢复。
  /// 交互期间零探测，平台线程只服务 UI 与正在播放的音频，避免窗口拖动/缩放/滚动掉帧。
  void _pauseScanThenResumeLater() {
    if (!mounted) return;
    AudioMetadataService.setPaused(true);
    _scanPauseTimer?.cancel();
    _scanPauseTimer = Timer(const Duration(milliseconds: 400), () {
      AudioMetadataService.setPaused(false);
    });
  }

  /// 播放列表滚动回调：开始/更新滚动时暂停后台元数据扫描，停止滚动 400ms 后恢复。
  void _onPlaylistScroll(ScrollNotification n) {
    if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
      _pauseScanThenResumeLater();
    }
  }

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
    // 展开集可能新增了文件夹（如定位到当前曲目所在目录链），可见项集合随之变化，
    // 必须置脏扁平列表缓存，否则 ListView 沿用旧可见项不刷新。
    _flatDirty = true;
  }

  @override
  void onWindowMove() {
    // 拖动窗口时暂停后台探测，GPU/平台线程让给窗口合成，避免一卡一卡。
    _pauseScanThenResumeLater();
    super.onWindowMove();
  }

  @override
  void onWindowResize() {
    // 缩放窗口时暂停后台探测，GPU/平台线程让给窗口合成，避免一卡一卡。
    _pauseScanThenResumeLater();
    super.onWindowResize();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _scanPauseTimer?.cancel();
    windowManager.removeListener(this);
    AudioMetadataService.busy.removeListener(_onBusyChanged);
    _watchedEntry?.metaNotifier.removeListener(_onCurrentMetaChanged);
    _watchedEntry = null;
    // 停止后台扫描循环并清场，但保留跨页面组合缓存（下次打开直接命中）。
    AudioMetadataService.dispose();
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
    final cover = current?.meta?.coverFullBytes ?? current?.meta?.coverBytes;
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
                const SizedBox(width: 8),
                _buildSortControls(cs),
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
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      _onPlaylistScroll(n);
                      return false;
                    },
                    child: Scrollbar(
                      controller: _playlistScrollController,
                      thumbVisibility: true,
                      child: SmoothScroll(
                        controller: _playlistScrollController,
                        builder: (context, controller, physics) =>
                            ListView.builder(
                          controller: controller,
                          physics: physics,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _visibleItems().length,
                          itemBuilder: (context, index) {
                            final item = _visibleItems()[index];
                            if (item.isFolder) {
                              return _buildFolderItem(
                                item.folder!,
                                cs,
                                item.depth,
                                item.hasKids,
                                item.expanded,
                              );
                            }
                            final f = item.file!;
                            final gi = _entryIndex[f.path] ?? -1;
                            final isCurrent = gi == _currentIndex && f.isAudio;
                            return _FileLeaf(
                              key: ValueKey(f.path),
                              entry: f,
                              cs: cs,
                              depth: item.depth,
                              isCurrent: isCurrent,
                              onTap: f.isAudio ? () => _playIndex(gi) : null,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 按当前排序偏好对「播放顺序 entries」与「文件夹树 tree」统一重排。
  /// 文件夹节点始终按名称排序（无 size/date），仅文件按所选字段/升降序排。
  /// 重排后定位回当前播放项，避免播放被打断。
  /// 重建 路径→全局播放序号 索引，供播放列表叶子 O(1) 定位当前项，
  /// 替代原先每个叶子用 `entries.indexOf` 的 O(n) 查找（整树重建时是 O(n²)）。
  void _rebuildIndex() {
    _entryIndex.clear();
    for (var i = 0; i < widget.playlist.entries.length; i++) {
      _entryIndex[widget.playlist.entries[i].path] = i;
    }
  }

  void _applySort() {
    final playingPath = (_currentIndex >= 0 &&
            _currentIndex < widget.playlist.entries.length)
        ? widget.playlist.entries[_currentIndex].path
        : null;
    widget.playlist.entries.sort((a, b) => comparePlaylistEntries(
          nameA: a.name,
          sizeA: a.sizeInBytes,
          dateA: a.modifiedTime,
          nameB: b.name,
          sizeB: b.sizeInBytes,
          dateB: b.modifiedTime,
          field: _sortField,
          order: _sortOrder,
        ));
    for (final root in widget.playlist.tree) {
      _sortTree(root);
    }
    _rebuildIndex();
    if (playingPath != null) {
      _currentIndex = _entryIndex[playingPath] ?? _currentIndex;
    }
    // 扁平化列表缓存依赖顺序，重排后必须置脏，否则 ListView 沿用旧顺序不刷新。
    _flatDirty = true;
  }

  void _sortTree(AudioFolderNode node) {
    node.files.sort((a, b) => comparePlaylistEntries(
          nameA: a.name,
          sizeA: a.sizeInBytes,
          dateA: a.modifiedTime,
          nameB: b.name,
          sizeB: b.sizeInBytes,
          dateB: b.modifiedTime,
          field: _sortField,
          order: _sortOrder,
        ));
    node.children.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final c in node.children) {
      _sortTree(c);
    }
  }

  /// 播放列表头部排序控件：字段下拉（名称/大小/日期）+ 升降序箭头按钮。
  Widget _buildSortControls(ColorScheme cs) {
    final itemStyle = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButton<SortField>(
          value: _sortField,
          underline: const SizedBox.shrink(),
          isDense: true,
          iconSize: 16,
          style: itemStyle,
          items: [
            DropdownMenuItem(
              value: SortField.name,
              child: Text(Strings.t('sortName')),
            ),
            DropdownMenuItem(
              value: SortField.size,
              child: Text(Strings.t('sortSize')),
            ),
            DropdownMenuItem(
              value: SortField.date,
              child: Text(Strings.t('sortDate')),
            ),
          ],
          onChanged: (f) {
            if (f == null || f == _sortField) return;
            setState(() {
              _sortField = f;
              _applySort();
            });
            SettingsService.saveAudioSort(_sortField, _sortOrder);
          },
        ),
        IconButton(
          icon: Icon(
            _sortOrder == SortOrder.ascending
                ? Icons.arrow_upward
                : Icons.arrow_downward,
          ),
          iconSize: 16,
          splashRadius: 14,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          color: cs.onSurfaceVariant,
          tooltip: _sortOrder == SortOrder.ascending
              ? Strings.t('sortAsc')
              : Strings.t('sortDesc'),
          onPressed: () {
            setState(() {
              _sortOrder = _sortOrder == SortOrder.ascending
                  ? SortOrder.descending
                  : SortOrder.ascending;
              _applySort();
            });
            SettingsService.saveAudioSort(_sortField, _sortOrder);
          },
        ),
      ],
    );
  }

  /// 渲染展开的文件夹树中的单个「文件夹头」（含展开/收起）。
  /// 折叠/展开时只需置脏扁平列表（_flatDirty）并重建可见项，不会重建整棵大树。
  Widget _buildFolderItem(
    AudioFolderNode node,
    ColorScheme cs,
    int depth,
    bool hasKids,
    bool expanded,
  ) {
    return InkWell(
      key: ValueKey('folder:${node.path}'),
      onTap: hasKids
          ? () => setState(() {
                if (expanded) {
                  _expanded.remove(node.path);
                } else {
                  _expanded.add(node.path);
                }
                _flatDirty = true;
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
    );
  }

  /// 把「当前展开状态」下的文件夹树扁平化成一条有序列表，供 ListView.builder 虚拟化渲染。
  /// 只放入可见的文件夹头与文件叶；折叠的文件夹及其子项不进入列表。
  List<_FlatItem> _buildFlatList() {
    final list = <_FlatItem>[];
    void walk(AudioFolderNode node, int depth) {
      final hasKids = node.children.isNotEmpty || node.files.isNotEmpty;
      final expanded = _expanded.contains(node.path);
      list.add(_FlatItem.folder(node, depth, expanded, hasKids));
      if (hasKids && expanded) {
        for (final c in node.children) {
          walk(c, depth + 1);
        }
        for (final f in node.files) {
          list.add(_FlatItem.file(f, depth + 1));
        }
      }
    }

    for (final r in widget.playlist.tree) {
      walk(r, 0);
    }
    return list;
  }

  /// 返回当前可见项列表（带扁平化缓存，仅在展开状态/列表变化后置脏时重建）。
  List<_FlatItem> _visibleItems() {
    if (_flatDirty || _flatList == null) {
      _flatList = _buildFlatList();
      _flatDirty = false;
    }
    return _flatList!;
  }

  Future<void> _openLocalFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path == null) return;
    int size = 0;
    DateTime modified = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      size = File(path).lengthSync();
    } catch (_) {}
    try {
      modified = File(path).lastModifiedSync();
    } catch (_) {}
    final name = path.split(RegExp(r'[/\\]')).last;
    final entry = AudioEntry(
      path: path,
      name: name,
      dirPath: File(path).parent.path,
      sizeInBytes: size,
      modifiedTime: modified,
      isAudio: true,
    );
    widget.playlist.entries.add(entry);
    if (widget.playlist.tree.isNotEmpty) {
      widget.playlist.tree.first.files.add(entry);
    }
    _applySort();
    _flatDirty = true;
    setState(() {});
    _playIndex(_entryIndex[path] ?? widget.playlist.entries.length - 1);
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
    _applySort();
    _flatDirty = true;
    _currentIndex = 0;
    _openCurrent();
    setState(() {});
    _startMetaProbe();
  }
}

/// 播放列表「扁平化」后的可见项：文件夹头或文件叶，供 ListView.builder 使用。
class _FlatItem {
  final bool isFolder;
  final AudioFolderNode? folder;
  final AudioEntry? file;
  final int depth;
  final bool expanded;
  final bool hasKids;

  _FlatItem.folder(this.folder, this.depth, this.expanded, this.hasKids)
      : isFolder = true,
        file = null;

  _FlatItem.file(this.file, this.depth)
      : isFolder = false,
        folder = null,
        expanded = false,
        hasKids = false;
}

/// 播放列表中的单个文件叶（音频可点击播放；非音频灰显）。
/// 自带状态：挂载时订阅条目 [AudioEntry.metaNotifier]，元数据由页面级后台扫描
/// 慢慢探测完成后通过 [AudioEntry.setMeta] 通知本叶自更新，**不会触发父级整树重建**。
/// 探测与挂载彻底解耦：滚动时不会产生新探测请求，滚动纯 UI、不卡。
class _FileLeaf extends StatefulWidget {
  final AudioEntry entry;
  final ColorScheme cs;
  final int depth;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _FileLeaf({
    required Key key,
    required this.entry,
    required this.cs,
    required this.depth,
    required this.isCurrent,
    this.onTap,
  }) : super(key: key);

  @override
  State<_FileLeaf> createState() => _FileLeafState();
}

class _FileLeafState extends State<_FileLeaf> {
  @override
  void initState() {
    super.initState();
    widget.entry.metaNotifier.addListener(_onMeta);
  }

  void _onMeta() {
    if (!mounted) return;
    // 若在 build 阶段被通知（如父级重建时某个探测结果返回并触发 metaNotifier），
    // 延后一帧再 setState，避免 “setState() or markNeedsBuild() called during build”。
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.entry.metaNotifier.removeListener(_onMeta);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.entry;
    final cs = widget.cs;
    final isCurrent = widget.isCurrent;
    final playable = f.isAudio;
    final cover = f.meta?.coverBytes;
    return InkWell(
      onTap: widget.onTap,
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
          left: 8.0 + widget.depth * 14 + 14,
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
                  cacheWidth: 64,
                  cacheHeight: 64,
                  errorBuilder: (_, _, _) => _audioFileIcon(cs, playable, isCurrent),
                ),
              )
            else
              _audioFileIcon(cs, playable, isCurrent, size: 32),
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
                    '${f.meta?.durationText ?? '--:--'} · ${f.sizeText} · ${f.dateText}',
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
}

/// 文件叶的占位图标：音频文件用 [Icons.audio_file]，非音频灰显。
Widget _audioFileIcon(ColorScheme cs, bool playable, bool isCurrent, {double size = 32}) {
  return Icon(
    playable ? Icons.audio_file : Icons.insert_drive_file,
    size: size * 0.7,
    color: playable
        ? (isCurrent ? cs.primary : cs.onSurfaceVariant)
        : cs.onSurfaceVariant.withValues(alpha: 0.6),
  );
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
