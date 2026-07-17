import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import '../models/video_entry.dart';
import '../services/video_playlist_service.dart';
import '../services/translations.dart';
import '../services/settings_service.dart';
import '../services/fvp_player.dart';
import '../services/video_metadata_service.dart';
import 'player_settings_page.dart';
import 'smooth_scroll.dart';

enum _RepeatMode { off, all, one, shuffle }

/// 音轨菜单的选项：自动(Auto) / 指定音轨 / 关闭音频。
enum _AudioChoiceKind { auto, track, off }

class _AudioChoice {
  final _AudioChoiceKind kind;
  final int? index;

  const _AudioChoice.auto()
      : kind = _AudioChoiceKind.auto,
        index = null;
  const _AudioChoice.track(this.index) : kind = _AudioChoiceKind.track;
  const _AudioChoice.off()
      : kind = _AudioChoiceKind.off,
        index = null;
}

class VideoPlayerPage extends StatefulWidget {
  final VideoPlaylist playlist;
  final int initialIndex;
  final String title;
  final double? initialPlaylistWidth;

  const VideoPlayerPage({
    super.key,
    required this.playlist,
    this.initialIndex = 0,
    required this.title,
    this.initialPlaylistWidth,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with WindowListener {
  late final FvpPlayer player;

  late int _currentIndex;
  bool _isFullscreen = false;
  bool _isMaximized = false;
  bool _showTop = false;
  bool _showBottom = false;
  bool _showPlaylist = SettingsService.loadPlayerShowPlaylistSync();
  bool _showSettings = false;
  bool _showMilliseconds = SettingsService.loadPlayerShowMillisecondsSync();
  bool _switchingDecode = false;
  double _playlistWidth = SettingsService.loadPlayerPlaylistWidthSync();
  Timer? _hideTimer;

  /// 滚动空闲定时器：滚动时暂停后台元数据扫描，停止滚动 400ms 后恢复，
  /// 避免探测抢占平台线程导致滚动/播放掉帧。
  Timer? _scrollIdleTimer;

  double _volume = 100;
  bool _muted = false;
  double _rate = 1.0;
  _RepeatMode _repeat = _RepeatMode.all;

  /// 已展开的文件夹路径集合（用于树形播放列表的收起/展开）。
  final Set<String> _expanded = {};
  final Random _random = Random();

  /// 路径 → 全局播放序号。供播放列表叶子 O(1) 定位，避免原 `entries.indexOf` 的 O(n) 查找
  /// （整棵树每次重建都会对每个叶子做一次，列表大时是 O(n²) 的重建开销）。
  final Map<String, int> _entryIndex = {};

  /// 播放列表「扁平化」缓存：仅含当前展开状态下可见的文件夹头/文件叶，供 ListView.builder
  /// 虚拟化渲染。随展开状态或列表内容变化置脏重建，平时直接复用，避免反复遍历整棵大树。
  List<_FlatItem>? _flatList;
  bool _flatDirty = true;

  /// 最近一次真正打开视频的时间戳。用于过滤播放器在打开瞬间误发的
  /// [completed] 事件：若 completed 在打开后极短时间内触发且播放位置仍接近 0，
  /// 视为误触发而非真正播完，避免据此自动跳到下一集（到末尾时还会回绕到第一个）。
  DateTime? _lastOpenAt;

  /// 是否使用硬件解码。默认开启；切换时重新载入当前视频以生效。
  bool _useHardwareDecode = true;

  /// 同名外置音频文件作为音轨。默认开启；切换时重新载入当前视频以生效。
  bool _useExternalAudio = SettingsService.loadPlayerUseExternalAudioSync();

  /// 是否已启动媒体初始化。用于把 open/元数据探测推迟到入场动画结束后，
  /// 且保证只触发一次。
  bool _mediaStarted = false;

  /// 播放列表滚动控制器（配合 SmoothScroll 与 Scrollbar 实现平滑滚动）。
  final ScrollController _playlistScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    player = FvpPlayer();
    if (widget.playlist.entries.isNotEmpty) {
      // 预热一次，使 fvp 后端就绪。
      // 注意：不要在此处把 maxWidth/maxHeight 设成当前窗口物理尺寸。
      // initState 时窗口仍是 main.dart 的默认 1280x720，会把 fvp 的
      // 纹理上限钉死在 1280x720；之后即便全屏/最大化，纹理也不会再变大，
      // 导致「视频最大只显示到 1280x720」。不传 options 时 fvp 用视频
      // 真实分辨率建纹理，画面可随窗口放大铺满。
      fvp.registerWith();
    }
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
    _rebuildIndex();
    _flatDirty = true;
    _initPlayer();
    _initPlayback();
    if (widget.initialPlaylistWidth != null) {
      _playlistWidth = widget.initialPlaylistWidth!;
    } else {
      SettingsService.loadPlayerPlaylistWidth()
          .then((v) => setState(() => _playlistWidth = v));
    }
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

  void _initPlayer() {
    player.completedStream.listen((_) => _onCompleted());
    player.tracksStream.listen((_) => _updateCurrentMetaFromPlayer());
    player.durationStream.listen((_) => _updateCurrentMetaFromPlayer());
    player.playingStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// 先读取硬件解码偏好并写入 fvp 的解码设置，再打开当前视频，
  /// 保证解码方式从首次播放起即生效（解码器改变需重新载入文件）。
  /// 真正的媒体初始化（open + 元数据探测）推迟到本页入场转场动画【完全结束】后，
  /// 避免缩放动画期间执行 c.initialize() 等重原生调用阻塞主线程导致掉帧。
  Future<void> _initPlayback() async {
    _useHardwareDecode = await SettingsService.loadPlayerHardwareDecode();
    player.setHardwareDecode(_useHardwareDecode);
    _useExternalAudio = await SettingsService.loadPlayerUseExternalAudio();
    if (!mounted) return;
    setState(() {});
    _startMediaAfterEnter();
  }

  /// 等待本页入场转场动画结束后再真正初始化媒体，
  /// 让缩放动画期间主线程/GPU 不被视频解码初始化抢占，保证动画流畅。
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
        // 启动静默慢扫：后台单并发、限速、可见优先地探测列表全部视频；
        // 滚动时由 ScrollNotification 暂停，避免抢占平台线程导致卡顿。
        VideoMetadataService.scanAll(widget.playlist.entries);
      }

      if (anim == null || anim.status == AnimationStatus.completed) {
        // 无转场动画或已进入完成态：立即执行（兜底）。
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
    // 登记当前播放项：其元数据由播放器内核直接回填，后台扫描排除它，避免重复建播放器。
    VideoMetadataService.setActivePath(entry.path);
    // 不 await：元数据/轨道通过流在初始化完成后回填。
    final ext = _useExternalAudio
        ? FvpPlayer.findExternalAudio(entry.path)
        : const <String>[];
    player.open(entry.path, play: true, externalAudio: ext);
  }

  /// 当播放器解析出当前视频的轨道信息/分辨率/时长时，回填到播放列表条目。
  void _updateCurrentMetaFromPlayer() {
    if (_currentIndex < 0 || _currentIndex >= widget.playlist.entries.length) {
      return;
    }
    final entry = widget.playlist.entries[_currentIndex];
    var meta = entry.meta ?? const VideoMeta();
    // 编码/分辨率/帧率来自 getMediaInfo()。
    final snap = player.snapshotVideoMeta();
    if (snap != null) {
      meta = meta.copyWith(
        codec: snap.codec,
        width: snap.width,
        height: snap.height,
        fps: snap.fps,
      );
    }
    // 解码出的真实分辨率（video-params）优先于 demux 分辨率。
    final w = player.state.width;
    final h = player.state.height;
    if (w != null && h != null) {
      meta = meta.copyWith(width: w, height: h);
    }
    final dur = player.state.duration;
    if (dur > Duration.zero) {
      meta = meta.copyWith(duration: dur);
    }
    if (entry.meta != meta) {
      entry.setMeta(meta);
      // 登记到探测缓存：当前播放项的元数据已由播放器内核回填，后台扫描无需重复探测。
      VideoMetadataService.putCache(entry.path, meta);
    }
  }

  /// 重建 路径→全局播放序号 索引，供播放列表叶子 O(1) 定位当前项，
  /// 替代原先每个叶子用 `entries.indexOf` 的 O(n) 查找（整树重建时是 O(n²)）。
  void _rebuildIndex() {
    _entryIndex.clear();
    for (var i = 0; i < widget.playlist.entries.length; i++) {
      _entryIndex[widget.playlist.entries[i].path] = i;
    }
  }

  void _onCompleted() {
    // 过滤打开瞬间的误触发：播放器有时在 open 后会立刻发一次 completed，
    // 此时播放位置仍接近 0，并非真正播完。若据此自动下一集，会跳到错误的视频
    // （到列表末尾时还会回绕到第一个）。仅当打开已超过 1.5s 且确有播放进度时才视为有效。
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

  /// 重新打开当前视频并以切换前的播放进度继续播放（保留播放/暂停状态），
  /// 不再从开头重播。用于硬件解码、外置音轨开关等需要重载文件才生效的偏好切换。
  /// 重新打开时会依据当前 [_useExternalAudio] 重新探测并挂载同名外置音频。
  Future<void> _reopenCurrentPreservingPosition() async {
    if (widget.playlist.entries.isEmpty) return;
    if (_currentIndex < 0 || _currentIndex >= widget.playlist.entries.length) {
      return;
    }
    final pos = player.state.position;
    final wasPlaying = player.state.playing;
    // 切换期间冻结进度条，避免 open 重置 position/duration 流使进度条跳到 0 再跳回。
    _switchingDecode = true;
    if (mounted) setState(() {});
    final entry = widget.playlist.entries[_currentIndex];
    _lastOpenAt = DateTime.now();
    final ext = _useExternalAudio
        ? FvpPlayer.findExternalAudio(entry.path)
        : const <String>[];
    // 先以暂停方式重新打开，待媒体可定位后 seek 到原进度，再恢复播放/暂停，
    // 避免 open(play:true) 后 seek 被载入过程吞掉而从开头重播。
    await player.open(entry.path, play: false, externalAudio: ext);
    if (pos > Duration.zero) {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline)) {
        if (player.state.duration > Duration.zero) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }
      await player.seek(pos).catchError((_) {});
    }
    if (wasPlaying) {
      await player.play();
    }
    _switchingDecode = false;
    if (mounted) setState(() {});
  }

  /// 切换硬件/软件解码：fvp 的解码器改变需重新载入文件才生效。
  Future<void> _applyHwdec() async {
    player.setHardwareDecode(_useHardwareDecode);
    await _reopenCurrentPreservingPosition();
  }

  /// 切换同名外置音频开关：重新载入当前视频以挂载/卸载外置音轨，保留播放进度。
  Future<void> _applyExternalAudio() async {
    await _reopenCurrentPreservingPosition();
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

  /// 播放列表滚动回调：开始/更新滚动时暂停后台元数据扫描，停止滚动 400ms 后恢复。
  /// 滚动期间零探测，平台线程只服务 UI 与正在播放的视频，滚动/播放都不掉帧。
  void _onPlaylistScroll(ScrollNotification n) {
    if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
      VideoMetadataService.setPaused(true);
      _scrollIdleTimer?.cancel();
      _scrollIdleTimer = Timer(const Duration(milliseconds: 400), () {
        VideoMetadataService.setPaused(false);
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _scrollIdleTimer?.cancel();
    windowManager.removeListener(this);
    if (_isFullscreen) {
      windowManager.setFullScreen(false);
    }
    _playlistScrollController.dispose();
    player.dispose();
    // 停止后台元数据扫描循环并清场，避免 timer/临时探测 controller 泄漏。
    VideoMetadataService.dispose();
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
                    useExternalAudio: _useExternalAudio,
                    onExternalAudioChanged: (v) {
                      setState(() => _useExternalAudio = v);
                      SettingsService.savePlayerUseExternalAudio(v);
                      _applyExternalAudio();
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
    final c = player.controller;
    return GestureDetector(
      onTap: () {
        _togglePlay();
        _revealOnTap();
      },
      onSecondaryTap: _close,
      child: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: player.isInitialized && c != null && c.value.size.width > 0
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final vw = c.value.size.width;
                  final vh = c.value.size.height;
                  // 按 contain 把视频等比放大到容器可容纳的最大尺寸，
                  // 让 fvp 用真实分辨率建的纹理被真正按窗口尺寸显示出来，
                  // 从而随全屏/最大化清晰铺满（比例不符时上下/左右黑边属正常留白）。
                  final scale = min(
                    constraints.maxWidth / vw,
                    constraints.maxHeight / vh,
                  );
                  return SizedBox(
                    width: vw * scale,
                    height: vh * scale,
                    child: VideoPlayer(c),
                  );
                },
              )
            : const SizedBox.shrink(),
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
            _buildProgress(cs, overlay: overlay),
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

  /// 进度条：独立 StatefulWidget，自身订阅位置流。
  /// 拖拽时暂停外部流更新，避免父级频繁 setState 重建 Slider 导致拖拽中断/卡死。
  Widget _buildProgress(ColorScheme cs, {bool overlay = false}) {
    return _ProgressSlider(
      player,
      cs,
      overlay: overlay,
      showMilliseconds: _showMilliseconds,
      freeze: _switchingDecode,
    );
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
    final hasAny = tracks.isNotEmpty;
    return PopupMenuButton<_AudioChoice>(
      tooltip: Strings.t('audioTrack'),
      icon: Icon(Icons.audiotrack, color: iconColor),
      enabled: hasAny || player.audioDisabled,
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<_AudioChoice>>[];
        // Auto：默认首条音轨（无内嵌时即外置首条）。
        final autoChecked = hasAny && !player.audioDisabled && player.activeAudioIndex == null;
        items.add(PopupMenuItem<_AudioChoice>(
          value: const _AudioChoice.auto(),
          child: Row(
            children: [
              if (autoChecked) ...[
                const Icon(Icons.check, size: 16),
                const SizedBox(width: 4),
              ],
              Text(Strings.t('audioAuto')),
            ],
          ),
        ));
        // 各音轨（内嵌 / 外置）。
        for (final t in tracks) {
          final selected =
              !player.audioDisabled && player.activeAudioIndex == t.index;
          items.add(PopupMenuItem<_AudioChoice>(
            value: _AudioChoice.track(t.index),
            child: Row(
              children: [
                if (selected) ...[
                  const Icon(Icons.check, size: 16),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    t.label.isNotEmpty ? t.label : 'Track ${t.index}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ));
        }
        // 关闭音频。
        items.add(PopupMenuItem<_AudioChoice>(
          value: const _AudioChoice.off(),
          child: Row(
            children: [
              if (player.audioDisabled) ...[
                const Icon(Icons.check, size: 16),
                const SizedBox(width: 4),
              ],
              Text(Strings.t('audioOff')),
            ],
          ),
        ));
        return items;
      },
      onSelected: (choice) {
        switch (choice.kind) {
          case _AudioChoiceKind.auto:
            player.setAudioTrackIndex(null);
          case _AudioChoiceKind.track:
            player.setAudioTrackIndex(choice.index);
          case _AudioChoiceKind.off:
            player.disableAudio();
        }
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildSubtitleMenu(Color iconColor) {
    final tracks = player.state.tracks.subtitle;
    return PopupMenuButton<int?>(
      tooltip: Strings.t('subtitle'),
      icon: Icon(Icons.subtitles, color: iconColor),
      enabled: tracks.isNotEmpty || true,
      itemBuilder: (ctx) {
        return [
          PopupMenuItem<int?>(
            value: null,
            child: const Text('Off'),
          ),
          if (tracks.isNotEmpty)
            PopupMenuItem<int?>(
              value: tracks.first.index,
              child: const Text('Auto'),
            ),
          ...tracks.map(
            (t) => PopupMenuItem<int?>(
              value: t.index,
              child: Text(t.label.isNotEmpty ? t.label : 'Track ${t.index}'),
            ),
          ),
        ];
      },
      onSelected: (i) => player.setSubtitleTrackIndex(i),
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
                ValueListenableBuilder<bool>(
                  valueListenable: VideoMetadataService.busy,
                  builder: (context, probing, _) => probing
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        )
                      : const SizedBox.shrink(),
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
                            final isCurrent = gi == _currentIndex && f.isVideo;
                            return _FileLeaf(
                              key: ValueKey(f.path),
                              entry: f,
                              cs: cs,
                              depth: item.depth,
                              isCurrent: isCurrent,
                              onTap: f.isVideo ? () => _playIndex(gi) : null,
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

  /// 渲染展开的文件夹树中的单个「文件夹头」（含展开/收起）。
  /// 折叠/展开时只需置脏扁平列表（_flatDirty）并重建可见项，不会重建整棵大树。
  Widget _buildFolderItem(
    VideoFolderNode node,
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
    void walk(VideoFolderNode node, int depth) {
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
    _rebuildIndex();
    _flatDirty = true;
    setState(() {});
    _playIndex(widget.playlist.entries.length - 1);
    // 新增条目后重新规划后台扫描，把新文件纳入静默慢扫。
    VideoMetadataService.scanAll(widget.playlist.entries);
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
    _rebuildIndex();
    _flatDirty = true;
    setState(() {});
    // 打开新文件夹后重新规划后台扫描，把新列表纳入静默慢扫。
    VideoMetadataService.scanAll(widget.playlist.entries);
  }
}

/// 播放列表「扁平化」后的可见项：文件夹头或文件叶，供 ListView.builder 使用。
class _FlatItem {
  final bool isFolder;
  final VideoFolderNode? folder;
  final VideoEntry? file;
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

/// 播放列表中的单个文件叶（视频可点击播放；非视频灰显）。
/// 自带状态：挂载时只向 [VideoMetadataService] 登记可见性（不发起探测），
/// 元数据由页面级后台扫描按「可见优先」慢慢探测完成后，通过
/// [VideoEntry.setMeta] → [VideoEntry.metaNotifier] 通知本叶自更新，**不会触发父级整树重建**。
/// 探测与挂载彻底解耦：滚动时不会产生新探测请求，滚动纯 UI、不卡；
/// 离屏叶子卸载时注销可见性，扫描仍可在后台慢慢补齐其元数据并缓存。
class _FileLeaf extends StatefulWidget {
  final VideoEntry entry;
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
    // 挂载即登记可见性（不发起探测）：真正的探测由页面级后台扫描按“可见优先”慢扫。
    // 探测与挂载解耦后，滚动时不再产生新探测请求，滚动纯 UI、不卡。
    VideoMetadataService.markVisible(widget.entry.path, true);
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
    // 卸载即注销可见性。
    VideoMetadataService.markVisible(widget.entry.path, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.entry;
    final cs = widget.cs;
    final isCurrent = widget.isCurrent;
    final playable = f.isVideo;
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
                    Text(
                      _metaLine(f),
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${f.meta?.durationText ?? '--'} · ${f.sizeText}',
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
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
}

/// 播放列表中的元信息行：编码格式 · 分辨率 · 帧率，用“·”分隔。
String _metaLine(VideoEntry f) {
  final codec = f.meta?.codecText;
  final codecLabel = (codec != null && codec != '--') ? codec : 'N/A';
  return [
    codecLabel,
    f.meta?.resolutionText ?? '--',
    f.meta?.fpsText ?? '--',
  ].join(' · ');
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
  final FvpPlayer player;
  final ColorScheme cs;
  final bool showMilliseconds;
  final bool freeze;
  final bool overlay;

  const _ProgressSlider(this.player, this.cs,
      {this.showMilliseconds = false,
      this.freeze = false,
      this.overlay = false});

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
      if (!_dragging && mounted && !widget.freeze) setState(() => _position = p);
    });
    _durSub = widget.player.durationStream.listen((d) {
      if (mounted && !widget.freeze) setState(() => _duration = d);
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
    // 全屏浮层背景为深色 → 用白色；窗口模式跟随主题(surface)，用 onSurfaceVariant 保证亮色下可读。
    final timeColor = widget.overlay ? Colors.white70 : widget.cs.onSurfaceVariant;
    return Row(
      children: [
        Text(
          widget.showMilliseconds
              ? VideoMeta.formatClock(position)
              : VideoMeta.formatDuration(position),
          style: TextStyle(color: timeColor, fontSize: 11),
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
          style: TextStyle(color: timeColor, fontSize: 11),
        ),
      ],
    );
  }
}
