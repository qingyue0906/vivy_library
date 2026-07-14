import 'package:flutter/material.dart';
import '../models/category_node.dart';
import '../services/translations.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import 'compact_level.dart';
import 'smooth_scroll.dart';

/// 左侧分类栏，树形展示多层文件夹。
/// 有子文件夹的节点显示展开箭头，点击展开/收起子层（带旋转 + 高度动画）。
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
              icon: Icons.apps_rounded,
              isSelected: widget.selectedCategoryPath == null,
              onTap: () => widget.onCategorySelected(null),
            ),
            _CategoryTile(
              label: Strings.t('rootDir'),
              value: widget.root.path,
              depth: 0,
              icon: Icons.folder_open_rounded,
              isSelected: widget.selectedCategoryPath == widget.root.path,
              onTap: () => widget.onCategorySelected(widget.root.path),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10 * c, vertical: 4 * c),
              child: Divider(
                height: 1,
                thickness: 1,
                color: cs.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            // Part 2: 根级直接文件夹展开树
            ...widget.root.subDirs.map((node) => _buildNode(context, c, node, 0)),
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
          icon: hasSubDirs
              ? (isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded)
              : Icons.folder_rounded,
          isSelected: widget.selectedCategoryPath == node.path,
          hasSubDirs: hasSubDirs,
          isExpanded: isExpanded,
          onTap: () => widget.onCategorySelected(node.path),
          onToggleExpand:
              hasSubDirs ? () => widget.onToggleExpand(node.path) : null,
        ),
        // 展开/收起用 AnimatedSize 做平滑高度过渡。
        AnimatedSize(
          duration: AppMotion.durNormal,
          curve: AppMotion.emphasized,
          alignment: Alignment.topCenter,
          child: (hasSubDirs && isExpanded)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: node.subDirs
                      .map((sub) => _buildNode(context, c, sub, depth + 1))
                      .toList(),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// 单个分类项：hover 高亮、选中圆角 pill + 左侧强调条、箭头旋转动画。
class _CategoryTile extends StatefulWidget {
  final String label;
  final String? value;
  final int depth;
  final IconData icon;
  final bool isSelected;
  final bool hasSubDirs;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback? onToggleExpand;

  const _CategoryTile({
    required this.label,
    required this.value,
    required this.depth,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.hasSubDirs = false,
    this.isExpanded = false,
    this.onToggleExpand,
  });

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final metrics = context.metrics;
    final c = CompactLevel.of(context);
    final selected = widget.isSelected;

    final Color bg = selected
        ? cs.primaryContainer.withValues(alpha: 0.9)
        : (_hover ? cs.onSurface.withValues(alpha: 0.06) : Colors.transparent);
    final Color fg = selected ? cs.onPrimaryContainer : cs.onSurface;
    final Color iconColor =
        selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6 * c, vertical: 1 * c),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppMotion.durFast,
            curve: AppMotion.standard,
            height: 30 * c,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: metrics.brSmall,
            ),
            child: Stack(
              children: [
                // 选中时左侧强调条
                if (selected)
                  Positioned(
                    left: 0,
                    top: 6 * c,
                    bottom: 6 * c,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(
                    left: 8 * c + widget.depth * 12 * c,
                    right: 8 * c,
                  ),
                  child: Row(
                    children: [
                      if (widget.hasSubDirs)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onToggleExpand,
                          child: Padding(
                            padding: EdgeInsets.all(1 * c),
                            child: AnimatedRotation(
                              turns: widget.isExpanded ? 0.25 : 0.0,
                              duration: AppMotion.durFast,
                              curve: AppMotion.standard,
                              child: Icon(
                                Icons.chevron_right,
                                size: 15 * c,
                                color: iconColor,
                              ),
                            ),
                          ),
                        )
                      else
                        SizedBox(width: 17 * c),
                      Icon(widget.icon, size: 14 * c, color: iconColor),
                      SizedBox(width: 6 * c),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12 * c,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: fg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
