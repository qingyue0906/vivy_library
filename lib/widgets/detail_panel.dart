import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../models/item_info.dart';
import '../models/library_item.dart';
import '../models/category_node.dart';
import '../models/direct_file.dart';
import '../models/goto_entry.dart';
import '../services/library_scanner.dart' show previewExtensions;
import '../services/translations.dart';
import 'compact_level.dart';
import 'smooth_scroll.dart';

/// 详情面板的四个标签页。
enum _DetailTab { overview, metadata, files, related }

class DetailPanel extends StatelessWidget {
  final LibraryItem? item;
  final ItemInfo? effectiveInfo; // 有效 info（含父文件夹继承 + 硬编码保底）
  final CategoryNode? folder;
  final DirectFile? file;
  final double backgroundOpacity;
  final void Function(GotoEntry entry)? onGotoTap;
  final void Function(String query)? onSearchByQuery;

  const DetailPanel({
    super.key,
    this.item,
    this.effectiveInfo,
    this.folder,
    this.file,
    this.backgroundOpacity = 1.0,
    this.onGotoTap,
    this.onSearchByQuery,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 以选择对象身份作为 key，切换选中项时重建内部 TabController，
    // 避免标签页数量变化导致的断言错误。
    final selectionKey = Object.hash(item?.path, folder?.path, file?.path);
    return Container(
      color: cs.surfaceContainerLow.withValues(alpha: backgroundOpacity),
      child: _DetailPanelBody(
        key: ValueKey(selectionKey),
        item: item,
        effectiveInfo: effectiveInfo,
        folder: folder,
        file: file,
        onGotoTap: onGotoTap,
        onSearchByQuery: onSearchByQuery,
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

  const _DetailPanelBody({
    super.key,
    this.item,
    this.effectiveInfo,
    this.folder,
    this.file,
    this.onGotoTap,
    this.onSearchByQuery,
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
  List<_TabSpec> _tabSpecs() {
    if (_isItem) {
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
        _TabSpec(_DetailTab.files, 'tabFiles', Icons.folder_outlined),
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
    _tabController = TabController(
      length: _tabSpecs().length,
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
    // 整页一体滚动：头部、TabBar、当前标签内容共用一个滚动视图，
    // 滚轮滚动整个预览面板，而非只有标签下方的内容滚动。
    return SmoothScroll(
      builder: (context, controller, physics) {
        _outerController = controller;
        return CustomScrollView(
          controller: controller,
          physics: physics,
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(c, cs)),
            SliverToBoxAdapter(child: _buildTabBar(c, cs, specs)),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(12 * c, 4 * c, 12 * c, 16 * c),
              sliver: SliverToBoxAdapter(
                child: _tabContent(context, c, cs, specs[_tabController.index].key),
              ),
            ),
          ],
        );
      },
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
      onTap: (_) {
        // 切换标签后回到面板顶部，与每页独立滚动时从内容顶部开始的直觉一致
        _outerController?.jumpTo(0);
      },
      tabs: [
        for (final s in specs)
          Tab(
            text: Strings.t(s.labelKey),
            height: 38 * c,
            icon: Icon(s.icon, size: 16 * c),
          ),
      ],
    );
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
        return _filesContent(context, c, cs);
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
          context, c, cs, Strings.t('classLabel'), info.classes.join('、')));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('tags'), info.tags.join('、')));
      rows.add(_copyableRow(context, c, cs, Strings.t('category'), widget.item!.category));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('size'), _formatSize(widget.item!.sizeInBytes)));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('modifiedTime'), _formatDate(widget.item!.modifiedTime)));
      rows.add(_copyableRow(context, c, cs, Strings.t('path'), widget.item!.path));
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

  Widget _filesContent(BuildContext context, double c, ColorScheme cs) {
    final rows = <Widget>[];
    if (_isItem) {
      final it = widget.item!;
      rows.add(_copyableRow(context, c, cs, Strings.t('category'), it.category));
      rows.add(_copyableRow(context, c, cs, Strings.t('size'), _formatSize(it.sizeInBytes)));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('modifiedTime'), _formatDate(it.modifiedTime)));
      rows.add(_copyableRow(context, c, cs, Strings.t('path'), it.path));
    } else if (_isFolder) {
      final f = widget.folder!;
      rows.add(_copyableRow(context, c, cs, Strings.t('path'), f.path));
      rows.add(_copyableRow(context, c, cs, Strings.t('size'), _formatSize(f.sizeInBytes)));
      rows.add(_copyableRow(context, c, cs, Strings.t('subfolderCount'),
          '${f.subDirs.length}'));
      rows.add(_copyableRow(
          context, c, cs, Strings.t('directItemCount'), '${f.items.length}'));
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
            final color = _chipColor(entry.name);
            return ActionChip(
              label: Text(entry.name, style: TextStyle(fontSize: 11 * c)),
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
