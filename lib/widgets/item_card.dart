import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/library_item.dart';
import '../services/settings_service.dart';
import 'compact_level.dart';
import 'gif_image.dart';

class ItemCard extends StatelessWidget {
  final LibraryItem item;
  final double aspectRatio;
  final double displayWidth;
  final double displayHeight;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCtrlTap;
  final VoidCallback onShiftTap;
  final void Function(Offset globalPosition) onRightClick;
  final GifDisplayMode gifMode;

  const ItemCard({
    super.key,
    required this.item,
    this.aspectRatio = 4 / 3,
    this.displayWidth = 150,
    this.displayHeight = 112.5,
    required this.isSelected,
    required this.onTap,
    required this.onCtrlTap,
    required this.onShiftTap,
    required this.onRightClick,
    this.gifMode = GifDisplayMode.hover,
  });

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    final selectedColor = cs.brightness == Brightness.light
        ? const Color(0xFF7B49E0)
        : cs.primary;
    final radius = BorderRadius.circular(4 * c);
    return GestureDetector(
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
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: displayHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: radius,
                image: null,
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: isSelected ? selectedColor : cs.outlineVariant,
                  width: isSelected ? 1.5 : 0.5,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPreviewImage(context, c),
                  if (item.info.star)
                    Positioned(
                      top: 2 * c,
                      right: 2 * c,
                      child: Container(
                        padding: EdgeInsets.all(2 * c),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10 * c),
                        ),
                        child: Icon(Icons.star, size: 12 * c, color: Colors.amber),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildInfo(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewImage(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    if (item.previewPath == null) {
      return Center(
        child: Icon(Icons.image_not_supported, size: 20 * c, color: cs.onSurfaceVariant),
      );
    }
    final cacheW = ((displayWidth * 2) ~/ 100 * 100).clamp(100, 800).toInt();
    final isGif = GifImage.isAnimatedFile(item.previewPath!);
    final errorWidget = Center(
      child: Icon(Icons.broken_image, size: 20 * c, color: cs.onSurfaceVariant),
    );
    if (isGif) {
      return GifImage(
        file: File(item.previewPath!),
        gifMode: gifMode,
        cacheWidth: cacheW,
        fit: BoxFit.cover,
        placeholderColor: Colors.transparent,
        errorBuilder: (_) => errorWidget,
      );
    }
    return Image.file(
      File(item.previewPath!),
      cacheWidth: cacheW,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => errorWidget,
    );
  }

  Widget _buildInfo(double c) {
    return Padding(
      padding: EdgeInsets.only(top: 4 * c, left: 2 * c, right: 2 * c),
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
