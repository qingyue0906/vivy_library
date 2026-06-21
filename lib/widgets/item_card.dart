import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/library_item.dart';
import 'compact_level.dart';

class ItemCard extends StatelessWidget {
  final LibraryItem item;
  final double aspectRatio;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCtrlTap;
  final VoidCallback onShiftTap;
  final void Function(Offset globalPosition) onRightClick;

  const ItemCard({
    super.key,
    required this.item,
    this.aspectRatio = 4 / 3,
    required this.isSelected,
    required this.onTap,
    required this.onCtrlTap,
    required this.onShiftTap,
    required this.onRightClick,
  });

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4 * c),
        side: isSelected
            ? BorderSide(color: cs.primary, width: 1.5)
            : BorderSide(color: cs.outlineVariant, width: 0.5),
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
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: aspectRatio,
                child: _buildPreviewImage(context, c),
              ),
              _buildInfo(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewImage(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    if (item.previewPath == null) {
      return Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.image_not_supported, size: 20 * c, color: cs.onSurfaceVariant),
      );
    }
    return Image.file(
      File(item.previewPath!),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.broken_image, size: 20 * c, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildInfo(double c) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6 * c, vertical: 5 * c),
      child: Text(
        item.info.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11 * c, fontWeight: FontWeight.w500),
      ),
    );
  }
}
