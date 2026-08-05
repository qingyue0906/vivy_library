import 'package:flutter/material.dart';
import '../models/category_node.dart';
import '../services/translations.dart';
import 'compact_level.dart';
import 'smooth_scroll.dart';
import 'tree_row.dart';

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
  final bool dragSelectEnabled; // 按住滑动快捷切换选中（设置开关）

  const CategoryPanel({
    super.key,
    required this.root,
    required this.selectedCategoryPath,
    required this.onCategorySelected,
    required this.expandedPaths,
    required this.onToggleExpand,
    this.backgroundOpacity = 1.0,
    this.dragSelectEnabled = false,
  });

  @override
  State<CategoryPanel> createState() => _CategoryPanelState();
}

class _CategoryPanelState extends State<CategoryPanel> {
  /// 按住滑动的拖选会话：按下置 true，抬起/取消置 false。
  /// 行内 MouseRegion 依据该值决定指针划入时是否选中。
  final ValueNotifier<bool> _dragSelectActive = ValueNotifier(false);

  @override
  void dispose() {
    _dragSelectActive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = CompactLevel.of(context);
    return Material(
      color: cs.surfaceContainerLow.withValues(alpha: widget.backgroundOpacity),
      child: Listener(
        onPointerDown: (_) => _dragSelectActive.value = true,
        onPointerUp: (_) => _dragSelectActive.value = false,
        onPointerCancel: (_) => _dragSelectActive.value = false,
        child: SmoothScroll(
          builder: (context, controller, physics) => ListView(
            controller: controller,
            physics: physics,
            padding: EdgeInsets.fromLTRB(0, 2 * c, 0, 4 * c),
            children: [
              // Part 1: 全部项目 + 根目录
              _buildItem(context,
                  label: Strings.t('allItems'), value: null, depth: 0, node: null,
                  icon: Icons.apps),
              _buildItem(context,
                  label: Strings.t('rootDir'), value: widget.root.path, depth: 0, node: widget.root,
                  icon: Icons.folder_open),
              Divider(height: 1 * c, thickness: 1, color: cs.outlineVariant),
              // Part 2: 根级直接文件夹展开树
              ...widget.root.subDirs.asMap().entries.map((e) => _buildNode(
                  context, e.value, 0,
                  isLast: e.key == widget.root.subDirs.length - 1,
                  parentLastChain: 0)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNode(BuildContext context, CategoryNode node, int depth,
      {required bool isLast, required int parentLastChain}) {
    final hasSubDirs = node.subDirs.isNotEmpty;
    final isExpanded = widget.expandedPaths.contains(node.path);
    final lastChain = isLast ? parentLastChain + 1 : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildItem(context,
            label: node.name,
            value: node.path,
            depth: depth,
            node: node,
            hasSubDirs: hasSubDirs,
            isExpanded: isExpanded,
            lastChain: lastChain),
        if (hasSubDirs)
          ExpandableChildren(
            expanded: isExpanded,
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...node.subDirs.asMap().entries.map((e) => _buildNode(
                    context, e.value, depth + 1,
                    isLast: e.key == node.subDirs.length - 1,
                    parentLastChain: lastChain)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required String label,
    required String? value,
    required int depth,
    required CategoryNode? node,
    IconData icon = Icons.folder,
    bool hasSubDirs = false,
    bool isExpanded = false,
    int lastChain = 0,
  }) {
    final isSelected = widget.selectedCategoryPath == value;
    return TreeRow(
      label: label,
      icon: hasSubDirs
          ? (isExpanded ? Icons.folder_open : Icons.folder)
          : icon,
      isSelected: isSelected,
      hasSubDirs: hasSubDirs,
      isExpanded: isExpanded,
      depth: depth,
      lastChain: lastChain,
      onTap: () => widget.onCategorySelected(value),
      onToggleExpand: hasSubDirs
          ? () => widget.onToggleExpand(node!.path)
          : null,
      dragSelect: widget.dragSelectEnabled ? _dragSelectActive : null,
    );
  }
}
