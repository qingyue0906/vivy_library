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
  final List<double>? perChildExtents;

  const _SectionGridDelegate({
    required this.crossAxisCount,
    required this.mainAxisExtent,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.headerExtent,
    required this.headerIndices,
    required this.childCount,
    this.perChildExtents,
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
      perChildExtents: perChildExtents,
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
        old.childCount != childCount ||
        !_sameDoubleList(old.perChildExtents, perChildExtents);
  }
}

bool _sameDoubleList(List<double>? a, List<double>? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 0.01) return false;
  }
  return true;
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
    this.perChildExtents,
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
  final List<double>? perChildExtents;

  late final double _tileWidth;
  late final List<double> _starts;
  late final List<double> _extents;
  late final List<double> _crossOffsets;
  late final double _maxScroll;
  late final List<List<int>> _colItems;

  void _compute() {
    _tileWidth =
        (crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1)) /
        crossAxisCount;
    _starts = List<double>.filled(childCount, 0);
    _extents = List<double>.filled(childCount, 0);
    _crossOffsets = List<double>.filled(childCount, 0);
    _colItems = List.generate(crossAxisCount, (_) => <int>[]);
    final colHeights = List<double>.filled(crossAxisCount, 0);
    final colStride = _tileWidth + crossAxisSpacing;

    for (var i = 0; i < childCount; i++) {
      if (headerIndices.contains(i)) {
        // 分组标题占满整行：先让所有列对齐到当前最高列，再放置标题，
        // 之后所有列从该高度继续，保证标题下方的卡片不与上方残留错位。
        final bottom = colHeights.reduce((a, b) => a > b ? a : b);
        _starts[i] = bottom;
        _extents[i] = headerExtent;
        _crossOffsets[i] = 0;
        final reset = bottom + headerExtent + mainAxisSpacing;
        for (var c = 0; c < crossAxisCount; c++) {
          colHeights[c] = reset;
        }
      } else {
        // 最短列贪心（Pinterest / SliverMasonryGrid 同款）：每张卡片放入
        // 当前最矮的一列并更新其高度；等高卡片时退化为普通按行网格。
        var col = 0;
        for (var c = 1; c < crossAxisCount; c++) {
          if (colHeights[c] < colHeights[col]) col = c;
        }
        final extent =
            perChildExtents != null ? perChildExtents![i] : mainAxisExtent;
        _starts[i] = colHeights[col];
        _extents[i] = extent;
        _crossOffsets[i] = col * colStride;
        colHeights[col] += extent + mainAxisSpacing;
        _colItems[col].add(i);
      }
    }
    final maxH = childCount > 0
        ? colHeights.reduce((a, b) => a > b ? a : b)
        : 0.0;
    // 去掉尾部多余的一格 mainAxisSpacing（最后一行卡片后无需额外间距）。
    _maxScroll = maxH - (childCount > 0 ? mainAxisSpacing : 0);
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

  /// 单列内二分：首个 end > [scrollOffset] 的全局索引；整列都已滚过时返回该列
  /// 最后一个（对全局最小可见索引无贡献）。
  int _colFirstVisible(List<int> colItems, double scrollOffset) {
    if (colItems.isEmpty) return childCount;
    var lo = 0, hi = colItems.length - 1, ans = colItems.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final gi = colItems[mid];
      if (_starts[gi] + _extents[gi] > scrollOffset) {
        ans = mid;
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }
    return colItems[ans];
  }

  /// 单列内二分：末个 start ≤ [scrollOffset] 的全局索引；整列都未进入视口时
  /// 返回该列第一个（对全局最大可见索引无贡献）。
  int _colLastVisible(List<int> colItems, double scrollOffset) {
    if (colItems.isEmpty) return -1;
    var lo = 0, hi = colItems.length - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final gi = colItems[mid];
      if (_starts[gi] <= scrollOffset) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return colItems[ans];
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    if (childCount == 0) return 0;
    var min = childCount;
    for (var col = 0; col < crossAxisCount; col++) {
      final gi = _colFirstVisible(_colItems[col], scrollOffset);
      if (gi < min) min = gi;
    }
    return min < childCount ? min : childCount - 1;
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    if (childCount == 0) return 0;
    var max = -1;
    for (var col = 0; col < crossAxisCount; col++) {
      final gi = _colLastVisible(_colItems[col], scrollOffset);
      if (gi > max) max = gi;
    }
    return max >= 0 ? max : 0;
  }
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

  /// 自适应模式下预览图的真实宽高比缓存（key=预览图路径）。
  /// 尺寸未知时回退默认 aspectRatio，加载完成后触发重排实现砖石布局。
  final Map<String, double> _previewAspectRatios = {};
  final Set<String> _resolvingAspects = {};

  /// 待解析宽高比的预览图路径集合。build 阶段只登记、不解析，待本帧 build
  /// 结束后再解析，避免 image.resolve().addListener() 在 build 期同步触发
  /// Image 控件 setState 而抛出断言。
  final Set<String> _pendingAspectPaths = {};
  bool _aspectResolveScheduled = false;

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
        modalDropActive: state.modalDropActive,
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
    if (gridSettings.displayMode == GridDisplayMode.list) {
      return _buildList(context, c, cs);
    }
    final minCardWidth = gridSettings.minCardWidth;
    final maxCardWidth = gridSettings.maxCardWidth;
    final spacing = 8.0 * c;
    final fixedPerRow = gridSettings.itemsPerRow;
    final aspectRatio = gridSettings.aspectRatioValue;
    final mode = gridSettings.displayMode;
    final badges = gridSettings.badges;
    final adaptive = mode == GridDisplayMode.adaptive;
    final hasCaption =
        mode != GridDisplayMode.compact && mode != GridDisplayMode.cover;

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

        final imgHeight = cardWidth / aspectRatio;
        final itemMainAxisExtent =
            hasCaption ? (imgHeight + 38 * c) : imgHeight;
        final folderMainAxisExtent = cardWidth / aspectRatio * 0.5 + 50 * c;
        final fileMainAxisExtent = cardWidth / aspectRatio * 0.5 + 46 * c;

        final gSubDirs = state.groupedSubDirs;
        final gItems = state.groupedItems;
        final gFiles = state.groupedFiles;

        // 自适应模式每次都重建（预览图尺寸缓存会触发重排），不走三级缓存。
        final cacheEnabled = !adaptive;
        // delegateKey: captures everything affecting cardBuilder closures
        //   (data refs, selection, settings, aspectRatio, c, gifMode,
        //   displayMode, badges). Excludes layout params.
        final delegateKey =
            '${identityHashCode(gSubDirs)}|${identityHashCode(gItems)}|'
            '${identityHashCode(gFiles)}|${identityHashCode(items)}|'
            '${identityHashCode(subDirs)}|'
            '${state.selectedPaths.hashCode}|'
            '${state.selectedFolderPaths.hashCode}|'
            '${state.selectedFile?.path ?? ''}|'
            '${identityHashCode(gridSettings)}|'
            '${gridSettings.aspectRatioValue}|'
            '${gridSettings.cardGifMode}|${gridSettings.fileGifMode}|'
            '$mode|${badges.enabled.map((e) => e.name).join(',')}|$c|$cardWidth';
        final fullKey = '$delegateKey|$crossAxisCount';

        if (cacheEnabled) {
          // Tier 1: full cache hit — return same widget, zero work.
          if (fullKey == _cachedFullKey && _cachedScrollContent != null) {
            return _cachedScrollContent!;
          }
        }

        // Determine whether to reuse cached delegates.
        final delegateHit = cacheEnabled &&
            delegateKey == _cachedDelegateKey &&
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
            (node) => _folderCard(node, cardWidth),
          );
          itemDelegate = _buildFlatDelegate(
            gItemsUsed,
            c,
            cs,
            (item) {
              final aspect = adaptive
                  ? (_previewAspectRatios[item.previewPath] ?? aspectRatio)
                  : aspectRatio;
              final ih = cardWidth / aspect;
              if (adaptive) _requestAspectResolution(item.previewPath);
              return _itemCard(item, cardWidth, ih, mode, badges);
            },
          );
          fileDelegate = _buildFlatDelegate(
            gFilesUsed,
            c,
            cs,
            (file) => _fileCard(file, cardWidth),
          );

          _cachedFolderDelegate = folderDelegate;
          _cachedItemDelegate = itemDelegate;
          _cachedFileDelegate = fileDelegate;
          _cachedFolderFlat = gSubDirsUsed;
          _cachedItemFlat = gItemsUsed;
          _cachedFileFlat = gFilesUsed;
          _cachedDelegateKey = delegateKey;
        }

        // 自适应模式：提前为所有 item 解析预览图真实宽高比，使屏外卡片也能
        // 拿到真实比例（而非默认比例），首屏即呈现完整砖石，而非只有可见行参差。
        if (adaptive) {
          for (final fe in gItemsUsed) {
            if (!fe.isHeader) {
              _requestAspectResolution((fe.entry as LibraryItem).previewPath);
            }
          }
        }

        final headerExtent = 16 * c;

        // 自适应下为每张 item 卡片计算独立高度（砖石布局）。
        List<double>? itemPerExtents;
        if (adaptive && gItemsUsed.isNotEmpty) {
          itemPerExtents = [
            for (final fe in gItemsUsed)
              fe.isHeader
                  ? headerExtent
                  : (() {
                      final item = fe.entry as LibraryItem;
                      final aspect =
                          _previewAspectRatios[item.previewPath] ?? aspectRatio;
                      return cardWidth / aspect + (hasCaption ? 38 * c : 0);
                    })(),
          ];
        }

        // Build slivers list using ONE SliverGrid per section. The grid itself
        // renders full-width group-header rows via _SectionGridDelegate, so
        // visual grouping is preserved while SliverGrid count stays ≤3
        // (the per-frame relayout cost no longer multiplies by group count).
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
                perChildExtents: itemPerExtents,
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

        final content = GestureDetector(
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
        if (cacheEnabled) {
          _cachedScrollContent = content;
          _cachedFullKey = fullKey;
        }
        return content;
      },
    );
  }

  // ===== 列表模式 =====

  Widget _buildList(BuildContext context, double c, ColorScheme cs) {
    final gSubDirs = state.groupedSubDirs;
    final gItems = state.groupedItems;
    final gFiles = state.groupedFiles;
    final thumb = 56 * c;
    final slivers = <Widget>[];
    if (gSubDirs.isNotEmpty) {
      slivers.add(_sectionHeader(Strings.t('folderSection'), c, cs));
      slivers.add(
        _listSection(gSubDirs, c, cs, (node) => _folderCard(node, thumb)),
      );
    }
    if (gItems.isNotEmpty) {
      slivers.add(_sectionHeader(Strings.t('itemSection'), c, cs));
      slivers.add(
        _listSection(
          gItems,
          c,
          cs,
          (item) => _itemCard(
            item,
            thumb,
            thumb,
            GridDisplayMode.list,
            gridSettings.badges,
          ),
        ),
      );
    }
    if (gFiles.isNotEmpty) {
      slivers.add(_sectionHeader(Strings.t('fileSection'), c, cs));
      slivers.add(
        _listSection(gFiles, c, cs, (file) => _fileCard(file, thumb)),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => state.clearSelection(),
      child: SmoothScroll(
        builder: (context, controller, physics) => CustomScrollView(
          controller: controller,
          physics: physics,
          slivers: slivers,
        ),
      ),
    );
  }

  SliverList _listSection<T>(
    List<GroupedEntries<T>> groups,
    double c,
    ColorScheme cs,
    Widget Function(T) cardBuilder,
  ) {
    final flat = _flatten(groups);
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final fe = flat[index];
          if (fe.isHeader) return _groupHeader(fe.headerLabel!, c, cs);
          return cardBuilder(fe.entry as T);
        },
        childCount: flat.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
      ),
    );
  }

  Widget _itemCard(
    LibraryItem item,
    double cardWidth,
    double imgHeight,
    GridDisplayMode mode,
    GridBadgeFlags badges,
  ) {
    return ItemCard(
      key: GlobalObjectKey(item.path),
      item: item,
      effectiveInfo: state.effectiveInfo(item),
      displayWidth: cardWidth,
      displayHeight: imgHeight,
      displayMode: mode,
      badges: badges,
      isSelected: state.isItemSelected(item.path),
      onTap: () => state.setSelectedItem(item),
      onCtrlTap: () => state.toggleItemSelection(item),
      onShiftTap: () => state.selectRange(item, items),
      onDoubleTap: () {
        final type = state.effectiveInfo(item).type.toLowerCase();
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
      onRightClick: (globalPos) => _showContextMenu(context, item, globalPos),
      gifMode: gridSettings.cardGifMode,
    );
  }

  Widget _folderCard(CategoryNode node, double cardWidth) => FolderCard(
        key: GlobalObjectKey(node.path),
        node: node,
        displayWidth: cardWidth,
        displayMode: gridSettings.displayMode,
        isSelected: state.isFolderSelected(node.path),
        onTap: () => state.setSelectedFolder(node),
        onDoubleTap: () => state.setSelectedCategory(node.path),
        onCtrlTap: () => state.toggleFolderSelection(node),
        onShiftTap: () => state.selectFolderRange(node, subDirs),
        onRightClick: (globalPos) =>
            _showFolderContextMenu(context, node, globalPos),
      );

  Widget _fileCard(DirectFile file, double cardWidth) => FileCard(
        key: GlobalObjectKey(file.path),
        file: file,
        displayWidth: cardWidth,
        displayMode: gridSettings.displayMode,
        isSelected: state.selectedFile?.path == file.path,
        onTap: () => state.setSelectedFile(file),
        onDoubleTap: () => _openFile(file.path),
        onRightClick: (globalPos) =>
            _showFileContextMenu(context, file, globalPos),
      );

  /// 自适应模式：异步解析预览图真实宽高比，加载完成后触发重排实现砖石布局。
  void _maybeResolveAspect(String? path) {
    if (path == null ||
        _previewAspectRatios.containsKey(path) ||
        _resolvingAspects.contains(path)) {
      return;
    }
    _resolvingAspects.add(path);
    final image = FileImage(File(path));
    image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener(
        (info, _) {
          _resolvingAspects.remove(path);
          final w = info.image.width.toDouble();
          final h = info.image.height.toDouble();
          if (w > 0 && h > 0 && mounted) {
            setState(() => _previewAspectRatios[path] = w / h);
          }
        },
        onError: (Object error, StackTrace? stack) {
          _resolvingAspects.remove(path);
        },
      ),
    );
  }

  /// build 阶段调用：登记需要解析宽高比的预览图，待本帧 build 结束（post-frame）
  /// 后再真正解析，从而避免在 LayoutBuilder/Image 构建过程中同步触发 setState。
  void _requestAspectResolution(String? path) {
    if (path == null) return;
    if (_previewAspectRatios.containsKey(path) ||
        _resolvingAspects.contains(path)) {
      return;
    }
    if (_pendingAspectPaths.add(path) && !_aspectResolveScheduled) {
      _aspectResolveScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _aspectResolveScheduled = false;
        if (!mounted) return;
        final paths = _pendingAspectPaths.toList();
        _pendingAspectPaths.clear();
        for (final p in paths) {
          _maybeResolveAspect(p);
        }
      });
    }
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
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
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
    Set<int> headerIndices, {
    List<double>? perChildExtents,
  }) {
    return SliverGrid(
      gridDelegate: _SectionGridDelegate(
        crossAxisCount: crossAxisCount,
        mainAxisExtent: mainAxisExtent,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        headerExtent: headerExtent,
        headerIndices: headerIndices,
        childCount: delegate.childCount ?? 0,
        perChildExtents: perChildExtents,
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
  /// 是否有带自身 DropTarget 的模态对话框（如创建项目对话框）打开。
  /// 打开时本层不显示高亮、也不接收拖放，避免与模态层叠加误亮/误复制。
  final bool modalDropActive;

  const _DropHighlight({
    required this.child,
    this.onFilesDropped,
    this.bottomInset = 0,
    this.excludeKey,
    this.modalDropActive = false,
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
      onDragEntered: (details) {
        if (widget.modalDropActive) {
          _setOver(false);
          return;
        }
        _setOver(!_isExcluded(details.globalPosition));
      },
      onDragUpdated: (details) {
        if (widget.modalDropActive) {
          _setOver(false);
          return;
        }
        _setOver(!_isExcluded(details.globalPosition));
      },
      onDragExited: (_) => _setOver(false),
      onDragDone: (detail) {
        _setOver(false);
        if (widget.modalDropActive) return;
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
