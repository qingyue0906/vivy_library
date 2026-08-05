import 'package:flutter/material.dart';
import 'compact_level.dart';

/// 树形列表视觉常量。
const double treeRowHeight = 28;
const double treeRowFillHeight = 26;
const double treeIndent = 14;
const double treeRowMargin = 4;
const double treeRowRadius = 6;

/// 暗色主题下提亮后的选中填充色（M3 secondaryContainer 提亮版）。
const Color _darkSelected = Color(0xFF5B5475);

/// 树的一行：Material 3 风格（圆角 hover/选中、行内边距）、
/// 展开箭头（旋转动画）、缩进引导线（由 [lastChain] 决定线段终止）。
class TreeRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool hasSubDirs;
  final bool isExpanded;
  final int depth;
  final int lastChain;
  final VoidCallback? onTap;
  final VoidCallback? onToggleExpand;

  const TreeRow({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.hasSubDirs,
    required this.isExpanded,
    required this.depth,
    required this.lastChain,
    this.onTap,
    this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = CompactLevel.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = isDark ? _darkSelected : cs.secondaryContainer;
    final muted = isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: treeRowMargin * c),
      child: SizedBox(
        height: treeRowHeight * c,
        child: Stack(
          children: [
            Center(
              child: Material(
                color: isSelected ? selectedColor : Colors.transparent,
                borderRadius: BorderRadius.circular(treeRowRadius * c),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  hoverColor: cs.onSurface.withValues(alpha: 0.06),
                  child: SizedBox(
                    height: treeRowFillHeight * c,
                    child: Row(
                      children: [
                        // 缩进占位：与覆盖层引导线同宽，保证层级缩进。
                        if (depth > 0)
                          SizedBox(width: depth * treeIndent * c),
                        if (hasSubDirs)
                          GestureDetector(
                            onTap: onToggleExpand,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: EdgeInsets.all(1 * c),
                              child: AnimatedRotation(
                                turns: isExpanded ? 0.25 : 0,
                                duration: const Duration(milliseconds: 160),
                                curve: Curves.easeOutCubic,
                                child: Icon(
                                  Icons.chevron_right,
                                  size: 14 * c,
                                  color: muted,
                                ),
                              ),
                            ),
                          )
                        else
                          SizedBox(width: 16 * c),
                        Padding(
                          padding: EdgeInsets.only(left: 2 * c),
                          child: Icon(icon, size: 13 * c, color: muted),
                        ),
                        SizedBox(width: 4 * c),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12 * c,
                              color: isSelected
                                  ? cs.onSecondaryContainer
                                  : cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 缩进引导线：全高 28 覆盖层，保证行间竖线连续；不拦截点击。
            if (depth > 0)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: depth * treeIndent * c,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GuidePainter(
                      depth: depth,
                      lastChain: lastChain,
                      isLeaf: !hasSubDirs,
                      indent: treeIndent * c,
                      arrowCenterOffset: 8 * c,
                      color: cs.outlineVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 子树展开/收起动画：收起时先保留子树播放反向动画，结束后再卸载。
class ExpandableChildren extends StatefulWidget {
  final bool expanded;
  final WidgetBuilder builder;
  final Duration duration;

  const ExpandableChildren({
    super.key,
    required this.expanded,
    required this.builder,
    this.duration = const Duration(milliseconds: 160),
  });

  @override
  State<ExpandableChildren> createState() => _ExpandableChildrenState();
}

class _ExpandableChildrenState extends State<ExpandableChildren>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _keepChildren = false;

  @override
  void initState() {
    super.initState();
    _keepChildren = widget.expanded;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.expanded ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(ExpandableChildren oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    if (widget.expanded) {
      _keepChildren = true;
      _controller.forward();
    } else {
      _controller.reverse().whenComplete(() {
        if (mounted) setState(() => _keepChildren = false);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: _keepChildren ? widget.builder(context) : null,
      builder: (context, child) => ClipRect(
        child: Align(
          heightFactor: _controller.value,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// 缩进引导线：竖线对齐祖先行的箭头中心（arrowCenterOffset），
/// 最后一项子树终止处收口；行内画一条水平短横连接父级竖线与箭头区。
class _GuidePainter extends CustomPainter {
  final int depth;
  final int lastChain;
  final bool isLeaf;
  final double indent;
  final double arrowCenterOffset;
  final Color color;

  _GuidePainter({
    required this.depth,
    required this.lastChain,
    required this.isLeaf,
    required this.indent,
    required this.arrowCenterOffset,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (depth <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final midY = size.height / 2;
    for (var i = 0; i < depth; i++) {
      final x = i * indent + arrowCenterOffset;
      canvas.drawLine(Offset(x, 0), Offset(x, midY), paint);
      final endsHere = isLeaf && lastChain >= depth - i;
      if (!endsHere) {
        canvas.drawLine(Offset(x, midY), Offset(x, size.height), paint);
      }
      if (i == depth - 1) {
        canvas.drawLine(Offset(x, midY), Offset(size.width - 1, midY), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) =>
      oldDelegate.depth != depth ||
      oldDelegate.lastChain != lastChain ||
      oldDelegate.isLeaf != isLeaf ||
      oldDelegate.indent != indent ||
      oldDelegate.arrowCenterOffset != arrowCenterOffset ||
      oldDelegate.color != color;
}
