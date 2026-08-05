import 'package:flutter/material.dart';
import '../models/category_node.dart';
import '../services/translations.dart';
import 'smooth_scroll.dart';
import 'tree_row.dart';

class FolderTreePicker extends StatefulWidget {
  final CategoryNode root;
  final String? selectedPath;
  final ValueChanged<String> onSelected;

  const FolderTreePicker({
    super.key,
    required this.root,
    required this.selectedPath,
    required this.onSelected,
  });

  @override
  State<FolderTreePicker> createState() => _FolderTreePickerState();
}

class _FolderTreePickerState extends State<FolderTreePicker> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _expanded.add(widget.root.path);
    if (widget.selectedPath != null) {
      final ancestors = widget.root.ancestorPaths(widget.selectedPath!);
      _expanded.addAll(ancestors);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SmoothScroll(
        builder: (context, controller, physics) => ListView(
          controller: controller,
          physics: physics,
          padding: EdgeInsets.zero,
          children: [
            _buildNode(context, widget.root, 0, label: Strings.t('rootDir')),
          ],
        ),
      ),
    );
  }

  Widget _buildNode(BuildContext context, CategoryNode node, int depth,
      {String? label, bool isLast = true, int parentLastChain = 0}) {
    final hasSubDirs = node.subDirs.isNotEmpty;
    final isExpanded = _expanded.contains(node.path);
    final isSelected = widget.selectedPath == node.path;
    final lastChain = isLast ? parentLastChain + 1 : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TreeRow(
          label: label ?? node.name,
          icon: hasSubDirs && isExpanded ? Icons.folder_open : Icons.folder,
          isSelected: isSelected,
          hasSubDirs: hasSubDirs,
          isExpanded: isExpanded,
          depth: depth,
          lastChain: lastChain,
          onTap: () {
            widget.onSelected(node.path);
            setState(() {});
          },
          onToggleExpand: hasSubDirs
              ? () {
                  setState(() {
                    if (isExpanded) {
                      _expanded.remove(node.path);
                    } else {
                      _expanded.add(node.path);
                    }
                  });
                }
              : null,
        ),
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
}
