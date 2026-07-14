import 'package:flutter/material.dart';
import '../models/category_node.dart';
import '../services/translations.dart';
import '../theme/design_tokens.dart';
import 'compact_level.dart';
import 'smooth_scroll.dart';

/// 左侧分类栏，树形展示多层文件夹。
/// 有子文件夹的节点显示展开箭头，点击展开/收起子层。
/// 展开状态托管在 LibraryState（expandedPaths / toggleExpand），
/// 因此刷新/编辑后的 rescan 不会丢失展开态。
class CategoryPanel extends StatefulWidget {
  final CategoryNode root;
  final String? selectedCategoryPath;
  final void Function(String?) onCategorySelected;
  final Set<String> expandedPaths;
  final void Function(String path) onToggleExpand;
  final double backgroundOpacity;

  const CategoryPanel({
    super.key,
    required this.root,
    required this.selectedCategoryPath,
    required this.onCategorySelected,
    required this.expandedPaths,
    required this.onToggleExpand,
    this.backgroundOpacity = 1.0,
  });

  @override
  State<CategoryPanel> createState() => _CategoryPanelState();
}

class _CategoryPanelState extends State<CategoryPanel> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = CompactLevel.of(context);
    return Material(
      color: cs.surfaceContainerLow.withValues(alpha: widget.backgroundOpacity),
      child: SmoothScroll(
        builder: (context, controller, physics) => ListView(
          controller: controller,
          physics: physics,
          padding: EdgeInsets.symmetric(vertical: 4 * c),
          children: [
            // Part 1: 全部项目 + 根目录
            _CategoryTile(
              label: Strings.t('allItems'),
              value: null,
              depth: 0,
              icon: Icons.apps,
              isSelected: widget.selectedCategoryPath == null,
              onSelected: () => widget.onCategorySelected(null),
            ),
            _CategoryTile(
              label: Strings.t('rootDir'),
              value: widget.root.path,
              depth: 0,
              icon: Icons.folder_open,
              isSelected: widget.selectedCategoryPath == widget.root.path,
              onSelected: () => widget.onCategorySelected(widget.root.path),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4 * c, horizontal: 8 * c),
              child: Divider(height: 1, thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            // Part 2: 根级直接文件夹展开树
            ...widget.root.subDirs.map((node) =>
                _buildNode(context, c, node, 0)),
          ],
        ),
      ),
    );
  }

  Widget _buildNode(BuildContext context, double c, CategoryNode node, int depth) {
    final hasSubDirs = node.subDirs.isNotEmpty;
    final isExpanded = widget.expandedPaths.contains(node.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CategoryTile(
          label: node.name,
          value: node.path,
          depth: depth,
          icon: Icons.folder,
          hasSubDirs: hasSubDirs,
          isExpanded: isExpanded,
          isSelected: widget.selectedCategoryPath == node.path,
          onSelected: () => widget.onCategorySelected(node.path),
          onToggleExpand: hasSubDirs
              ? () => widget.onToggleExpand(node.path)
              : null,
        ),
        if (hasSubDirs && isExpanded)
          ...node.subDirs.map((sub) => _buildNode(context, c, sub, depth + 1)),
      ],
    );
  }
}

/// 单个分类条目：悬停揭示、选中竖条 + 圆角底色、展开箭头旋转动画。
class _CategoryTile extends StatefulWidget {
  final String label;
  final String? value;
  final int depth;
  final IconData icon;
  final bool hasSubDirs;
  final bool isExpanded;
  final bool isSelected;
  final VoidCallback onSelected;
  final VoidCallback? onToggleExpand;

  const _CategoryTile({
    required this.label,
    required this.value,
    required this.depth,
    required this.icon,
    this.hasSubDirs = false,
    this.isExpanded = false,
    required this.isSelected,
    required this.onSelected,
    this.onToggleExpand,
  });

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = CompactLevel.of(context);
    final tokens = AppDesignTokens.of(context);
    final isSel = widget.isSelected;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: tokens.duration(MotionDurations.instant),
          curve: MotionCurves.standard,
          margin: EdgeInsets.symmetric(
            horizontal: 4 * c,
            vertical: 1 * c,
          ),
          height: 28 * c,
          decoration: BoxDecoration(
            color: isSel
                ? cs.primaryContainer.withValues(alpha: 0.55)
                : (_isHovered ? cs.primary.withValues(alpha: 0.07) : Colors.transparent),
            borderRadius: BorderRadius.circular(tokens.buttonRadius * c),
          ),
          child: Row(
            children: [
              // 选中竖条
              AnimatedContainer(
                duration: tokens.duration(MotionDurations.instant),
                width: 3 * c,
                margin: EdgeInsets.symmetric(vertical: 5 * c),
                decoration: BoxDecoration(
                  color: isSel ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2 * c),
                ),
              ),
              SizedBox(width: 4 * c),
              if (widget.hasSubDirs)
                _ExpandChevron(
                  expanded: widget.isExpanded,
                  onTap: widget.onToggleExpand,
                )
              else
                SizedBox(width: 16 * c),
              Icon(
                widget.icon,
                size: 14 * c,
                color: isSel ? cs.primary : cs.onSurfaceVariant,
              ),
              SizedBox(width: 5 * c),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12 * c,
                    color: isSel ? cs.onSurface : cs.onSurface,
                    fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 展开箭头：chevron 在展开/收起间旋转 90°，低开销 Tween。
class _ExpandChevron extends StatefulWidget {
  final bool expanded;
  final VoidCallback? onTap;

  const _ExpandChevron({required this.expanded, this.onTap});

  @override
  State<_ExpandChevron> createState() => _ExpandChevronState();
}

class _ExpandChevronState extends State<_ExpandChevron>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _turn;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: MotionDurations.fast,
      value: widget.expanded ? 1.0 : 0.0,
    );
    _turn = CurvedAnimation(parent: _ctrl, curve: MotionCurves.standard);
  }

  @override
  void didUpdateWidget(_ExpandChevron old) {
    super.didUpdateWidget(old);
    if (old.expanded != widget.expanded) {
      widget.expanded ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = CompactLevel.of(context);
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(6 * c),
      child: Padding(
        padding: EdgeInsets.all(2 * c),
        child: RotationTransition(
          turns: Tween(begin: 0.0, end: 0.25).animate(_turn),
          child: Icon(
            Icons.chevron_right,
            size: 16 * c,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
