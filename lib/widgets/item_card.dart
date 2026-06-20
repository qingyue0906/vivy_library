import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HardwareKeyboard 用于检测 Ctrl 键
import '../models/library_item.dart';

class ItemCard extends StatelessWidget {
  final LibraryItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCtrlTap;       // Ctrl+点击:多选
  final VoidCallback onShiftTap; // 新增
  final void Function(Offset globalPosition) onRightClick;  // 右键:弹出菜单(菜单本身在父级处理)

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
        // onSecondaryTapUp:鼠标右键抬起,details 里有点击位置坐标
        // 坐标用于在正确位置弹出上下文菜单
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 65, child: _buildPreviewImage()),
              Expanded(flex: 35, child: _buildInfo()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewImage() {
    if (item.previewPath == null) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }
    return Image.file(
      File(item.previewPath!),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }

  Widget _buildInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.info.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            item.category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}