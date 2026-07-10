import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../models/comic_page.dart';
import '../services/comic_playlist_service.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import 'smooth_scroll.dart';

/// 内置图片/漫画阅读器。参考 Komikku（平板分页阅读：点击左右分区翻页、
/// LTR/RTL/垂直方向）与 NeeView（中央大图 + 侧边页码/缩略图列表、适应模式、
/// 直接读文件夹与 zip/cbz 压缩包）。窗口/全屏与窗口控件沿用视频播放器骨架。
class ComicReaderPage extends StatefulWidget {
  final ComicPlaylist playlist;
  final int initialIndex;
  final String title;
  final double? initialThumbnailWidth;

  const ComicReaderPage({
    super.key,
    required this.playlist,
    this.initialIndex = 0,
    required this.title,
    this.initialThumbnailWidth,
  });

  @override
  State<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends State<ComicReaderPage> with WindowListener {
  late int _currentIndex;
  bool _isFullscreen = false;
  bool _isMaximized = false;
  bool _showTop = false;
  bool _showBottom = false;
  Timer? _hideTimer;

  ComicLayoutMode _layout = SettingsService.loadReaderLayoutModeSync();
  ComicReadDirection _direction = SettingsService.loadReaderDirectionSync();
  ComicFitMode _fit = SettingsService.loadReaderFitModeSync();
  bool _showThumbs = SettingsService.loadReaderShowThumbnailsSync();
  bool _showPageNumber = SettingsService.loadReaderShowPageNumberSync();
  double _thumbWidth = SettingsService.loadReaderThumbnailWidthSync();

  final ScrollController _thumbScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  /// 缩略图树中已展开的文件夹/压缩包节点路径集合（默认全展开）。
  final Set<String> _expandedNodes = {};

  /// 页码（扁平 entry）按 id 查索引，供树渲染 O(1) 定位高亮与跳转。
  final Map<String, int> _pageIndexById = {};

  /// 双页模式下的“跨页”分组：同一来源（压缩包或同一文件夹）的连续页成对，
  /// 不同来源的页不混排（如根目录的 1.png 不会与 2.zip 的首页拼在同一跨页）。
  late final List<List<int>> _spreads;

  List<ComicPage> get _entries => widget.playlist.entries;

  int get _step => _layout == ComicLayoutMode.double ? 2 : 1;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _currentIndex = widget.initialIndex.clamp(
      0,
      _entries.isEmpty ? 0 : _entries.length - 1,
    );
    for (var i = 0; i < _entries.length; i++) {
      _pageIndexById[_entries[i].id] = i;
    }
    _spreads = _buildSpreads();
    _initExpandedAll();
    if (widget.initialThumbnailWidth != null) {
      _thumbWidth = widget.initialThumbnailWidth!;
    }
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _isMaximized = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureThumbVisible());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    windowManager.removeListener(this);
    if (_isFullscreen) {
      windowManager.setFullScreen(false);
    }
    _thumbScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  // ===== 翻页导航 =====

  void _setIndex(int i) {
    final clamped = i.clamp(0, _entries.length - 1);
    if (clamped == _currentIndex) return;
    _expandAncestors(_entries[clamped]);
    setState(() => _currentIndex = clamped);
    _ensureThumbVisible();
    if (_layout == ComicLayoutMode.vertical) _scrollVerticalTo(clamped);
  }

  void _next() {
    if (_entries.isEmpty) return;
    if (_layout == ComicLayoutMode.double) {
      _setIndex(_nextSpreadStart(_currentIndex));
    } else {
      _setIndex((_currentIndex + _step).clamp(0, _entries.length - 1));
    }
  }

  void _prev() {
    if (_entries.isEmpty) return;
    if (_layout == ComicLayoutMode.double) {
      _setIndex(_prevSpreadStart(_currentIndex));
    } else {
      _setIndex((_currentIndex - _step).clamp(0, _entries.length - 1));
    }
  }

  void _first() => _setIndex(0);
  void _last() => _setIndex(
        _layout == ComicLayoutMode.double && _spreads.isNotEmpty
            ? _spreads.last.first
            : _entries.length - 1,
      );

  void _jumpTo(int i) {
    final clamped = i.clamp(0, _entries.length - 1);
    // 双页模式跳转到点击页所在跨页的起始页，避免把不同来源的页拼在一起。
    final target = _layout == ComicLayoutMode.double
        ? _spreadStart(clamped)
        : clamped;
    _expandAncestors(_entries[target]);
    setState(() => _currentIndex = target);
    _ensureThumbVisible();
    if (_layout == ComicLayoutMode.vertical) _scrollVerticalTo(_currentIndex);
  }

  // ===== 双页跨页分组 =====

  /// 来源标识：压缩包内页取 archivePath；直接图片取所在文件夹路径。
  /// 仅同来源的连续页才允许拼在同一跨页。
  String _sourceKey(ComicPage p) => p.isArchived ? p.archivePath! : p.dirPath;

  /// 将扁平 entries 按“同来源连续页成对、异来源拆开”切分为跨页。
  List<List<int>> _buildSpreads() {
    final sp = <List<int>>[];
    var i = 0;
    final n = _entries.length;
    while (i < n) {
      final key = _sourceKey(_entries[i]);
      if (i + 1 < n && _sourceKey(_entries[i + 1]) == key) {
        sp.add([i, i + 1]);
        i += 2;
      } else {
        sp.add([i]);
        i += 1;
      }
    }
    return sp;
  }

  /// [index] 所在跨页的起始页索引。
  int _spreadStart(int index) {
    final i = index.clamp(0, _entries.length - 1);
    for (final s in _spreads) {
      if (i >= s.first && i <= s.last) return s.first;
    }
    return i;
  }

  int _nextSpreadStart(int index) {
    final start = _spreadStart(index);
    final si = _spreads.indexWhere((s) => s.first == start);
    if (si < 0 || si + 1 >= _spreads.length) return start;
    return _spreads[si + 1].first;
  }

  int _prevSpreadStart(int index) {
    final start = _spreadStart(index);
    final si = _spreads.indexWhere((s) => s.first == start);
    if (si <= 0) return start;
    return _spreads[si - 1].first;
  }

  /// 当前跨页包含的页索引（用于双页模式下高亮与取图）。
  List<int> get _currentSpreadPages {
    final start = _spreadStart(_currentIndex);
    final si = _spreads.indexWhere((s) => s.first == start);
    return si < 0 ? [_currentIndex] : _spreads[si];
  }

  void _scrollVerticalTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _verticalKeys[index];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300), alignment: 0.0);
      }
    });
  }

  void _ensureThumbVisible() {
    if (!_showThumbs) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _thumbKeys[_currentIndex];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.5, duration: const Duration(milliseconds: 250));
      }
    });
  }

  // 每页在缩略图列表 / 垂直视图中的 key，用于滚动定位。
  final Map<int, GlobalKey> _thumbKeys = {};
  final Map<int, GlobalKey> _verticalKeys = {};
  GlobalKey _thumbKey(int i) => _thumbKeys.putIfAbsent(i, () => GlobalKey());
  GlobalKey _verticalKey(int i) => _verticalKeys.putIfAbsent(i, () => GlobalKey());

  // ===== 缩略图文件夹/压缩包树 =====

  /// 默认展开全部节点（保持旧版“全部可见”的体验，同时提供折叠分组）。
  void _initExpandedAll() {
    for (final root in widget.playlist.tree) _collectPaths(root);
  }

  void _collectPaths(ComicFolderNode node) {
    _expandedNodes.add(node.path);
    for (final c in node.children) _collectPaths(c);
  }

  /// 确保包含 [page] 的所有祖先节点已展开，使当前页在树中可见。
  void _expandAncestors(ComicPage page) {
    for (final root in widget.playlist.tree) {
      final chain = <ComicFolderNode>[];
      if (_nodeContains(root, page, chain)) {
        var changed = false;
        for (final n in chain) {
          if (_expandedNodes.add(n.path)) changed = true;
        }
        if (changed) setState(() {});
        return;
      }
    }
  }

  bool _nodeContains(
    ComicFolderNode node,
    ComicPage page,
    List<ComicFolderNode> chain,
  ) {
    chain.add(node);
    if (node.files.any((f) => f.id == page.id)) return true;
    for (final c in node.children) {
      if (_nodeContains(c, page, chain)) return true;
    }
    chain.removeLast();
    return false;
  }

  /// 计算当前应显示的树行（仅展开节点可见），保持与扁平 entries 相同的 DFS 顺序。
  List<_TreeRow> _visibleRows() {
    final rows = <_TreeRow>[];
    for (final root in widget.playlist.tree) {
      _appendVisible(root, 0, rows);
    }
    return rows;
  }

  void _appendVisible(ComicFolderNode node, int depth, List<_TreeRow> rows) {
    final hasContent = node.children.isNotEmpty || node.files.isNotEmpty;
    if (!hasContent) return;
    rows.add(_TreeRow.header(node, depth));
    if (_expandedNodes.contains(node.path)) {
      for (final f in node.files) {
        rows.add(_TreeRow.file(f, depth + 1));
      }
      for (final c in node.children) {
        _appendVisible(c, depth + 1, rows);
      }
    }
  }

  Widget _treeHeaderRow(ColorScheme cs, ComicFolderNode node, int depth) {
    final expanded = _expandedNodes.contains(node.path);
    return InkWell(
      onTap: () => setState(() {
        if (expanded) {
          _expandedNodes.remove(node.path);
        } else {
          _expandedNodes.add(node.path);
        }
      }),
      child: Container(
        padding: EdgeInsets.only(
          left: 8.0 + depth * 14,
          right: 8,
          top: 4,
          bottom: 4,
        ),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Icon(
              node.isArchive ? Icons.folder_zip : Icons.folder,
              size: 14,
              color: node.isArchive ? Colors.orange.shade400 : Colors.amber.shade400,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${node.files.length}',
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 设置切换 =====

  void _setLayout(ComicLayoutMode m) {
    setState(() => _layout = m);
    SettingsService.saveReaderLayoutMode(m);
    if (m == ComicLayoutMode.vertical) _scrollVerticalTo(_currentIndex);
  }

  void _toggleDirection() {
    final next = _direction == ComicReadDirection.ltr
        ? ComicReadDirection.rtl
        : ComicReadDirection.ltr;
    setState(() => _direction = next);
    SettingsService.saveReaderDirection(next);
  }

  void _setFit(ComicFitMode f) {
    setState(() => _fit = f);
    SettingsService.saveReaderFitMode(f);
  }

  void _toggleThumbs() {
    setState(() => _showThumbs = !_showThumbs);
    SettingsService.saveReaderShowThumbnails(_showThumbs);
    if (_showThumbs) _ensureThumbVisible();
  }

  void _togglePageNumber() {
    setState(() => _showPageNumber = !_showPageNumber);
    SettingsService.saveReaderShowPageNumber(_showPageNumber);
  }

  // ===== 窗口 / 全屏 =====

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

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
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
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
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

  void _toggleUiOverlay() {
    if (!_isFullscreen) return;
    setState(() {
      _showTop = !_showTop;
      _showBottom = !_showBottom;
    });
    _hideTimer?.cancel();
    if (_showBottom || _showTop) {
      _hideTimer = Timer(const Duration(seconds: 3), _hideAll);
    }
  }

  void _close() {
    if (_isFullscreen) windowManager.setFullScreen(false);
    Navigator.of(context).pop();
  }

  // ===== 键盘 =====

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final rtl = _direction == ComicReadDirection.rtl;
    switch (event.logicalKey) {
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
      case LogicalKeyboardKey.home:
        _first();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _last();
        return KeyEventResult.handled;
    }
    if (_layout == ComicLayoutMode.vertical) {
      // 垂直模式让方向键交由列表滚动。
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        rtl ? _prev() : _next();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        rtl ? _next() : _prev();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.space:
        _next();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.pageUp:
        _prev();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ===== 构建 =====

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
              Expanded(child: _buildReaderArea(cs)),
              if (_showThumbs && !_isFullscreen) ...[
                _ResizeHandle(
                  onDrag: (dx) {
                    final next = (_thumbWidth - dx).clamp(140.0, 460.0);
                    if (next != _thumbWidth) {
                      setState(() => _thumbWidth = next);
                    }
                  },
                  onDragEnd: () =>
                      SettingsService.saveReaderThumbnailWidth(_thumbWidth),
                ),
                _buildThumbnailPanel(cs),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReaderArea(ColorScheme cs) {
    if (_isFullscreen) {
      return Stack(
        children: [
          Positioned.fill(child: _buildContentArea(cs)),
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
        Expanded(child: _buildContentArea(cs)),
        _buildControlBar(cs),
      ],
    );
  }

  Widget _buildContentArea(ColorScheme cs) {
    if (_entries.isEmpty) {
      return Center(
        child: Text(
          Strings.t('pageListEmpty'),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      );
    }
    final Widget content;
    switch (_layout) {
      case ComicLayoutMode.vertical:
        content = _buildVertical();
      case ComicLayoutMode.double:
        content = _buildDouble();
      case ComicLayoutMode.single:
        content = _buildSingle();
    }
    return Stack(
      children: [
        Positioned.fill(child: content),
        if (_showPageNumber)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${_entries.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSingle() {
    final page = _entries[_currentIndex];
    return LayoutBuilder(
      builder: (context, cons) {
        return _ZoomablePage(
          pageKey: _currentIndex,
          viewportWidth: cons.maxWidth,
          viewportHeight: cons.maxHeight,
          invertHorizontal: _direction == ComicReadDirection.rtl,
          onNext: _next,
          onPrev: _prev,
          onToggleUi: _toggleUiOverlay,
          onClose: _close,
          child: _fitWidget(page, cons.maxWidth, cons.maxHeight),
        );
      },
    );
  }

  Widget _buildDouble() {
    final rtl = _direction == ComicReadDirection.rtl;
    final spread = _currentSpreadPages;
    final left = _entries[spread[0]];
    final ComicPage? right =
        spread.length > 1 ? _entries[spread[1]] : null;
    return LayoutBuilder(
      builder: (context, cons) {
        final halfW = cons.maxWidth / 2;
        final pageA = SizedBox(
          width: halfW,
          height: cons.maxHeight,
          child: _ArchiveOrFileImage(
            page: left,
            fit: BoxFit.contain,
            alignment: rtl ? Alignment.centerLeft : Alignment.centerRight,
          ),
        );
        final pageB = right == null
            ? SizedBox(width: halfW, height: cons.maxHeight)
            : SizedBox(
                width: halfW,
                height: cons.maxHeight,
                child: _ArchiveOrFileImage(
                  page: right,
                  fit: BoxFit.contain,
                  alignment: rtl ? Alignment.centerRight : Alignment.centerLeft,
                ),
              );
        // LTR：左=当前页，右=下一页；RTL：右=当前页，左=下一页。
        final children = rtl ? [pageB, pageA] : [pageA, pageB];
        return _ZoomablePage(
          pageKey: spread[0],
          viewportWidth: cons.maxWidth,
          viewportHeight: cons.maxHeight,
          invertHorizontal: rtl,
          onNext: _next,
          onPrev: _prev,
          onToggleUi: _toggleUiOverlay,
          onClose: _close,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
        );
      },
    );
  }

  Widget _buildVertical() {
    return LayoutBuilder(
      builder: (context, cons) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTap: _close,
          child: Scrollbar(
          controller: _verticalScrollController,
          child: SmoothScroll(
            controller: _verticalScrollController,
            builder: (context, controller, physics) => ListView.builder(
              controller: controller,
              physics: physics,
              itemCount: _entries.length,
              itemBuilder: (context, i) {
                final page = _entries[i];
                return Container(
                  key: _verticalKey(i),
                  alignment: Alignment.center,
                  child: _ArchiveOrFileImage(
                    page: page,
                    width: cons.maxWidth,
                  ),
                );
              },
            ),
          ),
        ),
      );
      },
    );
  }

  /// 按 fit 模式为单页构建带尺寸约束的图片（供 _ZoomablePage 平移/缩放）。
  Widget _fitWidget(ComicPage page, double vw, double vh) {
    switch (_fit) {
      case ComicFitMode.width:
        return SizedBox(
          width: vw,
          child: _ArchiveOrFileImage(page: page, width: vw),
        );
      case ComicFitMode.height:
        return SizedBox(
          height: vh,
          child: _ArchiveOrFileImage(page: page, height: vh),
        );
      case ComicFitMode.page:
        return SizedBox(
          width: vw,
          height: vh,
          child: _ArchiveOrFileImage(page: page, fit: BoxFit.contain),
        );
      case ComicFitMode.original:
        return _ArchiveOrFileImage(page: page);
    }
  }

  // ===== 顶栏 / 浮层 =====

  Widget _buildTopBar(ColorScheme cs) {
    final current = _entries.isEmpty ? null : _entries[_currentIndex];
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
                    Icon(Icons.auto_stories, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        current == null
                            ? widget.title
                            : '${widget.title}  ·  ${current.name}',
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

  Widget _buildTopOverlay(ColorScheme cs) {
    final current = _entries.isEmpty ? null : _entries[_currentIndex];
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
          tooltip:
              _isFullscreen ? Strings.t('exitFullscreen') : Strings.t('fullscreen'),
          onPressed: _toggleFullscreen,
        ),
        IconButton(
          icon: const Icon(Icons.close),
          color: Colors.redAccent,
          iconSize: 18,
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: Strings.t('closeReader'),
          onPressed: _close,
        ),
      ],
    );
  }

  // ===== 底部控制条 =====

  Widget _buildControlBar(ColorScheme cs, {bool overlay = false}) {
    final Color iconColor = overlay ? Colors.white : cs.onSurface;
    final isVertical = _layout == ComicLayoutMode.vertical;
    return Container(
      decoration: BoxDecoration(
        color: overlay ? Colors.black.withValues(alpha: 0.82) : cs.surface,
        border:
            overlay ? null : Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.first_page),
              color: iconColor,
              tooltip: Strings.t('home'),
              onPressed: _first,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              color: iconColor,
              tooltip: _direction == ComicReadDirection.rtl
                  ? Strings.t('nextPage')
                  : Strings.t('prevPage'),
              onPressed:
                  _direction == ComicReadDirection.rtl ? _next : _prev,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              color: iconColor,
              tooltip: _direction == ComicReadDirection.rtl
                  ? Strings.t('prevPage')
                  : Strings.t('nextPage'),
              onPressed:
                  _direction == ComicReadDirection.rtl ? _prev : _next,
            ),
            IconButton(
              icon: const Icon(Icons.last_page),
              color: iconColor,
              tooltip: Strings.t('end'),
              onPressed: _last,
            ),
            const SizedBox(width: 8),
            Text(
              '${_currentIndex + 1} / ${_entries.length}',
              style: TextStyle(color: iconColor, fontSize: 12),
            ),
            const Spacer(),
            _layoutButton(iconColor),
            IconButton(
              icon: Icon(_direction == ComicReadDirection.rtl
                  ? Icons.format_textdirection_r_to_l
                  : Icons.format_textdirection_l_to_r),
              color: isVertical ? iconColor.withValues(alpha: 0.4) : iconColor,
              tooltip: _direction == ComicReadDirection.rtl
                  ? Strings.t('directionRTL')
                  : Strings.t('directionLTR'),
              onPressed: isVertical ? null : _toggleDirection,
            ),
            _fitButton(iconColor),
            IconButton(
              icon: const Icon(Icons.tag),
              color: _showPageNumber ? cs.primary : iconColor,
              tooltip: Strings.t('showPageNumber'),
              onPressed: _togglePageNumber,
            ),
            IconButton(
              icon: Icon(_showThumbs
                  ? Icons.view_sidebar
                  : Icons.view_sidebar_outlined),
              color: iconColor,
              tooltip: Strings.t('pageList'),
              onPressed: _toggleThumbs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _layoutButton(Color iconColor) {
    IconData icon;
    switch (_layout) {
      case ComicLayoutMode.single:
        icon = Icons.crop_portrait;
      case ComicLayoutMode.double:
        icon = Icons.menu_book;
      case ComicLayoutMode.vertical:
        icon = Icons.view_day;
    }
    return PopupMenuButton<ComicLayoutMode>(
      tooltip: Strings.t('readingLayout'),
      icon: Icon(icon, color: iconColor),
      initialValue: _layout,
      onSelected: _setLayout,
      itemBuilder: (ctx) => [
        _layoutItem(ComicLayoutMode.single, Icons.crop_portrait,
            Strings.t('layoutSingle')),
        _layoutItem(
            ComicLayoutMode.double, Icons.menu_book, Strings.t('layoutDouble')),
        _layoutItem(ComicLayoutMode.vertical, Icons.view_day,
            Strings.t('layoutVertical')),
      ],
    );
  }

  PopupMenuItem<ComicLayoutMode> _layoutItem(
      ComicLayoutMode m, IconData icon, String label) {
    return PopupMenuItem<ComicLayoutMode>(
      value: m,
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(label),
          if (m == _layout) ...[const SizedBox(width: 8), const Icon(Icons.check, size: 14)],
        ],
      ),
    );
  }

  Widget _fitButton(Color iconColor) {
    IconData icon;
    switch (_fit) {
      case ComicFitMode.width:
        icon = Icons.swap_horiz;
      case ComicFitMode.height:
        icon = Icons.swap_vert;
      case ComicFitMode.page:
        icon = Icons.fit_screen;
      case ComicFitMode.original:
        icon = Icons.crop_original;
    }
    return PopupMenuButton<ComicFitMode>(
      tooltip: Strings.t('fitMode'),
      icon: Icon(icon, color: iconColor),
      initialValue: _fit,
      onSelected: _setFit,
      itemBuilder: (ctx) => [
        _fitItem(ComicFitMode.width, Icons.swap_horiz, Strings.t('fitWidth')),
        _fitItem(ComicFitMode.height, Icons.swap_vert, Strings.t('fitHeight')),
        _fitItem(ComicFitMode.page, Icons.fit_screen, Strings.t('fitPage')),
        _fitItem(ComicFitMode.original, Icons.crop_original,
            Strings.t('fitOriginal')),
      ],
    );
  }

  PopupMenuItem<ComicFitMode> _fitItem(
      ComicFitMode f, IconData icon, String label) {
    return PopupMenuItem<ComicFitMode>(
      value: f,
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(label),
          if (f == _fit) ...[const SizedBox(width: 8), const Icon(Icons.check, size: 14)],
        ],
      ),
    );
  }

  // ===== 侧边缩略图 / 页码列表 =====

  Widget _buildThumbnailPanel(ColorScheme cs) {
    return Container(
      width: _thumbWidth,
      color: cs.surfaceContainerHigh,
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(Icons.collections, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  Strings.t('pageList'),
                  style: TextStyle(fontSize: 13, color: cs.onSurface),
                ),
                const Spacer(),
                Text(
                  '${_entries.length}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Text(
                      Strings.t('pageListEmpty'),
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  )
                : Scrollbar(
                    controller: _thumbScrollController,
                    thumbVisibility: true,
                    child: SmoothScroll(
                      controller: _thumbScrollController,
                      builder: (context, controller, physics) {
                        final rows = _visibleRows();
                        return ListView.builder(
                          controller: controller,
                          physics: physics,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: rows.length,
                          itemBuilder: (context, i) {
                            final row = rows[i];
                            if (row.node != null) {
                              return _treeHeaderRow(cs, row.node!, row.depth);
                            }
                            final index = _pageIndexById[row.page!.id]!;
                            return _thumbItem(cs, index, indent: row.depth * 14.0);
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _thumbItem(ColorScheme cs, int index, {double indent = 0}) {
    final page = _entries[index];
    final isCurrent = _layout == ComicLayoutMode.double
        ? _currentSpreadPages.contains(index)
        : index == _currentIndex;
    return InkWell(
      key: _thumbKey(index),
      onTap: () => _jumpTo(index),
      child: Container(
        padding: EdgeInsets.only(
          left: 8 + indent,
          right: 8,
          top: 5,
          bottom: 5,
        ),
        decoration: isCurrent
            ? BoxDecoration(
                border: Border(left: BorderSide(color: cs.primary, width: 3)),
                color: cs.primary.withValues(alpha: 0.16),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isCurrent ? cs.primary : cs.onSurfaceVariant,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            Container(
              width: 54,
              height: 72,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              clipBehavior: Clip.antiAlias,
              child: _ArchiveOrFileImage(
                page: page,
                fit: BoxFit.cover,
                cacheWidth: 120,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    page.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isCurrent ? cs.primary : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    page.isArchived ? '${Strings.t('layoutDouble')[0]}· ${page.sizeText}' : page.sizeText,
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 缩略图树的一行描述：要么是文件夹/压缩包节点表头，要么是图片文件。
class _TreeRow {
  final ComicFolderNode? node;
  final ComicPage? page;
  final int depth;

  _TreeRow.header(this.node, this.depth) : page = null;
  _TreeRow.file(this.page, this.depth) : node = null;
}

/// 直接图片或压缩包内图片的统一显示：直接图用 [Image.file]，压缩包内条目
/// 优先用已缓存字节同步显示，否则异步解压后用 [Image.memory]。
class _ArchiveOrFileImage extends StatelessWidget {
  final ComicPage page;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final Alignment alignment;

  const _ArchiveOrFileImage({
    required this.page,
    this.fit,
    this.width,
    this.height,
    this.cacheWidth,
    this.alignment = Alignment.center,
  });

  Widget _error(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image, color: Colors.white38, size: 32),
          const SizedBox(height: 6),
          Text(
            Strings.t('imageLoadFailed'),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!page.isArchived) {
      return Image.file(
        File(page.sourcePath!),
        fit: fit,
        width: width,
        height: height,
        alignment: alignment,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _error(context),
      );
    }
    final cached = ComicPlaylistService.peekPageBytes(page.id);
    if (cached != null) {
      return Image.memory(
        cached,
        fit: fit,
        width: width,
        height: height,
        alignment: alignment,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _error(context),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: ComicPlaylistService.readPageBytes(page),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final bytes = snap.data;
        if (bytes == null) return _error(context);
        return Image.memory(
          bytes,
          fit: fit,
          width: width,
          height: height,
          alignment: alignment,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _error(context),
        );
      },
    );
  }
}

/// 单页/双页模式的缩放平移容器：拖拽平移、捏合缩放、Ctrl+滚轮缩放、普通滚轮翻页、
/// 点击左右分区翻页、点击中间切换 UI（全屏）、双击在 1x/2x 间切换。翻页时重置变换。
class _ZoomablePage extends StatefulWidget {
  final int pageKey;
  final double viewportWidth;
  final double viewportHeight;
  final bool invertHorizontal;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onToggleUi;
  final VoidCallback onClose;
  final Widget child;

  const _ZoomablePage({
    required this.pageKey,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.invertHorizontal,
    required this.onNext,
    required this.onPrev,
    required this.onToggleUi,
    required this.onClose,
    required this.child,
  });

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  bool _moved = false;

  @override
  void didUpdateWidget(covariant _ZoomablePage old) {
    super.didUpdateWidget(old);
    if (old.pageKey != widget.pageKey) {
      _reset();
    }
  }

  void _reset() {
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.focalPoint;
    _moved = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _scale = (_startScale * d.scale).clamp(1.0, 5.0);
      _offset = _startOffset + (d.focalPoint - _startFocal);
      if ((d.focalPoint - _startFocal).distance > 4) _moved = true;
      _clampOffset();
    });
  }

  void _clampOffset() {
    // 缩放为 1 且内容不超出视口时，回中；否则允许自由平移。
    if (_scale <= 1.0) {
      _offset = Offset.zero;
    }
  }

  void _handleTapUp(TapUpDetails d) {
    if (_moved) return;
    final w = widget.viewportWidth;
    final dx = d.localPosition.dx;
    if (dx < w / 3) {
      widget.invertHorizontal ? widget.onNext() : widget.onPrev();
    } else if (dx > w * 2 / 3) {
      widget.invertHorizontal ? widget.onPrev() : widget.onNext();
    } else {
      widget.onToggleUi();
    }
  }

  void _handleDoubleTap() {
    setState(() {
      if (_scale > 1.0) {
        _scale = 1.0;
        _offset = Offset.zero;
      } else {
        _scale = 2.0;
      }
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl) {
      setState(() {
        final delta = event.scrollDelta.dy > 0 ? -0.2 : 0.2;
        _scale = (_scale + delta).clamp(1.0, 5.0);
        _clampOffset();
      });
    } else {
      if (event.scrollDelta.dy > 0) {
        widget.onNext();
      } else {
        widget.onPrev();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTapUp,
        onDoubleTap: _handleDoubleTap,
        onSecondaryTap: widget.onClose,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: ClipRect(
          child: Transform(
            transform: Matrix4.identity()
              ..translate(_offset.dx, _offset.dy)
              ..scale(_scale),
            alignment: Alignment.center,
            child: OverflowBox(
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              alignment: Alignment.center,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 阅读区与缩略图面板之间的可拖拽分隔条。
class _ResizeHandle extends StatelessWidget {
  final void Function(double dx) onDrag;
  final VoidCallback? onDragEnd;

  const _ResizeHandle({required this.onDrag, this.onDragEnd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: (d) => onDrag(d.delta.dx),
      onPanEnd: (_) => onDragEnd?.call(),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: SizedBox(
          width: 5,
          child: Center(child: Container(width: 1, color: cs.outlineVariant)),
        ),
      ),
    );
  }
}
