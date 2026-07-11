import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../models/library_item.dart';
import '../models/category_node.dart';
import '../models/direct_file.dart';
import '../providers/library_state.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import 'item_card.dart';
import 'folder_card.dart';
import 'file_card.dart';
import 'dart:io';
import 'file_browser_panel.dart';
import 'file_properties_dialog.dart';
import 'exe_picker_dialog.dart';
import '../models/exe_record.dart';
import '../services/script_service.dart';
import 'class_nav_bar.dart';
import 'package:flutter/services.dart';
import 'compact_level.dart';
import 'script_result_dialog.dart';
import 'smooth_scroll.dart';

/// 分组扁平化后的单元：要么是一张普通卡片（[isHeader]=false），要么是一个
/// 占满整行的分组标题（[isHeader]=true）。单个 SliverGrid 按此顺序排版，
/// 既保留清晰的分组视觉，又让 SliverGrid 数量恒为 ≤3（不再一个分组一个）。
class _FlatEntry<T> {
  final T? entry;
  final String? headerLabel;
  final bool isHeader;

  _FlatEntry.card(this.entry)
      : isHeader = false,
        headerLabel = null;
  _FlatEntry.header(this.headerLabel)
      : isHeader = true,
        entry = null;
}

/// 单 section 内统一用一个 SliverGrid 排版：每个分组的首个单元是占满整行的
/// 分组标题（[headerIndices]），其余为普通卡片格。这样分组视觉清晰，同时
/// SliverGrid 数量恒为 ≤3（不再是一个分组一个），消除拖动重排卡顿。
class _SectionGridDelegate extends SliverGridDelegate {
  final int crossAxisCount;
  final double mainAxisExtent;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double headerExtent;
  final Set<int> headerIndices;
  final int childCount;

  const _SectionGridDelegate({
    required this.crossAxisCount,
    required this.mainAxisExtent,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.headerExtent,
    required this.headerIndices,
    required this.childCount,
  });

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    return _SectionGridLayout(
      crossAxisCount: crossAxisCount,
      mainAxisExtent: mainAxisExtent,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
      headerExtent: headerExtent,
      headerIndices: headerIndices,
      childCount: childCount,
      crossAxisExtent: constraints.crossAxisExtent,
    );
  }

  @override
  bool shouldRelayout(covariant _SectionGridDelegate old) {
    return old.crossAxisCount != crossAxisCount ||
        old.mainAxisExtent != mainAxisExtent ||
        old.crossAxisSpacing != crossAxisSpacing ||
        old.mainAxisSpacing != mainAxisSpacing ||
        old.headerExtent != headerExtent ||
        old.headerIndices != headerIndices ||
        old.childCount != childCount;
  }
}

/// 支持「整行标题 + 普通卡片格」混合布局的 SliverGridLayout。
/// 标题单元占满整行（crossAxisExtent=整宽），卡片按 crossAxisCount 排列。
/// 预计算每张单元的绝对 scrollOffset / crossOffset，查询走二分，滚动高效。
class _SectionGridLayout extends SliverGridLayout {
  _SectionGridLayout({
    required this.crossAxisCount,
    required this.mainAxisExtent,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.headerExtent,
    required this.headerIndices,
    required this.childCount,
    required this.crossAxisExtent,
  }) {
    _compute();
  }

  final int crossAxisCount;
  final double mainAxisExtent;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double headerExtent;
  final Set<int> headerIndices;
  final int childCount;
  final double crossAxisExtent;

  late final double _tileWidth;
  late final List<double> _starts;
  late final List<double> _extents;
  late final List<double> _crossOffsets;
  late final double _maxScroll;

  void _compute() {
    _tileWidth =
        (crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1)) /
        crossAxisCount;
    _starts = List<double>.filled(childCount, 0);
    _extents = List<double>.filled(childCount, 0);
    _crossOffsets = List<double>.filled(childCount, 0);
    var offset = 0.0;
    var col = 0;
    for (var i = 0; i < childCount; i++) {
      if (headerIndices.contains(i)) {
        // 标题前若本行有未填完的卡片，先换行，避免标题与上一组卡片同行。
        if (col > 0) {
          offset += mainAxisExtent + mainAxisSpacing;
          col = 0;
        }
        _starts[i] = offset;
        _extents[i] = headerExtent;
        _crossOffsets[i] = 0;
        offset += headerExtent + mainAxisSpacing;
        col = 0;
      } else {
        _starts[i] = offset;
        _extents[i] = mainAxisExtent;
        _crossOffsets[i] = col * (_tileWidth + crossAxisSpacing);
        col++;
        if (col >= crossAxisCount) {
          offset += mainAxisExtent + mainAxisSpacing;
          col = 0;
        }
      }
    }
    _maxScroll = col > 0 ? offset + mainAxisExtent : offset;
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final isHeader = headerIndices.contains(index);
    return SliverGridGeometry(
      scrollOffset: _starts[index],
      crossAxisOffset: _crossOffsets[index],
      mainAxisExtent: _extents[index],
      crossAxisExtent: isHeader ? crossAxisExtent : _tileWidth,
    );
  }

  @override
  double computeMaxScrollOffset(int childCount) => _maxScroll;

  int _firstVisible(double scrollOffset) {
    if (childCount == 0) return 0;
    var lo = 0;
    var hi = childCount - 1;
    var ans = childCount - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (_starts[mid] + _extents[mid] > scrollOffset) {
        ans = mid;
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }
    return ans;
  }

  int _lastVisible(double scrollOffset) {
    if (childCount == 0) return 0;
    var lo = 0;
    var hi = childCount - 1;
    var ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (_starts[mid] <= scrollOffset) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) =>
      _firstVisible(scrollOffset);

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) =>
      _lastVisible(scrollOffset);
}

class GridArea extends StatefulWidget {
  final List<LibraryItem> items;
  final List<CategoryNode> subDirs;
  final List<DirectFile> files;
  final LibraryState state;
  final ScriptService scriptService;
  final double filePanelHeight;
  final void Function(double delta) onFilePanelResize;
  final VoidCallback? onFilePanelResizeEnd;
  final void Function(List<LibraryItem> targets, bool isBatch) onEditRequest;
  final void Function(CategoryNode folder) onFolderEditRequest;
  final void Function(List<CategoryNode> folders) onFolderBatchEditRequest;
  final VoidCallback? onCreateItem;
  final void Function(List<String> paths)? onFileDrop;
  final GridSettings gridSettings;
  final double middleOpacity;
  final void Function(LibraryItem item, {String? startPath}) onOpenVideoPlayer;
  final void Function(LibraryItem item, {String? startPath}) onOpenAudioPlayer;
  final void Function(LibraryItem item, {String? startPath}) onOpenComicReader;
  final void Function(LibraryItem item, {String? startPath}) onOpenEbookReader;

  const GridArea({
    super.key,
    required this.items,
    required this.subDirs,
    required this.files,
    required this.state,
    required this.scriptService,
    required this.filePanelHeight,
    required this.onFilePanelResize,
    this.onFilePanelResizeEnd,
    required this.onEditRequest,
    required this.onFolderEditRequest,
    required this.onFolderBatchEditRequest,
    required this.gridSettings,
    this.middleOpacity = 1.0,
    this.onCreateItem,
    this.onFileDrop,
    required     this.onOpenVideoPlayer,
    required this.onOpenAudioPlayer,
    required this.onOpenComicReader,
    required this.onOpenEbookReader,
  });

  @override
  State<GridArea> createState() => _GridAreaState();
}

class _GridAreaState extends State<GridArea> with SingleTickerProviderStateMixin {
  // Bridge getters — allow method bodies to reference fields by name
  // without changing every `this.xxx` to `widget.xxx`.
  List<LibraryItem> get items => widget.items;
  List<CategoryNode> get subDirs => widget.subDirs;
  List<DirectFile> get files => widget.files;
  LibraryState get state => widget.state;
  ScriptService get scriptService => widget.scriptService;
  double get filePanelHeight => widget.filePanelHeight;
  void Function(double delta) get onFilePanelResize => widget.onFilePanelResize;
  VoidCallback? get onFilePanelResizeEnd => widget.onFilePanelResizeEnd;
  void Function(List<LibraryItem> targets, bool isBatch) get onEditRequest =>
      widget.onEditRequest;
  void Function(CategoryNode folder) get onFolderEditRequest =>
      widget.onFolderEditRequest;
  void Function(List<CategoryNode> folders) get onFolderBatchEditRequest =>
      widget.onFolderBatchEditRequest;
  VoidCallback? get onCreateItem => widget.onCreateItem;
  void Function(List<String> paths)? get onFileDrop => widget.onFileDrop;
  GridSettings get gridSettings => widget.gridSettings;
  void Function(LibraryItem item, {String? startPath}) get onOpenComicReader =>
      widget.onOpenComicReader;
  void Function(LibraryItem item, {String? startPath}) get onOpenEbookReader =>
      widget.onOpenEbookReader;
  double get middleOpacity => widget.middleOpacity;

  /// 文件面板的根 key，用于在嵌套 DropTarget 场景下排除其命中区域，
  /// 避免拖入底部面板时外层网格区也触发一次复制。
  final GlobalKey _panelKey = GlobalKey();

  /// 底部文件面板进出场动画控制器：作为面板滑入/滑出与中间内容让位的唯一动画源。
  /// 同一进度 v 同时驱动内容让位、面板位移、FAB 位置，确保三者完全同步。
  late final AnimationController _panelAnim;

  /// 退出动画期间仍需非空 item 来构建面板；可见时捕获并保留至动画结束。
  LibraryItem? _panelItem;

  @override
  void initState() {
    super.initState();
    _panelAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (state.fileBrowserVisible && state.selectedItem != null) {
      _panelAnim.value = 1;
      _panelItem = state.selectedItem;
    }
  }

  @override
  void dispose() {
    _panelAnim.dispose();
    super.dispose();
  }

  // ===== Drag performance cache =====
  // Tier 1: full cache — same widget returned, Flutter skips update entirely.
  Widget? _cachedScrollContent;
  String? _cachedFullKey;
  // Tier 2: delegate cache — same SliverChildBuilderDelegate instances reused
  // with new gridDelegate, Flutter skips performRebuild, only relayouts.
  // One delegate per SECTION (not per group): the section's groups are
  // flattened into a single SliverGrid, so there are ≤3 SliverGrids total
  // instead of one-per-group (dozens). This is the key drag-stutter fix —
  // relayout cost no longer multiplies by group count.
  String? _cachedDelegateKey;
  SliverChildBuilderDelegate? _cachedFolderDelegate;
  SliverChildBuilderDelegate? _cachedItemDelegate;
  SliverChildBuilderDelegate? _cachedFileDelegate;
  List<_FlatEntry<CategoryNode>>? _cachedFolderFlat;
  List<_FlatEntry<LibraryItem>>? _cachedItemFlat;
  List<_FlatEntry<DirectFile>>? _cachedFileFlat;

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);

    // 依据可见性驱动面板进出场动画（带状态守卫，build 重复调用时为 no-op）。
    // 同一进度 v 同时驱动「内容让位高度」与「面板位移」，二者完全同步。
    final visible = state.fileBrowserVisible && state.selectedItem != null;
    if (visible) {
      _panelItem = state.selectedItem;
      if (!_panelAnim.isCompleted) _panelAnim.forward();
    } else {
      if (!_panelAnim.isDismissed) _panelAnim.reverse();
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyA &&
            HardwareKeyboard.instance.isControlPressed) {
          state.selectAll(items);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: _DropHighlight(
        onFilesDropped: (paths) => onFileDrop?.call(paths),
        excludeKey: _panelKey,
        bottomInset: visible ? filePanelHeight + 4 : 0,
        child: AnimatedBuilder(
          animation: _panelAnim,
          builder: (context, _) {
            final v = _panelAnim.value;
            final panelTotal = filePanelHeight + 4;
            final reserved = panelTotal * v;
            return Stack(
              children: [
                Column(
                  children: [
                    ClassNavBar(state: state),
                    Expanded(
                      child: (items.isEmpty && subDirs.isEmpty && files.isEmpty)
                          ? Center(
                              child: Text(
                                Strings.t('noItems'),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 12 * c,
                                ),
                              ),
                            )
                          : Padding(
                              padding: EdgeInsets.all(8 * c)
                                  .copyWith(bottom: 8 * c + reserved),
                              child: _buildGrid(context, c),
                            ),
                    ),
                  ],
                ),
                if (v > 0 && _panelItem != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: panelTotal,
                    child: Transform.translate(
                      offset: Offset(0, (1 - v) * panelTotal),
                      child: Opacity(
                        opacity: v,
                        child: ClipRect(
                          child: Column(
                            children: [
                              MouseRegion(
                                cursor: SystemMouseCursors.resizeUpDown,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onPanUpdate: (details) =>
                                      onFilePanelResize(details.delta.dy),
                                  onPanEnd: (_) => onFilePanelResizeEnd?.call(),
                                  child: Container(
                                    height: 4,
                                    color: Colors.transparent,
                                  ),
                                ),
                              ),
                              FileBrowserPanel(
                                key: _panelKey,
                                item: _panelItem!,
                                state: state,
                                scriptService: scriptService,
                                height: filePanelHeight,
                                backgroundOpacity: middleOpacity,
                                gifMode: gridSettings.fileGifMode,
                                onPlayProject: () =>
                                    widget.onOpenVideoPlayer(_panelItem!),
                                onPlayVideoFile: (path) => widget.onOpenVideoPlayer(
                                  _panelItem!,
                                  startPath: path,
                                ),
                                onPlayAudioProject: () =>
                                    widget.onOpenAudioPlayer(_panelItem!),
                                onPlayAudioFile: (path) =>
                                    widget.onOpenAudioPlayer(
                                  _panelItem!,
                                  startPath: path,
                                ),
                                onReadProject: () =>
                                    widget.onOpenComicReader(_panelItem!),
                                onReadImageFile: (path) =>
                                    widget.onOpenComicReader(
                                  _panelItem!,
                                  startPath: path,
                                ),
                                onReadEbookProject: () =>
                                    widget.onOpenEbookReader(_panelItem!),
                                onReadEbookFile: (path) =>
                                    widget.onOpenEbookReader(
                                  _panelItem!,
                                  startPath: path,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 16 * c,
                  bottom: panelTotal * v + 16 * c,
                  child: FloatingActionButton.small(
                    heroTag: 'createItem',
                    onPressed: onCreateItem,
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    final minCardWidth = gridSettings.minCardWidth;
    final maxCardWidth = gridSettings.maxCardWidth;
    final spacing = 8.0 * c;
    final fixedPerRow = gridSettings.itemsPerRow;
    final aspectRatio = gridSettings.aspectRatioValue;

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount;
        double cardWidth;

        if (fixedPerRow > 0) {
          crossAxisCount = fixedPerRow;
          cardWidth =
              (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
              crossAxisCount;
        } else {
          crossAxisCount = (constraints.maxWidth / (maxCardWidth + spacing))
              .floor()
              .clamp(1, 999);
          cardWidth =
              (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
              crossAxisCount;
          if (cardWidth < minCardWidth && crossAxisCount > 1) {
            crossAxisCount--;
            cardWidth =
                (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                crossAxisCount;
          }
        }

        // Fixed mainAxisExtent (known-good 24ff0a5 baseline). childAspectRatio
        // made every SliverGrid's per-frame relayout far more expensive; with
        // dozens of groups in grouped mode that multiplied into the drag
        // stutter. mainAxisExtent yields identical card sizes but is cheap to
        // relayout.
        final imgHeight = cardWidth / aspectRatio;
        final itemMainAxisExtent = imgHeight + 38 * c;
        final folderMainAxisExtent = cardWidth / aspectRatio * 0.5 + 50 * c;
        final fileMainAxisExtent = cardWidth / aspectRatio * 0.5 + 46 * c;

        final gSubDirs = state.groupedSubDirs;
        final gItems = state.groupedItems;
        final gFiles = state.groupedFiles;

        // --- Three-tier cache ---
        // delegateKey: captures everything affecting cardBuilder closures
        //   (data refs, selection, settings, aspectRatio, c, gifMode).
        //   Excludes layout params (crossAxisCount, spacing, cardWidth).
        // fullKey: delegateKey + crossAxisCount — determines if we can
        //   return the exact same widget (zero work).
        final delegateKey =
            '${identityHashCode(gSubDirs)}|${identityHashCode(gItems)}|'
            '${identityHashCode(gFiles)}|${identityHashCode(items)}|'
            '${identityHashCode(subDirs)}|'
            '${state.selectedPaths.hashCode}|'
            '${state.selectedFolderPaths.hashCode}|'
            '${state.selectedFile?.path ?? ''}|'
            '${identityHashCode(gridSettings)}|'
            '${gridSettings.aspectRatioValue}|'
            '${gridSettings.cardGifMode}|${gridSettings.fileGifMode}|$c|$cardWidth';
        final fullKey = '$delegateKey|$crossAxisCount';

        // Tier 1: full cache hit — return same widget, zero work.
        if (fullKey == _cachedFullKey && _cachedScrollContent != null) {
          return _cachedScrollContent!;
        }

        // Determine whether to reuse cached delegates.
        final delegateHit = delegateKey == _cachedDelegateKey &&
            _cachedFolderDelegate != null;

        SliverChildBuilderDelegate folderDelegate;
        SliverChildBuilderDelegate itemDelegate;
        SliverChildBuilderDelegate fileDelegate;
        List<_FlatEntry<CategoryNode>> gSubDirsUsed;
        List<_FlatEntry<LibraryItem>> gItemsUsed;
        List<_FlatEntry<DirectFile>> gFilesUsed;

        if (delegateHit) {
          // Tier 2: delegate cache hit — reuse flattened delegates, only relayout.
          folderDelegate = _cachedFolderDelegate!;
          itemDelegate = _cachedItemDelegate!;
          fileDelegate = _cachedFileDelegate!;
          gSubDirsUsed = _cachedFolderFlat!;
          gItemsUsed = _cachedItemFlat!;
          gFilesUsed = _cachedFileFlat!;
        } else {
          // Tier 3: full miss — flatten each section's groups into a single
          // delegate (one SliverGrid per section; group labels become full-width
          // header rows rendered by _SectionGridDelegate).
          gSubDirsUsed = _flatten(gSubDirs);
          gItemsUsed = _flatten(gItems);
          gFilesUsed = _flatten(gFiles);

          folderDelegate = _buildFlatDelegate(
            gSubDirsUsed,
            c,
            cs,
            (node) => FolderCard(
              key: GlobalObjectKey(node.path),
              node: node,
              displayWidth: cardWidth,
              isSelected: state.isFolderSelected(node.path),
              onTap: () => state.setSelectedFolder(node),
              onDoubleTap: () => state.setSelectedCategory(node.path),
              onCtrlTap: () => state.toggleFolderSelection(node),
              onShiftTap: () => state.selectFolderRange(node, subDirs),
              onRightClick: (globalPos) =>
                  _showFolderContextMenu(context, node, globalPos),
            ),
          );
          itemDelegate = _buildFlatDelegate(
            gItemsUsed,
            c,
            cs,
            (item) => ItemCard(
              key: GlobalObjectKey(item.path),
              item: item,
              displayWidth: cardWidth,
              displayHeight: imgHeight,
              isSelected: state.isItemSelected(item.path),
              onTap: () => state.setSelectedItem(item),
              onCtrlTap: () => state.toggleItemSelection(item),
              onShiftTap: () => state.selectRange(item, items),
              onDoubleTap: () {
                final type = item.info.type.toLowerCase();
                if (type == 'video' || type == 'anime') {
                  widget.onOpenVideoPlayer(item);
                } else if (type == 'voice' || type == 'music') {
                  widget.onOpenAudioPlayer(item);
                } else if (type == 'comic' || type == 'picture') {
                  widget.onOpenComicReader(item);
                } else if (type == 'novel' || type == 'book') {
                  widget.onOpenEbookReader(item);
                }
              },
              onRightClick: (globalPos) =>
                  _showContextMenu(context, item, globalPos),
              gifMode: gridSettings.cardGifMode,
            ),
          );
          fileDelegate = _buildFlatDelegate(
            gFilesUsed,
            c,
            cs,
            (file) => FileCard(
              key: GlobalObjectKey(file.path),
              file: file,
              displayWidth: cardWidth,
              isSelected: state.selectedFile?.path == file.path,
              onTap: () => state.setSelectedFile(file),
              onDoubleTap: () => _openFile(file.path),
              onRightClick: (globalPos) =>
                  _showFileContextMenu(context, file, globalPos),
            ),
          );

          _cachedFolderDelegate = folderDelegate;
          _cachedItemDelegate = itemDelegate;
          _cachedFileDelegate = fileDelegate;
          _cachedFolderFlat = gSubDirsUsed;
          _cachedItemFlat = gItemsUsed;
          _cachedFileFlat = gFilesUsed;
          _cachedDelegateKey = delegateKey;
        }

        // Build slivers list using ONE SliverGrid per section. The grid itself
        // renders full-width group-header rows via _SectionGridDelegate, so
        // visual grouping is preserved while SliverGrid count stays ≤3
        // (the per-frame relayout cost no longer multiplies by group count).
        final headerExtent = 16 * c;
        final folderHeaderIndices = _headerIndices(gSubDirsUsed);
        final itemHeaderIndices = _headerIndices(gItemsUsed);
        final fileHeaderIndices = _headerIndices(gFilesUsed);

        final slivers = <Widget>[];
        if (gSubDirsUsed.isNotEmpty) {
          slivers
            ..add(_sectionHeader(Strings.t('folderSection'), c, cs, top: false))
            ..add(
              _groupedGrid(
                folderDelegate,
                crossAxisCount,
                folderMainAxisExtent,
                spacing,
                headerExtent,
                folderHeaderIndices,
              ),
            );
        }
        if (gItemsUsed.isNotEmpty) {
          slivers
            ..add(_sectionHeader(Strings.t('itemSection'), c, cs))
            ..add(
              _groupedGrid(
                itemDelegate,
                crossAxisCount,
                itemMainAxisExtent,
                spacing,
                headerExtent,
                itemHeaderIndices,
              ),
            );
        }
        if (gFilesUsed.isNotEmpty) {
          slivers
            ..add(_sectionHeader(Strings.t('fileSection'), c, cs))
            ..add(
              _groupedGrid(
                fileDelegate,
                crossAxisCount,
                fileMainAxisExtent,
                spacing,
                headerExtent,
                fileHeaderIndices,
              ),
            );
        }

        _cachedScrollContent = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => state.clearSelection(),
          child: SmoothScroll(
            builder: (context, controller, physics) => CustomScrollView(
              controller: controller,
              physics: physics,
              // 不显式设置 cacheExtent，使用默认(≈0)：分组模式网格已被拆成
              // 数十个稀疏 SliverGrid，扩大缓存窗口会让视口边界跨越多分组，
              // 面板重排时边界附近的 GifImage 反复挂载/卸载造成掉帧。
              // 屏幕外动图的 CPU 限流已由 GifImage 的 TickerMode 冻结承担，
              // 无需再用 cacheExtent 限流。
              slivers: slivers,
            ),
          ),
        );
        _cachedFullKey = fullKey;

        return _cachedScrollContent!;
      },
    );
  }

  Widget _sectionHeader(
    String title,
    double c,
    ColorScheme cs, {
    bool top = true,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(
          top: top ? 8 * c : 0,
          bottom: 4 * c,
          left: 2 * c,
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11 * c,
            fontWeight: FontWeight.normal,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Flattens a section's groups into a single list: for each non-empty group
  /// first a [header] entry (the group label), then its card entries. Group and
  /// intra-group order are preserved so one SliverGrid lays everything out
  /// contiguously with clear per-group header rows.
  List<_FlatEntry<T>> _flatten<T>(List<GroupedEntries<T>> groups) {
    final out = <_FlatEntry<T>>[];
    for (final group in groups) {
      if (group.entries.isEmpty) continue;
      if (group.groupLabel.isNotEmpty) {
        out.add(_FlatEntry.header(group.groupLabel));
      }
      for (final entry in group.entries) {
        out.add(_FlatEntry.card(entry));
      }
    }
    return out;
  }

  /// 收集扁平列表中所有分组标题项的下标，供 [_SectionGridDelegate] 排版整行标题。
  Set<int> _headerIndices<T>(List<_FlatEntry<T>> flat) =>
      {for (var i = 0; i < flat.length; i++) if (flat[i].isHeader) i};

  /// Builds ONE SliverChildBuilderDelegate spanning the whole section. Cards
  /// are matched by their GlobalObjectKey so elements are reused across
  /// rebuilds; group-label entries render as full-width header rows.
  SliverChildBuilderDelegate _buildFlatDelegate<T>(
    List<_FlatEntry<T>> flat,
    double c,
    ColorScheme cs,
    Widget Function(T) cardBuilder,
  ) {
    return SliverChildBuilderDelegate(
      (context, index) {
        final fe = flat[index];
        if (fe.isHeader) return _groupHeader(fe.headerLabel!, c, cs);
        return cardBuilder(fe.entry as T);
      },
      childCount: flat.length,
    );
  }

  /// Wraps a section's (single) delegate in a SliverGrid that renders full-width
  /// group header rows via [_SectionGridDelegate]. Reusing the same delegate
  /// instance means Flutter skips performRebuild — only performLayout runs.
  SliverGrid _groupedGrid(
    SliverChildBuilderDelegate delegate,
    int crossAxisCount,
    double mainAxisExtent,
    double spacing,
    double headerExtent,
    Set<int> headerIndices,
  ) {
    return SliverGrid(
      gridDelegate: _SectionGridDelegate(
        crossAxisCount: crossAxisCount,
        mainAxisExtent: mainAxisExtent,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        headerExtent: headerExtent,
        headerIndices: headerIndices,
        childCount: delegate.childCount ?? 0,
      ),
      delegate: delegate,
    );
  }

  /// 分组标题：占满整行的一行小标题（与原每分组单独 SliverGrid 前的标题一致）。
  Widget _groupHeader(String label, double c, ColorScheme cs) {
    return SizedBox(
      height: 16 * c,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(left: 2 * c),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10 * c,
              fontWeight: FontWeight.normal,
              color: cs.onSurfaceVariant.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }

  void _showFolderContextMenu(
    BuildContext context,
    CategoryNode node,
    Offset globalPos,
  ) {
    final c = CompactLevel.of(context);
    state.selectFolderForContextMenu(node);
    final selectedFolders = state.selectedFolders;
    final isBatch = selectedFolders.length > 1;

    final position = RelativeRect.fromLTRB(
      globalPos.dx,
      globalPos.dy,
      globalPos.dx + 1,
      globalPos.dy + 1,
    );
    showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(minWidth: 150 * c),
      items: [
        PopupMenuItem(
          value: 'edit',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.edit, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(
                isBatch
                    ? Strings.tn('batchEditN', {
                        'n': '${selectedFolders.length}',
                      })
                    : Strings.t('edit'),
                style: TextStyle(fontSize: 11 * c),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'locate',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.location_searching, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(Strings.t('locateHere'), style: TextStyle(fontSize: 11 * c)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'enter',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(
                Strings.t('enterFolder'),
                style: TextStyle(fontSize: 11 * c),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open_folder',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(
                Strings.t('openInExplorer'),
                style: TextStyle(fontSize: 11 * c),
              ),
            ],
          ),
        ),
        ..._buildScriptMenuItems(context),
      ],
    ).then((value) {
      if (value == null) return;
      if (value.startsWith('script:')) {
        final scriptId = value.substring(7);
        final script = scriptService.scripts
            .where((s) => s.id == scriptId)
            .firstOrNull;
        if (script != null) {
          _runScript(
            context,
            script,
            selectedFolders.map((f) => f.path).toList(),
          );
        }
        return;
      }
      switch (value) {
        case 'edit':
          if (isBatch) {
            onFolderBatchEditRequest(selectedFolders);
          } else {
            onFolderEditRequest(node);
          }
        case 'locate':
          _locateFolder(node.path);
        case 'enter':
          state.setSelectedCategory(node.path);
        case 'open_folder':
          _openInExplorer(node.path);
      }
    });
  }

  void _showContextMenu(
    BuildContext context,
    LibraryItem tappedItem,
    Offset globalPos,
  ) {
    final c = CompactLevel.of(context);
    state.selectItemForContextMenu(tappedItem);
    final selectedItems = state.selectedItems;
    final isBatch = selectedItems.length > 1;

    final position = RelativeRect.fromLTRB(
      globalPos.dx,
      globalPos.dy,
      globalPos.dx + 1,
      globalPos.dy + 1,
    );

    showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(minWidth: 150 * c),
      items: [
        PopupMenuItem(
          value: 'edit',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.edit, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(
                isBatch
                    ? Strings.tn('batchEditN', {'n': '${selectedItems.length}'})
                    : Strings.t('edit'),
                style: TextStyle(fontSize: 11 * c),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'locate',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.location_searching, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(Strings.t('locateHere'), style: TextStyle(fontSize: 11 * c)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open_folder',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(
                Strings.t('openInExplorer'),
                style: TextStyle(fontSize: 11 * c),
              ),
            ],
          ),
        ),
        ..._buildScriptMenuItems(context),
      ],
    ).then((value) {
      if (value == null) return;
      if (value.startsWith('script:')) {
        final scriptId = value.substring(7);
        final script = scriptService.scripts
            .where((s) => s.id == scriptId)
            .firstOrNull;
        if (script != null) {
          _runScript(
            context,
            script,
            selectedItems.map((i) => i.path).toList(),
          );
        }
        return;
      }
      switch (value) {
        case 'edit':
          onEditRequest(selectedItems, isBatch);
        case 'locate':
          _locateItem(tappedItem);
        case 'open_folder':
          _openInExplorer(tappedItem.path);
      }
    });
  }

  void _locateFolder(String folderPath) {
    state.locateInTree(folderPath);
  }

  void _locateItem(LibraryItem item) {
    state.locateInTree(item.categoryPath);
    // 切换分类后，下一帧将对应项目滚动到可见区域
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = GlobalObjectKey(item.path);
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
        );
      }
    });
  }

  void _openInExplorer(String path) {
    Process.run('explorer', [path]);
  }

  void _openFile(String path) {
    Process.run('cmd', ['/c', 'start', '', path]);
  }

  void _showFileContextMenu(
    BuildContext context,
    DirectFile file,
    Offset globalPos,
  ) {
    final c = CompactLevel.of(context);
    final position = RelativeRect.fromLTRB(
      globalPos.dx,
      globalPos.dy,
      globalPos.dx + 1,
      globalPos.dy + 1,
    );
    showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(minWidth: 150 * c),
      items: [
        PopupMenuItem(
          value: 'open',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(
                Strings.t('openWithDefault'),
                style: TextStyle(fontSize: 11 * c),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open_as',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.apps, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(Strings.t('openAs'), style: TextStyle(fontSize: 11 * c)),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'rename',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.drive_file_rename_outline, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(Strings.t('rename'), style: TextStyle(fontSize: 11 * c)),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'locate',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(
                Strings.t('openInExplorer'),
                style: TextStyle(fontSize: 11 * c),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'properties',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(Strings.t('properties'), style: TextStyle(fontSize: 11 * c)),
            ],
          ),
        ),
        ..._buildScriptMenuItems(context),
      ],
    ).then((value) async {
      if (value == null) return;
      if (value.startsWith('script:')) {
        final scriptId = value.substring(7);
        final script = scriptService.scripts
            .where((s) => s.id == scriptId)
            .firstOrNull;
        if (script != null) {
          _runScript(context, script, [file.path]);
        }
        return;
      }
      switch (value) {
        case 'open':
          _openFile(file.path);
        case 'open_as':
          final record = await showDialog<ExeRecord>(
            context: context,
            builder: (_) => const ExePickerDialog(),
          );
          if (record != null) {
            Process.run(record.path, [file.path]);
          }
        case 'rename':
          _showRenameDialog(context, file);
        case 'locate':
          Process.run('explorer', ['/select,', file.path]);
        case 'properties':
          showDialog(
            context: context,
            builder: (_) => FilePropertiesDialog(file: File(file.path)),
          );
      }
    });
  }

  List<PopupMenuEntry<String>> _buildScriptMenuItems(BuildContext context) {
    final c = CompactLevel.of(context);
    final scripts = scriptService.scripts.where((s) => s.enabled).toList();
    if (scripts.isEmpty) return const [];
    return [
      PopupMenuDivider(),
      for (final script in scripts)
        PopupMenuItem<String>(
          value: 'script:${script.id}',
          height: 28 * c,
          child: Tooltip(
            waitDuration: Duration.zero,
            message: scriptService.readDescriptionSync(script),
            child: Row(
              children: [
                Icon(Icons.code, size: 13 * c),
                SizedBox(width: 6 * c),
                Expanded(
                  child: Text(
                    script.name,
                    style: TextStyle(fontSize: 11 * c),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  void _runScript(
    BuildContext context,
    ScriptEntry script,
    List<String> paths,
  ) {
    if (script.execMode == ScriptExecMode.terminal) {
      scriptService.executeScriptTerminal(script, paths);
    } else {
      final future = script.execMode == ScriptExecMode.silent
          ? scriptService.executeScriptSilent(script, paths)
          : scriptService.executeScript(script, paths);
      future.then((result) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (_) => ScriptResultDialog(result: result),
          );
        }
      });
    }
  }

  void _showRenameDialog(BuildContext context, DirectFile file) {
    final currentName = file.name;
    final dotIndex = currentName.lastIndexOf('.');
    final nameWithoutExt = dotIndex > 0
        ? currentName.substring(0, dotIndex)
        : currentName;

    final ctrl = TextEditingController(text: currentName);
    ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: nameWithoutExt.length,
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Strings.t('rename'), style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: Strings.t('newFileName'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onSubmitted: (_) => _doRename(dialogContext, file, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(Strings.t('cancel')),
          ),
          FilledButton(
            onPressed: () => _doRename(dialogContext, file, ctrl.text.trim()),
            child: Text(Strings.t('rename')),
          ),
        ],
      ),
    );
  }

  Future<void> _doRename(
    BuildContext dialogContext,
    DirectFile file,
    String newName,
  ) async {
    if (newName.isEmpty) return;
    Navigator.pop(dialogContext);

    final error = await state.renameFile(file.path, newName);
    if (error != null && dialogContext.mounted) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(
          content: Text(
            Strings.tn('renameFailed', {'error': error.toString()}),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// 为中间网格区域提供拖入高亮圆角边框与文件路径读取。
/// 由于 desktop_drop 的 DropTarget 为全局监听，嵌套时内外层都会在命中区域触发，
/// 因此通过 [excludeKey] 排除内层（如底部文件面板）的命中矩形，
/// 拖入底部面板时本层不再重复触发复制。
class _DropHighlight extends StatefulWidget {
  final Widget child;
  final void Function(List<String> paths)? onFilesDropped;
  /// 高亮边框底部需排除的高度（如底部文件面板占据的区域）。
  final double bottomInset;
  /// 需排除其命中区域的内层 widget key（拖入该区域时本层不触发）。
  final GlobalKey? excludeKey;

  const _DropHighlight({
    required this.child,
    this.onFilesDropped,
    this.bottomInset = 0,
    this.excludeKey,
  });

  @override
  State<_DropHighlight> createState() => _DropHighlightState();
}

class _DropHighlightState extends State<_DropHighlight> {
  bool _isDragOver = false;

  /// 若拖入点落在 [excludeKey] 对应的矩形内（如底部文件面板），说明由内层
  /// DropTarget 处理，本层应跳过：既不重复复制，也不让本层高亮跟着亮起。
  bool _isExcluded(Offset globalPosition) {
    final key = widget.excludeKey;
    final renderBox =
        key?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return false;
    final rect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    return rect.contains(globalPosition);
  }

  /// 仅在状态变化时触发重建，避免 onDragUpdated 每帧无谓 setState。
  void _setOver(bool value) {
    if (_isDragOver != value) setState(() => _isDragOver = value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);
    return DropTarget(
      // 进入/移动时若落在被排除区域（底部面板）则不点亮本层高亮，
      // 让“拖到哪个区域哪个区域才高亮”的语义成立。
      onDragEntered: (details) =>
          _setOver(!_isExcluded(details.globalPosition)),
      onDragUpdated: (details) =>
          _setOver(!_isExcluded(details.globalPosition)),
      onDragExited: (_) => _setOver(false),
      onDragDone: (detail) {
        _setOver(false);
        if (_isExcluded(detail.globalPosition)) return;
        final paths = detail.files.map((f) => f.path).toList();
        if (paths.isNotEmpty) {
          widget.onFilesDropped?.call(paths);
        }
      },
      child: Stack(
        children: [
          widget.child,
          if (_isDragOver)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: widget.bottomInset,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: cs.primary, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
