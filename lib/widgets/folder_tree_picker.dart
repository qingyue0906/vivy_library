import 'package:flutter/material.dart';
import '../models/category_node.dart';
import '../services/translations.dart';
import 'compact_level.dart';

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
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      constraints: const BoxConstraints(maxHeight: 240),
      child: ListView(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        children: [
          _buildNode(context, c, widget.root, 0, label: Strings.t('rootDir')),
        ],
      ),
    );
  }

  Widget _buildNode(BuildContext context, double c, CategoryNode node, int depth, {String? label}) {
    final hasSubDirs = node.subDirs.isNotEmpty;
    final isExpanded = _expanded.contains(node.path);
    final isSelected = widget.selectedPath == node.path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            widget.onSelected(node.path);
            setState(() {});
          },
          child: Container(
            height: 28 * c,
            color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
            child: Padding(
              padding: EdgeInsets.only(left: 4 * c + depth * 14 * c, right: 8 * c),
              child: Row(
                children: [
                  if (hasSubDirs)
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (isExpanded) { _expanded.remove(node.path); }
                          else { _expanded.add(node.path); }
                        });
                      },
                      child: Padding(
                        padding: EdgeInsets.all(2 * c),
                        child: Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: 14 * c, color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    SizedBox(width: 18 * c),
                  Icon(Icons.folder, size: 13 * c, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  SizedBox(width: 4 * c),
                  Expanded(
                    child: Text(
                      label ?? node.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12 * c, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasSubDirs && isExpanded)
          ...node.subDirs.map((n) => _buildNode(context, c, n, depth + 1)),
      ],
    );
  }
}