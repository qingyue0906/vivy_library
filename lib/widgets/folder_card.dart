import 'package:flutter/material.dart';
import '../models/category_node.dart';
import 'compact_level.dart';

/// 文件夹卡片，模仿 Windows 资源管理器大图标风格。
/// 单击：选中文件夹（右侧显示其 info）；双击：进入文件夹。
class FolderCard extends StatelessWidget {
  final CategoryNode node;
  final double displayWidth;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final void Function(Offset globalPosition) onRightClick;

  const FolderCard({
    super.key,
    required this.node,
    required this.displayWidth,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onRightClick,
  });

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    final selectedColor = cs.brightness == Brightness.light
        ? const Color(0xFF7B49E0)
        : cs.primary;
    return GestureDetector(
      onSecondaryTapUp: (details) => onRightClick(details.globalPosition),
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        borderRadius: BorderRadius.circular(4 * c),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 6 * c, horizontal: 4 * c),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primaryContainer.withValues(alpha: 0.4)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4 * c),
            border: Border.all(
              color: isSelected ? selectedColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder, size: 48 * c, color: Colors.amber.shade400),
              SizedBox(height: 4 * c),
              Text(
                node.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11 * c,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
