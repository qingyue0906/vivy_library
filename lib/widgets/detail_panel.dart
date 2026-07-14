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
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
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

  bool get _isItem => widget.item != null;
  bool get _isFolder => widget.folder != null;
  bool get _isFile => widget.file != null;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabSpecs().length,
      vsync: this,
      animationDuration: AppMotion.durNormal,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 依据当前选中对象的类型决定要展示哪些标签页。
  List<_TabSpec> _tabSpecs() {
    if (_isItem) {
      return const [
        _TabSpec(_DetailTab.overview, '概览', Icons.dashboard_outlined),
        _TabSpec(_DetailTab.metadata, '元数据', Icons.data_object_outlined),
        _TabSpec(_DetailTab.files, '文件', Icons.folder_outlined),
        _TabSpec(_DetailTab.related, '关联', Icons.link_outlined),
      ];
    }
    if (_isFolder) {
      return const [
        _TabSpec(_DetailTab.overview, '概览', Icons.dashboard_outlined),
        _TabSpec(_DetailTab.metadata, '元数据', Icons.data_object_outlined),
        _TabSpec(_DetailTab.files, '文件', Icons.folder_outlined),
      ];
    }
    if (_isFile) {
      return const [
        _TabSpec(_DetailTab.overview, '概览', Icons.dashboard_outlined),
        _TabSpec(_DetailTab.metadata, '元数据', Icons.data_object_outlined),
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;

    if (!_isItem && !_isFolder && !_isFile) {
      return _buildEmpty(context, c);
    }

    final specs = _tabSpecs();
    // 详情头部作为 Hero 起点：打开播放器/阅读器时与封面对接飞行。
    final heroChild = _isItem
        ? Hero(tag: widget.item!.path, child: _buildHeader(context, c, cs))
        : _buildHeader(context, c, cs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heroChild,
        TabBar(
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
          tabs: [
            for (final s in specs)
              Tab(
                text: s.label,
                height: 38 * c,
                icon: Icon(s.icon, size: 16 * c),
              ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final s in specs)
                _tabContent(context, c, cs, s.key),
            ],
          ),
        ),
      ],
    );
  }

  // ===== 头部大预览卡 =====

  Widget _buildHeader(BuildContext context, double c, ColorScheme cs) {
    final title = _headerTitle();
    final subtitle = _headerSubtitle();
    final imagePath = _headerImagePath();
    final tintColor = _headerTint();
    final icon = _headerIcon();
    final hasImage = imagePath != null;

    final chips = <Widget>[
      _pillChip(context, c, cs, label: subtitle ?? '', color: tintColor,
          icon: icon),
      if (_isItem) ..._ratingChips(context, c, cs),
    ];

    return TweenAnimationBuilder<double>(
      duration: AppMotion.durNormal,
      curve: AppMotion.emphasized,
      tween: Tween(begin: 0.92, end: 1.0),
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: child,
      ),
      child: Container(
        margin: EdgeInsets.fromLTRB(12 * c, 12 * c, 12 * c, 4 * c),
        height: hasImage ? 168 * c : 116 * c,
        child: ClipRRect(
          borderRadius: context.metrics.br,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _tintedBackground(c, cs, tintColor, icon),
                )
              else
                _tintedBackground(c, cs, tintColor, icon),
              if (hasImage)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                      stops: const [0.45, 1.0],
                    ),
                  ),
                ),
              Positioned(
                left: 12 * c,
                right: 12 * c,
                bottom: 10 * c,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15 * c,
                        fontWeight: FontWeight.w700,
                        color: hasImage ? Colors.white : cs.onPrimaryContainer,
                        shadows: hasImage
                            ? [
                                const Shadow(
                                  color: Colors.black54,
                                  offset: Offset(0, 1),
                                  blurRadius: 2,
                                )
                              ]
                            : null,
                      ),
                    ),
                    SizedBox(height: 8 * c),
                    Wrap(
                      spacing: 6 * c,
                      runSpacing: 6 * c,
                      children: chips,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tintedBackground(double c, ColorScheme cs, Color tint, IconData icon) {
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
        child: Icon(icon, size: 56 * c, color: tint.withValues(alpha: 0.7)),
      ),
    );
  }

  // ===== 标签页内容 =====

  Widget _tabContent(
      BuildContext context, double c, ColorScheme cs, _DetailTab key) {
    late final Widget body;
    switch (key) {
      case _DetailTab.overview:
        body = _overviewContent(context, c, cs);
      case _DetailTab.metadata:
        body = _metadataContent(context, c, cs);
      case _DetailTab.files:
        body = _filesContent(context, c, cs);
      case _DetailTab.related:
        body = _relatedContent(context, c, cs);
    }
    return SmoothScroll(
      builder: (ctx, controller, physics) => ListView(
        controller: controller,
        physics: physics,
        padding: EdgeInsets.all(12 * c),
        children: [body],
      ),
    );
  }

  Widget _overviewContent(BuildContext context, double c, ColorScheme cs) {
    final children = <Widget>[];

    if (_isItem) {
      final info = widget.effectiveInfo ?? widget.item!.info;
      if (info.description.isNotEmpty) {
        children.add(_descriptionCard(context, c, cs, info.description));
        children.add(SizedBox(height: 10 * c));
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
      if ((info.creator ?? '').isNotEmpty) {
        children.add(_metaLine(context, c, cs, Strings.t('creator'),
            info.creator ?? '', color: cs.primary));
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
        borderRadius: context.metrics.brSmall,
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
        borderRadius: context.metrics.brSmall,
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

  Widget _copyableRow(BuildContext context, double c, ColorScheme cs,
      String label, String value) {
    final display = value.isEmpty ? '—' : value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: context.metrics.brSmall,
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
        duration: const Duration(seconds: 1, milliseconds: 500),
      ),
    );
  }

  Widget _pillChip(BuildContext context, double c, ColorScheme cs,
      {required String label, required Color color, required IconData icon}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * c, vertical: 3 * c),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: label.isEmpty ? 0 : 0.35),
        borderRadius: context.metrics.brPill,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12 * c, color: Colors.white),
          SizedBox(width: 4 * c),
          Text(
            label,
            style: TextStyle(fontSize: 11 * c, color: Colors.white),
          ),
        ],
      ),
    );
  }

  List<Widget> _ratingChips(BuildContext context, double c, ColorScheme cs) {
    final info = widget.effectiveInfo ?? widget.item!.info;
    final stars = (info.rating / 2).clamp(0, 5);
    return [
      Container(
        padding: EdgeInsets.symmetric(horizontal: 8 * c, vertical: 3 * c),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: context.metrics.brPill,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 12 * c, color: context.vivy.star),
            SizedBox(width: 4 * c),
            Text(
              '${stars.toStringAsFixed(1)} / 5',
              style: TextStyle(fontSize: 11 * c, color: Colors.white),
            ),
          ],
        ),
      ),
    ];
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

  String? _headerSubtitle() {
    if (_isItem) {
      final info = widget.effectiveInfo ?? widget.item!.info;
      return info.type;
    }
    if (_isFolder) return Strings.t('folderLabel');
    return widget.file!.extension.isNotEmpty
        ? '.${widget.file!.extension}'
        : Strings.t('noExt');
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
      return context.vivy.forType(info.type);
    }
    if (_isFolder) return context.vivy.typeFolder;
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

  // ===== 字段解析辅助 =====

  IconData _typeIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('video')) return Icons.movie_outlined;
    if (t.contains('audio')) return Icons.audiotrack_outlined;
    if (t.contains('comic') || t.contains('manga')) return Icons.menu_book_outlined;
    if (t.contains('ebook') || t.contains('book')) return Icons.auto_stories_outlined;
    if (t.contains('game') || t.contains('exe')) return Icons.sports_esports_outlined;
    return Icons.collections_outlined;
  }

  IconData _fileIcon(String ext) {
    switch (ext) {
      case 'mp4' || 'mkv' || 'avi' || 'mov' || 'wmv':
        return Icons.video_file;
      case 'mp3' || 'flac' || 'wav' || 'aac' || 'ogg':
        return Icons.audio_file;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'zip' || 'rar' || '7z' || 'tar' || 'gz':
        return Icons.folder_zip;
      case 'exe' || 'msi' || 'bat' || 'sh':
        return Icons.terminal;
      case 'txt' || 'md' || 'log':
        return Icons.article;
      case 'json' || 'xml' || 'yaml' || 'toml':
        return Icons.data_object;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _fileColor(String ext) {
    final cs = Theme.of(context).colorScheme;
    final map = <String, Color>{
      'mp4': cs.primary,
      'mkv': cs.primary,
      'avi': cs.primary,
      'mov': cs.primary,
      'wmv': cs.primary,
      'mp3': Colors.purple,
      'flac': Colors.purple,
      'wav': Colors.purple,
      'aac': Colors.purple,
      'ogg': Colors.purple,
      'pdf': Colors.red,
      'zip': Colors.orange,
      'rar': Colors.orange,
      '7z': Colors.orange,
      'tar': Colors.orange,
      'gz': Colors.orange,
      'exe': Colors.green,
      'msi': Colors.green,
      'bat': Colors.green,
      'sh': Colors.green,
      'txt': cs.onSurfaceVariant,
      'md': cs.onSurfaceVariant,
      'log': cs.onSurfaceVariant,
      'json': Colors.teal,
      'xml': Colors.teal,
      'yaml': Colors.teal,
      'toml': Colors.teal,
    };
    return map[ext] ?? cs.onSurfaceVariant;
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
  final String label;
  final IconData icon;
  const _TabSpec(this.key, this.label, this.icon);
}
