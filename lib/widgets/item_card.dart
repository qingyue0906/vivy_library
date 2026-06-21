import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/library_item.dart';

class ItemCard extends StatelessWidget {
  final LibraryItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCtrlTap;
  final VoidCallback onShiftTap;
  final void Function(Offset globalPosition) onRightClick;

  const ItemCard({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onCtrlTap,
    required this.onShiftTap,
    required this.onRightClick,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: Colors.deepPurple.shade400, width: 2.5)
            : BorderSide.none,
      ),
      child: GestureDetector(
        onSecondaryTapUp: (details) => onRightClick(details.globalPosition),
        child: InkWell(
          onTap: () {
            final isCtrl = HardwareKeyboard.instance.isControlPressed;
            final isShift = HardwareKeyboard.instance.isShiftPressed;
            if (isShift) {
              onShiftTap();
            } else if (isCtrl) {
              onCtrlTap();
            } else {
              onTap();
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min, // 整张卡片只占用内容实际需要的高度
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // AspectRatio 是 Flutter 内置机制,自己保证不会有任何溢出,
              // 不再需要我们手动算任何数值
              AspectRatio(
                aspectRatio: 3 / 2,
                child: _buildPreviewImage(context),
              ),
              _buildInfo(), // 不再固定高度,让文字内容自己决定需要多高
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewImage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (item.previewPath == null) {
      return Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.image_not_supported, color: cs.onSurfaceVariant),
      );
    }
    return Image.file(
      File(item.previewPath!),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.broken_image, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        item.info.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}