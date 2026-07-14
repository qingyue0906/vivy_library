import 'dart:io';
import 'package:flutter/material.dart';
import '../models/direct_file.dart';
import '../services/settings_service.dart';
import '../services/library_scanner.dart' show previewExtensions;
import '../theme/design_tokens.dart';
import 'gif_image.dart';
import 'compact_level.dart';

/// 中间区域的文件卡片。模仿 Windows 资源管理器大图标风格。
/// 单击：选中文件（右侧显示其信息）；双击：打开文件。
///
/// 用手动双击检测替代 GestureDetector.onDoubleTap，避免 Flutter 为区分
/// 单击/双击等待 ~300ms 超时导致的"点击卡顿"。单击立即响应，
/// 300ms 内第二次点击触发双击（与 FolderCard 一致）。
class FileCard extends StatefulWidget {
  final DirectFile file;
  final double displayWidth;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback onDoubleTap;
  final void Function(Offset globalPosition)? onRightClick;
  final GridDisplayMode displayMode;

  const FileCard({
    super.key,
    required this.file,
    required this.displayWidth,
    this.isSelected = false,
    this.onTap,
    required this.onDoubleTap,
    this.onRightClick,
    this.displayMode = GridDisplayMode.loose,
  });

  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  DateTime? _lastTapTime;
  bool _isHovered = false;

  void _handleTap() {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300) {
      _lastTapTime = null;
      widget.onDoubleTap();
    } else {
      _lastTapTime = now;
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    final tokens = AppDesignTokens.of(context);
    if (widget.displayMode == GridDisplayMode.list) {
      return _buildListRow(c, cs, tokens);
    }
    final ext = widget.file.extension;
    final isImage = previewExtensions.any((e) => e == '.$ext');
    final radius = BorderRadius.circular(tokens.cardRadius * c);
    final isSel = widget.isSelected;
    final isHov = _isHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _handleTap,
        onSecondaryTapUp: widget.onRightClick != null
            ? (details) => widget.onRightClick!(details.globalPosition)
            : null,
        child: AnimatedContainer(
          duration: tokens.duration(MotionDurations.fast),
          curve: MotionCurves.standard,
          padding: EdgeInsets.all(6 * c),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: isSel
                  ? cs.primary
                  : (isHov ? cs.primary.withValues(alpha: 0.4) : Colors.transparent),
              width: isSel ? 2.0 * c : 1.0 * c,
            ),
            color: isSel
                ? cs.primaryContainer.withValues(alpha: 0.3)
                : (isHov ? cs.primary.withValues(alpha: 0.05) : Colors.transparent),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 58 * c,
                height: 58 * c,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tokens.cardRadius * 0.7 * c),
                  color: cs.surfaceContainerHighest,
                ),
                clipBehavior: Clip.antiAlias,
                child: isImage
                    ? GifImage(
                        file: File(widget.file.path),
                        gifMode: GifDisplayMode.static,
                        cacheWidth: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_) => _buildFileIcon(context, ext, c),
                      )
                    : _buildFileIcon(context, ext, c),
              ),
              SizedBox(height: 5 * c),
              Text(
                widget.file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10 * c,
                  height: 1.2,
                  color: cs.onSurface,
                ),
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

  Widget _buildListRow(double c, ColorScheme cs, AppDesignTokens tokens) {
    final radius = BorderRadius.circular(tokens.buttonRadius * c);
    final isSel = widget.isSelected;
    final isHov = _isHovered;
    final ext = widget.file.extension;
    final isImage = previewExtensions.any((e) => e == '.$ext');
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _handleTap,
        onSecondaryTapUp: widget.onRightClick != null
            ? (details) => widget.onRightClick!(details.globalPosition)
            : null,
        child: AnimatedContainer(
          duration: tokens.duration(MotionDurations.fast),
          curve: MotionCurves.standard,
          height: 46 * c,
          padding: EdgeInsets.symmetric(vertical: 5 * c, horizontal: 6 * c),
          decoration: BoxDecoration(
            color: isSel
                ? cs.primaryContainer.withValues(alpha: 0.35)
                : (isHov ? cs.primary.withValues(alpha: 0.06) : Colors.transparent),
            borderRadius: radius,
            border: Border.all(
              color: isSel
                  ? cs.primary
                  : (isHov ? cs.primary.withValues(alpha: 0.4) : Colors.transparent),
              width: isSel ? 1.5 * c : 1.0 * c,
            ),
          ),
          child: Row(
            children: [
              SizedBox(width: 4 * c),
              SizedBox(
                width: 32 * c,
                height: 32 * c,
                child: isImage
                    ? GifImage(
                        file: File(widget.file.path),
                        gifMode: GifDisplayMode.static,
                        cacheWidth: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_) => _buildFileIcon(context, ext, c),
                      )
                    : _buildFileIcon(context, ext, c),
              ),
              SizedBox(width: 10 * c),
              Expanded(
                child: Text(
                  widget.file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5 * c,
                    fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                    color: cs.onSurface,
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
