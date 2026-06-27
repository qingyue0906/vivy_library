import 'dart:io';
import 'package:flutter/material.dart';
import '../models/direct_file.dart';
import '../services/settings_service.dart';
import '../services/library_scanner.dart' show previewExtensions;
import 'gif_image.dart';
import 'compact_level.dart';

class FileCard extends StatelessWidget {
  final DirectFile file;
  final double displayWidth;
  final VoidCallback onDoubleTap;
  final void Function(Offset globalPosition)? onRightClick;

  const FileCard({
    super.key,
    required this.file,
    required this.displayWidth,
    required this.onDoubleTap,
    this.onRightClick,
  });

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    final ext = file.extension;
    final isImage = previewExtensions.any((e) => e == '.$ext');
    final isGif = ext == 'gif';

    return MouseRegion(
      child: GestureDetector(
        onDoubleTap: onDoubleTap,
        onSecondaryTapUp: onRightClick != null
            ? (details) => onRightClick!(details.globalPosition)
            : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6 * c),
          ),
          padding: EdgeInsets.all(4 * c),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56 * c,
                height: 56 * c,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6 * c),
                  color: cs.surfaceContainerHighest,
                ),
                clipBehavior: Clip.antiAlias,
                child: isImage
                    ? (isGif
                        ? GifImage(
                            file: File(file.path),
                            gifMode: GifDisplayMode.static,
                            cacheWidth: 120,
                            fit: BoxFit.cover,
                            placeholderColor: cs.surfaceContainerHighest,
                          )
                        : Image.file(
                            File(file.path),
                            cacheWidth: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildFileIcon(context, ext, c),
                          ))
                    : _buildFileIcon(context, ext, c),
              ),
              SizedBox(height: 4 * c),
              Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9 * c, color: cs.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileIcon(BuildContext context, String ext, double c) {
    IconData icon;
    Color color;

    switch (ext) {
      case 'mp4' || 'mkv' || 'avi' || 'mov' || 'wmv':
        icon = Icons.video_file;
        color = Colors.blue.shade400;
      case 'mp3' || 'flac' || 'wav' || 'aac' || 'ogg':
        icon = Icons.audio_file;
        color = Colors.purple.shade400;
      case 'pdf':
        icon = Icons.picture_as_pdf;
        color = Colors.red.shade400;
      case 'zip' || 'rar' || '7z' || 'tar' || 'gz':
        icon = Icons.folder_zip;
        color = Colors.orange.shade400;
      case 'exe' || 'msi' || 'bat' || 'sh':
        icon = Icons.terminal;
        color = Colors.green.shade400;
      case 'txt' || 'md' || 'log':
        icon = Icons.article;
        color = Colors.grey.shade600;
      case 'json' || 'xml' || 'yaml' || 'toml':
        icon = Icons.data_object;
        color = Colors.teal.shade400;
      default:
        icon = Icons.insert_drive_file;
        color = Colors.grey.shade500;
    }

    return Icon(icon, size: 28 * c, color: color);
  }
}
