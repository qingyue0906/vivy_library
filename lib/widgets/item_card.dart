import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/library_item.dart';
import '../models/item_info.dart';
import '../services/settings_service.dart';
import 'compact_level.dart';
import 'gif_image.dart';

class ItemCard extends StatefulWidget {
  final LibraryItem item;
  final ItemInfo effectiveInfo;
  final double displayWidth;
  final double displayHeight;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCtrlTap;
  final VoidCallback onShiftTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset globalPosition) onRightClick;
  final GifDisplayMode gifMode;
  final GridDisplayMode displayMode;
  final GridBadgeFlags badges;

  const ItemCard({
    super.key,
    required this.item,
    required this.effectiveInfo,
    this.displayWidth = 150,
    this.displayHeight = 112.5,
    required this.isSelected,
    required this.onTap,
    required this.onCtrlTap,
    required this.onShiftTap,
    this.onDoubleTap,
    required this.onRightClick,
    this.gifMode = GifDisplayMode.hover,
    this.displayMode = GridDisplayMode.loose,
    this.badges = const GridBadgeFlags(),
  });

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  bool _isHovered = false;
  DateTime? _lastTapTime;

  /// 手动双击判定：300ms 内二次点击触发 [onDoubleTap]，单击立即响应无延迟。
  void _handleTap() {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300) {
      _lastTapTime = null;
      widget.onDoubleTap?.call();
      return;
    }
    _lastTapTime = now;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    if (isShift) {
      widget.onShiftTap();
    } else if (isCtrl) {
      widget.onCtrlTap();
    } else {
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    final selectedColor = cs.brightness == Brightness.light
        ? const Color(0xFF7B49E0)
        : cs.primary;
    final hoverColor = cs.brightness == Brightness.light
        ? const Color(0xFFB89AFF)
        : const Color(0xFF7E8FA3);
    final radius = BorderRadius.circular(4 * c);
    final borderColor = widget.isSelected
        ? selectedColor
        : (_isHovered ? hoverColor : cs.outlineVariant);
    final borderWidth = widget.isSelected ? 1.5 : (_isHovered ? 1.0 : 0.5);

    // 预览图 + 徽章叠加（不含点击手势，由调用方包裹后复用）。
    final preview = ClipRRect(
      borderRadius: radius,
      child: GestureDetector(
        onTap: _handleTap,
        onSecondaryTapUp: (details) =>
            widget.onRightClick(details.globalPosition),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Container(
            height: widget.displayHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: radius),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: _buildBadges(context, c),
            ),
          ),
        ),
      ),
    );

    if (widget.displayMode == GridDisplayMode.list) {
      return _buildListRow(c, cs, selectedColor, hoverColor);
    }
    if (widget.displayMode == GridDisplayMode.cover) {
      return preview;
    }
    // loose / compact / adaptive
    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        preview,
        if (widget.displayMode != GridDisplayMode.compact)
          Expanded(child: _buildInfo(c)),
      ],
    );
  }

  Widget _buildTypeBadge(double c) {
    final type = widget.effectiveInfo.type.toLowerCase();
    if (type.isEmpty || type == 'default') return const SizedBox.shrink();
    return Positioned(
      top: 2 * c,
      left: 2 * c,
      child: Container(
        padding: EdgeInsets.all(2 * c),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10 * c),
        ),
        child: Icon(
          _typeIcon(type),
          size: 14 * c,
          color: _typeColor(type),
        ),
      ),
    );
  }

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
      default:
        return Colors.grey;
    }
  }

  Widget _buildPreviewImage(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    if (widget.item.previewPath == null) {
      return Center(
        child: Icon(
          Icons.image_not_supported,
          size: 20 * c,
          color: cs.onSurfaceVariant,
        ),
      );
    }
    final cacheW = ((widget.displayWidth * 2) ~/ 100 * 100)
        .clamp(100, 800)
        .toInt();
    final errorWidget = Center(
      child: Icon(Icons.broken_image, size: 20 * c, color: cs.onSurfaceVariant),
    );
    return GifImage(
      file: File(widget.item.previewPath!),
      gifMode: widget.gifMode,
      cacheWidth: cacheW,
      fit: BoxFit.cover,
      errorBuilder: (_) => errorWidget,
    );
  }

  Widget _buildInfo(double c) {
    return Padding(
      padding: EdgeInsets.only(top: 4 * c, left: 2 * c, right: 2 * c),
      child: Text(
        widget.item.info.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11 * c),
      ),
    );
  }

  /// 构建预览图与所有徽章的叠加层（紧凑模式额外把标题封到图内底部）。
  List<Widget> _buildBadges(BuildContext context, double c) {
    final list = <Widget>[_buildPreviewImage(context, c)];
    if (widget.badges.isEnabled(GridBadge.type)) {
      list.add(_buildTypeBadge(c));
    }
    if (widget.item.info.star && widget.badges.isEnabled(GridBadge.star)) {
      list.add(_buildStarBadge(c));
    }
    final rating = widget.effectiveInfo.contentRating;
    if (rating.isNotEmpty && widget.badges.isEnabled(GridBadge.rating)) {
      list.add(_buildRatingBadge(c, rating));
    }
    if (widget.displayMode == GridDisplayMode.compact) {
      list.add(_buildCompactTitle(c));
    }
    return list;
  }

  Widget _buildStarBadge(double c) => Positioned(
        top: 2 * c,
        right: 2 * c,
        child: Container(
          padding: EdgeInsets.all(2 * c),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10 * c),
          ),
          child: Icon(Icons.star, size: 14 * c, color: Colors.amber),
        ),
      );

  Widget _buildRatingBadge(double c, String rating) => Positioned(
        bottom: widget.displayMode == GridDisplayMode.compact ? 20 * c : 2 * c,
        right: 2 * c,
        child: Container(
          constraints: BoxConstraints(minWidth: 18 * c, minHeight: 18 * c),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 5 * c),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(9 * c),
          ),
          child: Text(
            rating,
            style: TextStyle(
              fontSize: 11 * c,
              color: _ratingColor(rating),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );

  /// 紧凑模式：把标题封到预览图内底部，作为半透明渐变条。
  Widget _buildCompactTitle(double c) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 2 * c, horizontal: 4 * c),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.75),
                Colors.transparent,
              ],
            ),
          ),
          child: Text(
            widget.item.info.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10 * c, color: Colors.white),
          ),
        ),
      );

  Color _ratingColor(String rating) {
    final r = rating.toUpperCase();
    if (r.contains('R')) return Colors.redAccent;
    if (r.contains('PG')) return Colors.orangeAccent;
    if (r.startsWith('G')) return Colors.greenAccent;
    return Colors.white;
  }

  /// 列表模式行：左侧缩略图、中间标题、右侧徽章。
  Widget _buildListRow(
    double c,
    ColorScheme cs,
    Color selectedColor,
    Color hoverColor,
  ) {
    final borderColor = widget.isSelected
        ? selectedColor
        : (_isHovered ? hoverColor : cs.outlineVariant);
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          widget.onRightClick(details.globalPosition),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: _handleTap,
          borderRadius: BorderRadius.circular(4 * c),
          splashColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: Container(
            height: widget.displayHeight + 10 * c,
            padding: EdgeInsets.symmetric(vertical: 4 * c, horizontal: 4 * c),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? cs.primaryContainer.withValues(alpha: 0.25)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4 * c),
              border: Border.all(
                color: borderColor,
                width: widget.isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: widget.displayHeight,
                  height: widget.displayHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4 * c),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildPreviewImage(context, c),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 8 * c),
                Expanded(
                  child: Text(
                    widget.item.info.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12 * c),
                  ),
                ),
                SizedBox(width: 8 * c),
                _buildListBadges(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 列表行右侧徽章：类型 / 标星 / 分级（受开关控制）。
  Widget _buildListBadges(double c) {
    final children = <Widget>[];
    if (widget.badges.isEnabled(GridBadge.type)) {
      final type = widget.effectiveInfo.type.toLowerCase();
      if (type.isNotEmpty && type != 'default') {
        children.add(
          Icon(_typeIcon(type), size: 14 * c, color: _typeColor(type)),
        );
      }
    }
    if (widget.item.info.star && widget.badges.isEnabled(GridBadge.star)) {
      children.add(Icon(Icons.star, size: 14 * c, color: Colors.amber));
    }
    final rating = widget.effectiveInfo.contentRating;
    if (rating.isNotEmpty && widget.badges.isEnabled(GridBadge.rating)) {
      // 列表模式右侧分级徽章与类型/标星图标一致：纯彩色文字，无背景。
      children.add(
        Text(
          rating,
          style: TextStyle(
            fontSize: 11 * c,
            color: _ratingColor(rating),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: 6 * c),
          children[i],
        ],
      ],
    );
  }
}
