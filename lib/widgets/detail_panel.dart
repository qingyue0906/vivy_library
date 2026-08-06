import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../models/item_info.dart';
import '../models/library_item.dart';
import '../models/category_node.dart';
import '../models/direct_file.dart';
import '../models/goto_entry.dart';
import '../providers/library_state.dart';
import '../services/library_scanner.dart' show previewExtensions;
import '../services/script_service.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import 'compact_level.dart';
import 'drag_select.dart';
import 'file_browser_panel.dart';
import 'smooth_scroll.dart';

/// 详情面板的四个标签页。
enum _DetailTab { overview, metadata, files, related }

class DetailPanel extends StatefulWidget {
  final LibraryItem? item;
  final ItemInfo? effectiveInfo; // 有效 info（含父文件夹继承 + 硬编码保底）
  final CategoryNode? folder;
  final DirectFile? file;
  final double backgroundOpacity;
  final void Function(GotoEntry entry)? onGotoTap;
  final void Function(String query)? onSearchByQuery;
  final bool showBottomFilePanel; // 关闭时文件浏览区嵌入"文件"标签页底部
  final bool keepDetailTabOnSelection; // 切换选中时保持当前标签页
  final ValueListenable<bool>? dragSelect; // 全局拖选会话（设置开启时传入）
  final LibraryState? state;
  final ScriptService? scriptService;
  final GifDisplayMode gifMode;
  final void Function(LibraryItem item, {String? startPath})? onOpenVideoPlayer;
  final void Function(LibraryItem item, {String? startPath})? onOpenAudioPlayer;
  final void Function(LibraryItem item, {String? startPath})? onOpenComicReader;
  final void Function(LibraryItem item, {String? startPath})? onOpenEbookReader;
  final void Function(LibraryItem item, {String? startPath})? onOpenEdgeHtml;
  final void Function(LibraryItem item, {String? startPath})? onOpenMarkdown;

  const DetailPanel({
    super.key,
    this.item,
    this.effectiveInfo,
    this.folder,
    this.file,
    this.backgroundOpacity = 1.0,
    this.onGotoTap,
    this.onSearchByQuery,
    this.showBottomFilePanel = true,
    this.keepDetailTabOnSelection = false,
    this.dragSelect,
    this.state,
    this.scriptService,
    this.gifMode = GifDisplayMode.hover,
    this.onOpenVideoPlayer,
    this.onOpenAudioPlayer,
    this.onOpenComicReader,
    this.onOpenEbookReader,
    this.onOpenEdgeHtml,
    this.onOpenMarkdown,
  });

  @override
  State<DetailPanel> createState() => _DetailPanelState();
}

class _DetailPanelState extends State<DetailPanel> {
  /// 跨选中切换保留的标签页（按枚举存储，跨类型切换自动兜底）。
  _DetailTab? _lastTab;

  void _onTabSelected(_DetailTab tab) {
    _lastTab = tab;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = CompactLevel.of(context);
    // 以选择对象身份作为 key，切换选中项时重建内部 TabController，
    // 避免标签页数量变化导致的断言错误。
    // showBottomFilePanel 也纳入 key：设置切换该开关后标签页数量变化，
    // 需要重建以匹配新的 TabController 长度。
    final selectionKey = Object.hash(widget.item?.path, widget.folder?.path,
        widget.file?.path, widget.showBottomFilePanel);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: widget.backgroundOpacity),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
        borderRadius: BorderRadius.circular(8 * c),
      ),
      child: _DetailPanelBody(
        key: ValueKey(selectionKey),
        item: widget.item,
        effectiveInfo: widget.effectiveInfo,
        folder: widget.folder,
        file: widget.file,
        onGotoTap: widget.onGotoTap,
        onSearchByQuery: widget.onSearchByQuery,
        keepDetailTab: widget.keepDetailTabOnSelection,
        lastTab: _lastTab,
        onTabSelected: _onTabSelected,
        dragSelect: widget.dragSelect,
        showBottomFilePanel: widget.showBottomFilePanel,
        backgroundOpacity: widget.backgroundOpacity,
        state: widget.state,
        scriptService: widget.scriptService,
        gifMode: widget.gifMode,
        onOpenVideoPlayer: widget.onOpenVideoPlayer,
        onOpenAudioPlayer: widget.onOpenAudioPlayer,
        onOpenComicReader: widget.onOpenComicReader,
        onOpenEbookReader: widget.onOpenEbookReader,
        onOpenEdgeHtml: widget.onOpenEdgeHtml,
        onOpenMarkdown: widget.onOpenMarkdown,
      ),
    );
  }
}

class _DetailPanelBody extends StatefulWidget {
  final LibraryItem? item;
  final ItemInfo? effectiveInfo;
  final CategoryNode? folder;
  final DirectFile? file;
  final void Function(GotoEntry entry)? onGotoTap;
  final void Function(String query)? onSearchByQuery;
  final bool keepDetailTab;
  final _DetailTab? lastTab;
  final void Function(_DetailTab tab)? onTabSelected;
  final ValueListenable<bool>? dragSelect;
  final bool showBottomFilePanel;
  final double backgroundOpacity;
  final LibraryState? state;
  final ScriptService? scriptService;
  final GifDisplayMode gifMode;
  final void Function(LibraryItem item, {String? startPath})? onOpenVideoPlayer;
  final void Function(LibraryItem item, {String? startPath})? onOpenAudioPlayer;
  final void Function(LibraryItem item, {String? startPath})? onOpenComicReader;
  final void Function(LibraryItem item, {String? startPath})? onOpenEbookReader;
  final void Function(LibraryItem item, {String? startPath})? onOpenEdgeHtml;
  final void Function(LibraryItem item, {String? startPath})? onOpenMarkdown;

  const _DetailPanelBody({
    super.key,
    this.item,
    this.effectiveInfo,
    this.folder,
    this.file,
    this.onGotoTap,
    this.onSearchByQuery,
    this.keepDetailTab = false,
    this.lastTab,
    this.onTabSelected,
    this.dragSelect,
    this.showBottomFilePanel = true,
    this.backgroundOpacity = 1.0,
    this.state,
    this.scriptService,
    this.gifMode = GifDisplayMode.hover,
    this.onOpenVideoPlayer,
    this.onOpenAudioPlayer,
    this.onOpenComicReader,
    this.onOpenEbookReader,
    this.onOpenEdgeHtml,
    this.onOpenMarkdown,
  });

  @override
  State<_DetailPanelBody> createState() => _DetailPanelBodyState();
}

class _DetailPanelBodyState extends State<_DetailPanelBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// 外层整页滚动控制器（由 SmoothScroll 创建，此处仅保存引用
  /// 用于切换标签时回到面板顶部）。
  ScrollController? _outerController;

  bool get _isItem => widget.item != null;
  bool get _isFolder => widget.folder != null;
  bool get _isFile => widget.file != null;

  /// 依据当前选中对象的类型决定要展示哪些标签页。
  /// 底部文件面板开启时 item 无"文件"标签页（文件在底部面板查看）；
  /// 文件夹的"文件"标签页始终移除（信息与元数据重复，无文件浏览区）。
  List<_TabSpec> _tabSpecs() {
    if (_isItem) {
      if (widget.showBottomFilePanel) {
        return const [
          _TabSpec(_DetailTab.overview, 'tabOverview', Icons.dashboard_outlined),
          _TabSpec(_DetailTab.metadata, 'tabMetadata', Icons.data_object_outlined),
          _TabSpec(_DetailTab.related, 'tabRelated', Icons.link_outlined),
        ];
      }
      return const [
        _TabSpec(_DetailTab.overview, 'tabOverview', Icons.dashboard_outlined),
        _TabSpec(_DetailTab.metadata, 'tabMetadata', Icons.data_object_outlined),
        _TabSpec(_DetailTab.files, 'tabFiles', Icons.folder_outlined),
        _TabSpec(_DetailTab.related, 'tabRelated', Icons.link_outlined),
      ];
    }
    if (_isFolder) {
      return const [
        _TabSpec(_DetailTab.overview, 'tabOverview', Icons.dashboard_outlined),
        _TabSpec(_DetailTab.metadata, 'tabMetadata', Icons.data_object_outlined),
      ];
    }
    if (_isFile) {
      return const [
        _TabSpec(_DetailTab.overview, 'tabOverview', Icons.dashboard_outlined),
        _TabSpec(_DetailTab.metadata, 'tabMetadata', Icons.data_object_outlined),
      ];
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    final specs = _tabSpecs();
    // 设置开启时按上次标签页恢复（枚举方式存储，跨类型自动兜底到 0）。
    var initialIndex = 0;
    if (widget.keepDetailTab && widget.lastTab != null) {
      final idx = specs.indexWhere((s) => s.key == widget.lastTab);
      if (idx >= 0) initialIndex = idx;
    }
    _tabController = TabController(
      length: specs.length,
      initialIndex: initialIndex,
      vsync: this,
      animationDuration: const Duration(milliseconds: 180),
    )..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;

    if (!_isItem && !_isFolder && !_isFile) {
      return _buildEmpty(context, c);
    }

    final specs = _tabSpecs();
    final filesTabIndex = specs.indexWhere((s) => s.key == _DetailTab.files);
    final fabVisible = _isItem &&
        !widget.showBottomFilePanel &&
        widget.state != null &&
        widget.scriptService != null &&
        filesTabIndex >= 0 &&
        _tabController.index == filesTabIndex;
    // 整页一体滚动：头部、TabBar、当前标签内容共用一个滚动视图，
    // 滚轮滚动整个预览面板，而非只有标签下方的内容滚动。
    final body = SmoothScroll(
      builder: (context, controller, physics) {
        _outerController = controller;
        return CustomScrollView(
          controller: controller,
          physics: physics,
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(c, cs)),
            SliverToBoxAdapter(child: _buildTabBar(c, cs, specs)),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(12 * c, 4 * c, 12 * c,
                  fabVisible ? 16 * c + 52 : 16 * c),
              sliver: SliverToBoxAdapter(
                child: _tabContent(context, c, cs, specs[_tabController.index].key),
              ),
            ),
          ],
        );
      },
    );
    // 文件标签页的悬浮操作按钮组，固定在面板右下角，不随内容滚动。
    if (!fabVisible) return body;
    return Stack(
      children: [
        body,
        Positioned(
          right: 16 * c,
          bottom: 16 * c,
          child: _buildFloatingButtons(context, c),
        ),
      ],
    );
  }

  Widget _buildTabBar(double c, ColorScheme cs, List<_TabSpec> specs) {
    return TabBar(
      controller: _tabController,
      isScrollable: false,
      dividerHeight: 1,
      dividerColor: cs.outlineVariant.withValues(alpha: 0.6),
      indicatorSize: TabBarIndicatorSize.label,
      indicatorColor: cs.primary,
      labelColor: cs.primary,
      unselectedLabelColor: cs.onSurfaceVariant,
      labelStyle: TextStyle(fontSize: 11 * c, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 11 * c),
      onTap: (i) => _selectTab(specs, i),
      tabs: [
        for (var i = 0; i < specs.length; i++)
          DragSelectItem(
            active: widget.dragSelect,
            onSelect: () => _selectTab(specs, i),
            child: Tab(
              text: Strings.t(specs[i].labelKey),
              height: 38 * c,
              icon: Icon(specs[i].icon, size: 16 * c),
            ),
          ),
      ],
    );
  }

  /// 切换到指定标签页：更新记忆、回到面板顶部。
  /// 点击与拖选共用同一入口。
  void _selectTab(List<_TabSpec> specs, int i) {
    _tabController.animateTo(i);
    widget.onTabSelected?.call(specs[i].key);
    // 切换标签后回到面板顶部，与每页独立滚动时从内容顶部开始的直觉一致
    _outerController?.jumpTo(0);
  }

  // ===== 头部：原比例预览图 + 标题 + 类型/评分/分级 =====

  Widget _buildHeader(double c, ColorScheme cs) {
    final imagePath = _headerImagePath();
    final title = _headerTitle();
    final tint = _headerTint();
    final icon = _headerIcon();
    final hasImage = imagePath != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(12 * c, 12 * c, 12 * c, 6 * c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 预览图按原比例显示：宽 100%、高随宽等比（无高度上限），
          // 图上不叠加任何内容；加载期以最小高度占位避免塌陷
          if (hasImage)
            Container(
              constraints: BoxConstraints(minHeight: 120 * c),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4 * c),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                File(imagePath),
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    _tintedPlaceholder(c, cs, tint, icon),
              ),
            )
          else
            Container(
              height: 132 * c,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tint.withValues(alpha: 0.22),
                    tint.withValues(alpha: 0.07),
                  ],
                ),
                borderRadius: BorderRadius.circular(4 * c),
              ),
              child: Center(
                child: Icon(icon, size: 52 * c, color: tint.withValues(alpha: 0.75)),
              ),
            ),
          SizedBox(height: 10 * c),
          Center(
            child: SelectableText(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13 * c, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(height: 6 * c),
          Center(child: _buildInfoChips(c, cs)),
        ],
      ),
    );
  }

  Widget _tintedPlaceholder(double c, ColorScheme cs, Color tint, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tint.withValues(alpha: 0.22),
            tint.withValues(alpha: 0.07),
          ],
        ),
      ),
      child: Center(
        child: Icon(icon, size: 52 * c, color: tint.withValues(alpha: 0.75)),
      ),
    );
  }

  /// 标题下方的信息行：类型 / 评分（星标+数值）/ 分级。
  Widget _buildInfoChips(double c, ColorScheme cs) {
    final chips = <Widget>[];
    if (_isItem) {
      final info = widget.effectiveInfo ?? widget.item!.info;
      if (info.type.isNotEmpty) {
        chips.add(_infoChip(
          c: c,
          cs: cs,
          icon: _typeIcon(info.type),
          label: info.type,
          color: _typeColor(info.type),
        ));
      }
      if (info.rating > 0) {
        final stars = (info.rating / 2).clamp(0, 5);
        chips.add(_infoChip(
          c: c,
          cs: cs,
          icon: Icons.star_rounded,
          label: '${stars.toStringAsFixed(1)} / 5',
          color: Colors.amber.shade600,
        ));
      }
      if (info.contentRating.isNotEmpty) {
        chips.add(_infoChip(
          c: c,
          cs: cs,
          icon: Icons.shield_outlined,
          label: info.contentRating,
          color: cs.onSurfaceVariant,
        ));
      }
    } else if (_isFolder) {
      chips.add(_infoChip(
        c: c,
        cs: cs,
        icon: Icons.folder_outlined,
        label: Strings.t('folderLabel'),
        color: Colors.amber.shade600,
      ));
    } else if (_isFile) {
      final f = widget.file!;
      chips.add(_infoChip(
        c: c,
        cs: cs,
        icon: _fileIcon(f.extension),
        label: f.extension.isNotEmpty ? '.${f.extension}' : Strings.t('noExt'),
        color: _fileColor(f.extension),
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6 * c,
      runSpacing: 6 * c,
      alignment: WrapAlignment.center,
      children: chips,
    );
  }

  Widget _infoChip({
    required double c,
    required ColorScheme cs,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * c, vertical: 3 * c),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4 * c),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12 * c, color: color),
          SizedBox(width: 4 * c),
          Text(
            label,
            style: TextStyle(
              fontSize: 11 * c,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ===== 标签页内容（并入整页滚动，不再各自内滚）=====

  Widget _tabContent(
      BuildContext context, double c, ColorScheme cs, _DetailTab key) {
    switch (key) {
      case _DetailTab.overview:
        return _overviewContent(context, c, cs);
      case _DetailTab.metadata:
        return _metadataContent(context, c, cs);
      case _DetailTab.files:
        return _filesContent(context, c);
      case _DetailTab.related:
        return _relatedContent(context, c, cs);
    }
  }

  Widget _overviewContent(BuildContext context, double c, ColorScheme cs) {
    final children = <Widget>[];

    if (_isItem) {
      final info = widget.effectiveInfo ?? widget.item!.info;
      if (info.description.isNotEmpty) {
        children.add(_descriptionCard(context, c, cs, info.description));
        children.add(SizedBox(height: 10 * c));
      }
      if ((info.creator ?? '').isNotEmpty) {
        children.add(_metaLine(context, c, cs, Strings.t('creator'),
            info.creator ?? '', color: cs.primary));
      }
      if (info.classes.isNotEmpty) {
        children.add(_sectionTitle(context, c, cs, Strings.t('classLabel')));
        children.add(_chipWrap(context, c, cs, info.classes, 'class'));
        children.add(SizedBox(height: 8 * c));
      }
      if (info.tags.isNotEmpty) {
        children.add(_sectionTitle(context, c, cs, Strings.t('tags')));
        children.add(_chipWrap(context, c, cs, info.tags, 'tags'));
        children.add(SizedBox(height: 8 * c));
      }
    } else if (_isFolder) {
      final info = widget.folder!.info;
      if (info != null && info.description.isNotEmpty) {
        children.add(_descriptionCard(context, c, cs, info.description));
      } else {
        children.add(_hintCard(context, c, cs,
            '${widget.folder!.subDirs.length} 个子文件夹 · ${widget.folder!.items.length} 个项目'));
      }
    } else if (_isFile) {
      children.add(_hintCard(context, c, cs,
          '${widget.file!.extension.isNotEmpty ? '.${widget.file!.extension}' : Strings.t('noExt')} · ${_formatSize(widget.file!.sizeInBytes)}'));
    }

    if (children.isEmpty) {
      return _hintCard(context, c, cs, Strings.t('noItems'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _metadataContent(BuildContext context, double c, ColorScheme cs) {
    final rows = <Widget>[];

    if (_isItem) {
      final info = widget.effectiveInfo ?? widget.item!.info;
      rows.add(_copyableRow(context, c, cs, Strings.t('creator'), info.creator ?? ''));
      rows.add(_copyableRow(context, c, cs, Strings.t('type'), info.type));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('contentRating'), info.contentRating));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('rating'), '${(info.rating / 2).toStringAsFixed(1)} / 5'));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('classLabel'), info.classes.join(', ')));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('tags'), info.tags.join(', ')));
      rows.add(_copyableRow(context, c, cs, Strings.t('category'), widget.item!.category));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('size'), _formatSize(widget.item!.sizeInBytes)));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('modifiedTime'), _formatDate(widget.item!.modifiedTime)));
      rows.add(_copyableRow(context, c, cs, Strings.t('path'), widget.item!.path));
      final uuid = widget.item!.info.uuid;
      rows.add(_copyableRow(context, c, cs, Strings.t('uuid'),
          uuid == null || uuid.isEmpty ? '—' : uuid));
    } else if (_isFolder) {
      final info = widget.folder!.info;
      if (info != null) {
        rows.add(_copyableRow(context, c, cs, Strings.t('creator'), info.creator ?? ''));
        rows.add(_copyableRow(context, c, cs, Strings.t('type'), info.type));
        rows.add(_copyableRow(
            context, c, cs, Strings.t('contentRating'), info.contentRating));
        rows.add(_copyableRow(
            context, c, cs, Strings.t('rating'), '${(info.rating / 2).toStringAsFixed(1)} / 5'));
      }
      rows.add(_copyableRow(context, c, cs, Strings.t('path'), widget.folder!.path));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('size'), _formatSize(widget.folder!.sizeInBytes)));
      rows.add(_copyableRow(context, c, cs, Strings.t('subfolderCount'),
          '${widget.folder!.subDirs.length}'));
      rows.add(_copyableRow(context, c, cs, Strings.t('directItemCount'),
          '${widget.folder!.items.length}'));
    } else if (_isFile) {
      final f = widget.file!;
      rows.add(_copyableRow(context, c, cs, Strings.t('extension'),
          f.extension.isNotEmpty ? '.${f.extension}' : Strings.t('noExt')));
      rows.add(_copyableRow(context, c, cs, Strings.t('size'), _formatSize(f.sizeInBytes)));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('modifiedTime'), _formatDate(f.modifiedTime)));
      rows.add(_copyableRow(context, c, cs, Strings.t('path'), f.path));
    }

    return Column(children: rows);
  }

  /// "文件"标签页内容：仅在 item 且底部文件面板关闭时存在，
  /// 直接显示嵌入的文件浏览区（信息行与"元数据"标签页重复，已移除）。
  Widget _filesContent(BuildContext context, double c) {
    if (widget.state == null || widget.scriptService == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 4 * c),
        _buildEmbeddedBrowser(context),
      ],
    );
  }

  Widget _buildEmbeddedBrowser(BuildContext context) {
    final it = widget.item!;
    final v = widget.onOpenVideoPlayer;
    final a = widget.onOpenAudioPlayer;
    final r = widget.onOpenComicReader;
    final e = widget.onOpenEbookReader;
    final h = widget.onOpenEdgeHtml;
    final m = widget.onOpenMarkdown;
    return FileBrowserPanel(
      item: it,
      state: widget.state!,
      scriptService: widget.scriptService!,
      backgroundOpacity: widget.backgroundOpacity,
      gifMode: widget.gifMode,
      embedded: true,
      onPlayProject: v == null ? null : () => v(it),
      onPlayVideoFile: v == null ? null : (path) => v(it, startPath: path),
      onPlayAudioProject: a == null ? null : () => a(it),
      onPlayAudioFile: a == null ? null : (path) => a(it, startPath: path),
      onReadProject: r == null ? null : () => r(it),
      onReadImageFile: r == null ? null : (path) => r(it, startPath: path),
      onReadEbookProject: e == null ? null : () => e(it),
      onReadEbookFile: e == null ? null : (path) => e(it, startPath: path),
      onBrowseHtmlProject: h == null ? null : () => h(it),
      onBrowseHtmlFile: h == null ? null : (path) => h(it, startPath: path),
      onBrowseMarkdownProject: m == null ? null : () => m(it),
      onBrowseMarkdownFile: m == null ? null : (path) => m(it, startPath: path),
    );
  }

  /// 文件标签页右下角的悬浮操作按钮组：32px 扁平圆形灰色按钮，
  /// 与中间网格区 40px 主题色带阴影的创建按钮在视觉上区分。
  /// 按钮内容：打开项目（随类型）、显示/隐藏 Info、取消全选（有选中时）。
  Widget _buildFloatingButtons(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    final it = widget.item!;
    final type = (widget.effectiveInfo ?? it.info).type.toLowerCase();
    final state = widget.state!;
    final buttons = <Widget>[];

    void add(IconData icon, String tooltip, VoidCallback onTap) {
      buttons.add(
        Tooltip(
          message: tooltip,
          child: Material(
            color: cs.surfaceContainerHighest,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 32 * c,
                height: 32 * c,
                child: Icon(icon, size: 16 * c, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ),
      );
      buttons.add(SizedBox(width: 10 * c));
    }

    switch (type) {
      case 'video':
      case 'anime':
        if (widget.onOpenVideoPlayer != null) {
          add(Icons.play_arrow, Strings.t('openProjectVideos'),
              () => widget.onOpenVideoPlayer!(it));
        }
        break;
      case 'comic':
      case 'picture':
        if (widget.onOpenComicReader != null) {
          add(Icons.auto_stories, Strings.t('openProjectComic'),
              () => widget.onOpenComicReader!(it));
        }
        break;
      case 'novel':
      case 'book':
        if (widget.onOpenEbookReader != null) {
          add(Icons.menu_book, Strings.t('openProjectEbook'),
              () => widget.onOpenEbookReader!(it));
        }
        break;
      case 'voice':
      case 'music':
        if (widget.onOpenAudioPlayer != null) {
          add(Icons.audiotrack, Strings.t('openProjectAudio'),
              () => widget.onOpenAudioPlayer!(it));
        }
        break;
      case 'edgehtml':
        if (widget.onOpenEdgeHtml != null) {
          add(Icons.html, Strings.t('openProjectHtml'),
              () => widget.onOpenEdgeHtml!(it));
        }
        break;
      case 'markdown':
        if (widget.onOpenMarkdown != null) {
          add(Icons.article, Strings.t('openProjectMarkdown'),
              () => widget.onOpenMarkdown!(it));
        }
        break;
    }

    final showSystem = state.showSystemFiles;
    add(
      showSystem ? Icons.visibility_off : Icons.visibility,
      showSystem ? Strings.t('hideInfo') : Strings.t('showInfo'),
      state.toggleSystemFiles,
    );

    if (state.selectedBrowserPaths.isNotEmpty) {
      add(Icons.deselect, Strings.t('deselectAll'), state.clearBrowserSelection);
    }

    if (buttons.isNotEmpty && buttons.last is SizedBox) {
      buttons.removeLast();
    }
    return Row(mainAxisSize: MainAxisSize.min, children: buttons);
  }

  Widget _relatedContent(BuildContext context, double c, ColorScheme cs) {
    if (_isItem) {
      final info = widget.effectiveInfo ?? widget.item!.info;
      if (info.goto.isNotEmpty) {
        return _buildGotoSection(context, c, cs, info.goto);
      }
    }
    return _hintCard(context, c, cs, Strings.t('noRelated'));
  }

  // ===== 通用小组件 =====

  Widget _descriptionCard(
      BuildContext context, double c, ColorScheme cs, String text) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10 * c),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4 * c),
      ),
      child: _buildUrlText(context, c, cs, text),
    );
  }

  Widget _hintCard(BuildContext context, double c, ColorScheme cs, String text) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10 * c),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4 * c),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11 * c, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _sectionTitle(
      BuildContext context, double c, ColorScheme cs, String label) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6 * c),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11 * c,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _chipWrap(BuildContext context, double c, ColorScheme cs,
      List<String> values, String field) {
    return Wrap(
      spacing: 6 * c,
      runSpacing: 6 * c,
      children: values.map((v) {
        final color = _chipColor(v);
        return InputChip(
          label: Text(v),
          backgroundColor: color.withValues(alpha: 0.16),
          labelStyle: TextStyle(fontSize: 11 * c, color: color),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.symmetric(horizontal: 6 * c),
          onPressed: widget.onSearchByQuery == null
              ? null
              : () => widget.onSearchByQuery!('$field:$v'),
        );
      }).toList(),
    );
  }

  Widget _metaLine(BuildContext context, double c, ColorScheme cs, String label,
      String value,
      {Color? color}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6 * c),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56 * c,
            child: Text(label,
                style: TextStyle(fontSize: 11 * c, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(value,
                style: TextStyle(
                    fontSize: 11 * c, color: color ?? cs.onSurface)),
          ),
        ],
      ),
    );
  }

  /// 可点击复制的字段行：点击整行把值复制到剪贴板并提示。
  Widget _copyableRow(BuildContext context, double c, ColorScheme cs,
      String label, String value) {
    final display = value.isEmpty ? '—' : value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4 * c),
        onTap: () => _copy(context, value),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 5 * c, horizontal: 4 * c),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56 * c,
                child: Text(label,
                    style:
                        TextStyle(fontSize: 11 * c, color: cs.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(
                  display,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11 * c, color: cs.onSurface),
                ),
              ),
              SizedBox(width: 4 * c),
              Icon(Icons.copy, size: 13 * c, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  void _copy(BuildContext context, String value) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(Strings.t('copied')),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  Widget _buildGotoSection(BuildContext context, double c, ColorScheme cs,
      List<GotoEntry> goto) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 6 * c),
          child: Text(
            Strings.t('relatedItems'),
            style: TextStyle(
              fontSize: 11 * c,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Wrap(
          spacing: 6 * c,
          runSpacing: 4 * c,
          children: goto.map((entry) {
            final label = _gotoLabel(entry);
            final color = _chipColor(label);
            return ActionChip(
              label: Text(label, style: TextStyle(fontSize: 11 * c)),
              avatar: Icon(Icons.link, size: 12 * c, color: color),
              backgroundColor: color.withValues(alpha: 0.16),
              labelStyle: TextStyle(fontSize: 11 * c, color: color),
              onPressed: () => widget.onGotoTap?.call(entry),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.symmetric(horizontal: 4 * c),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 关联条目的展示名：name 非空直接用；
  /// name 为空时回退目标标题——uuid 型查库内项目 title，
  /// path 型读目标目录 info.json 的 title（读不到回退子文件夹名）。
  String _gotoLabel(GotoEntry entry) {
    if (entry.name.isNotEmpty) return entry.name;
    if (entry.uuid.isNotEmpty) {
      final item = widget.state?.itemByUuid(entry.uuid);
      if (item != null) {
        final title = widget.state!.effectiveInfo(item).title.trim();
        if (title.isNotEmpty) return title;
      }
      return '';
    }
    final relative = entry.path;
    if (relative != null && relative.isNotEmpty && _isItem) {
      final sep = Platform.pathSeparator;
      final targetDir = '${widget.item!.path}$sep$relative';
      try {
        final infoFile = File('$targetDir$sep${'info.json'}');
        if (infoFile.existsSync()) {
          final raw = jsonDecode(infoFile.readAsStringSync());
          if (raw is Map && raw['title'] is String) {
            final title = (raw['title'] as String).trim();
            if (title.isNotEmpty) return title;
          }
        }
      } catch (_) {}
      final parts = relative.replaceAll('\\', '/').split('/');
      if (parts.isNotEmpty && parts.last.isNotEmpty) return parts.last;
    }
    return '';
  }

  Widget _buildEmpty(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        Strings.t('selectHint'),
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12 * c),
      ),
    );
  }

  // ===== 头部派生数据 =====

  String _headerTitle() {
    if (_isItem) {
      final info = widget.effectiveInfo ?? widget.item!.info;
      return info.title;
    }
    if (_isFolder) {
      final info = widget.folder!.info;
      return info != null ? info.title : widget.folder!.name;
    }
    return widget.file!.name;
  }

  String? _headerImagePath() {
    if (_isItem) return widget.item!.previewPath;
    if (_isFile) {
      final ext = widget.file!.extension;
      final isImage = previewExtensions.any((e) => e == '.$ext');
      return isImage ? widget.file!.path : null;
    }
    return null;
  }

  Color _headerTint() {
    if (_isItem) {
      final info = widget.effectiveInfo ?? widget.item!.info;
      return _typeColor(info.type);
    }
    if (_isFolder) return Colors.amber.shade400;
    return _fileColor(widget.file!.extension);
  }

  IconData _headerIcon() {
    if (_isItem) {
      final info = widget.effectiveInfo ?? widget.item!.info;
      return _typeIcon(info.type);
    }
    if (_isFolder) return Icons.folder;
    return _fileIcon(widget.file!.extension);
  }

  // ===== 类型/文件图标与配色（与卡片徽章一致）=====

  IconData _typeIcon(String type) {
    switch (type) {
      case 'video':
        return Icons.movie;
      case 'anime':
        return Icons.live_tv;
      case 'novel':
        return Icons.menu_book;
      case 'book':
        return Icons.book;
      case 'application':
        return Icons.apps;
      case 'zip':
        return Icons.archive;
      case 'picture':
        return Icons.photo;
      case 'comic':
        return Icons.auto_stories;
      case 'voice':
        return Icons.mic;
      case 'music':
        return Icons.music_note;
      case 'edgehtml':
        return Icons.html;
      case 'markdown':
        return Icons.article;
      default:
        return Icons.label;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'video':
        return Colors.redAccent;
      case 'anime':
        return Colors.pinkAccent;
      case 'novel':
        return Colors.tealAccent;
      case 'book':
        return Colors.brown.shade300;
      case 'application':
        return Colors.lightBlueAccent;
      case 'zip':
        return Colors.amber;
      case 'picture':
        return Colors.greenAccent;
      case 'comic':
        return Colors.purpleAccent;
      case 'voice':
        return Colors.orangeAccent;
      case 'music':
        return Colors.cyanAccent;
      case 'edgehtml':
        return Colors.orange;
      case 'markdown':
        return Colors.lightGreen;
      default:
        return Colors.grey;
    }
  }

  IconData _fileIcon(String ext) {
    switch (ext) {
      case 'mp4' || 'mkv' || 'avi' || 'mov' || 'wmv': return Icons.video_file;
      case 'mp3' || 'flac' || 'wav' || 'aac' || 'ogg': return Icons.audio_file;
      case 'pdf': return Icons.picture_as_pdf;
      case 'zip' || 'rar' || '7z' || 'tar' || 'gz': return Icons.folder_zip;
      case 'exe' || 'msi' || 'bat' || 'sh': return Icons.terminal;
      case 'txt' || 'md' || 'log': return Icons.article;
      case 'json' || 'xml' || 'yaml' || 'toml': return Icons.data_object;
      default: return Icons.insert_drive_file;
    }
  }

  Color _fileColor(String ext) {
    switch (ext) {
      case 'mp4' || 'mkv' || 'avi' || 'mov' || 'wmv': return Colors.blue.shade400;
      case 'mp3' || 'flac' || 'wav' || 'aac' || 'ogg': return Colors.purple.shade400;
      case 'pdf': return Colors.red.shade400;
      case 'zip' || 'rar' || '7z' || 'tar' || 'gz': return Colors.orange.shade400;
      case 'exe' || 'msi' || 'bat' || 'sh': return Colors.green.shade400;
      case 'txt' || 'md' || 'log': return Colors.grey.shade600;
      case 'json' || 'xml' || 'yaml' || 'toml': return Colors.teal.shade400;
      default: return Colors.grey.shade500;
    }
  }

  /// 由字符串哈希出稳定的色相，保证同一标签颜色稳定。
  Color _chipColor(String s) {
    final hue = (s.codeUnits.fold(0, (a, b) => a + b) * 37) % 360;
    return HSLColor.fromAHSL(1.0, hue.toDouble(), 0.55, 0.55).toColor();
  }

  Widget _buildUrlText(
      BuildContext context, double c, ColorScheme cs, String text) {
    final urlRegex = RegExp(r'https?://[^\s]+');
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in urlRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () => _openUrl(url),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return SelectableText.rich(
      TextSpan(style: TextStyle(fontSize: 11 * c, color: cs.onSurface), children: spans),
    );
  }

  void _openUrl(String url) {
    Process.run('cmd', ['/c', 'start', url]);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

class _TabSpec {
  final _DetailTab key;
  final String labelKey;
  final IconData icon;
  const _TabSpec(this.key, this.labelKey, this.icon);
}
