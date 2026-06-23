import 'package:flutter/material.dart';
import '../models/category_node.dart';
import 'compact_level.dart';

/// 左侧分类栏，树形展示多层文件夹。
/// 有子文件夹的节点显示展开箭头，点击展开/收起子层。
class CategoryPanel extends StatefulWidget {
  final CategoryNode root;
  final String? selectedCategoryPath;
  final void Function(String?) onCategorySelected;
  final double backgroundOpacity;

  const CategoryPanel({
    super.key,
    required this.root,
    required this.selectedCategoryPath,
    required this.onCategorySelected,
    this.backgroundOpacity = 1.0,
  });

  @override
  State<CategoryPanel> createState() => _CategoryPanelState();
}

class _CategoryPanelState extends State<CategoryPanel> {
  final Set<String> _expandedPaths = {};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = CompactLevel.of(context);
    return Material(
      color: cs.surfaceContainerLow.withValues(alpha: widget.backgroundOpacity),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildItem(context, c,
              label: '全部', value: null, depth: 0, node: null),
          ...widget.root.subDirs.map((node) =>
              _buildNode(context, c, node, 0)),
        ],
      ),
    );
  }

  Widget _buildNode(BuildContext context, double c, CategoryNode node, int depth) {
    final hasSubDirs = node.subDirs.isNotEmpty;
    final isExpanded = _expandedPaths.contains(node.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildItem(context, c,
            label: node.name,
            value: node.path,
            depth: depth,
            node: node,
            hasSubDirs: hasSubDirs,
            isExpanded: isExpanded,
            onToggleExpand: hasSubDirs
                ? () => setState(() {
                      if (isExpanded) {
                        _expandedPaths.remove(node.path);
                      } else {
                        _expandedPaths.add(node.path);
                      }
                    })
                : null),
        if (hasSubDirs && isExpanded)
          ...node.subDirs.map((sub) => _buildNode(context, c, sub, depth + 1)),
      ],
    );
  }

  Widget _buildItem(
    BuildContext context,
    double c, {
    required String label,
    required String? value,
    required int depth,
    required CategoryNode? node,
    bool hasSubDirs = false,
    bool isExpanded = false,
    VoidCallback? onToggleExpand,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = widget.selectedCategoryPath == value;
    return Container(
      height: 28 * c,
      color: isSelected ? cs.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: () => widget.onCategorySelected(value),
        child: Padding(
          padding: EdgeInsets.only(left: 12 * c + depth * 14 * c, right: 8 * c),
          child: Row(
            children: [
              if (hasSubDirs)
                InkWell(
                  onTap: onToggleExpand,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16 * c,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              else
                SizedBox(width: 20 * c),
              SizedBox(width: 4 * c),
              Icon(Icons.folder, size: 14 * c, color: cs.onSurfaceVariant),
              SizedBox(width: 6 * c),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12 * c,
                    color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
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
