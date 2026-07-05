import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../models/item_info.dart';
import '../models/library_item.dart';
import '../models/category_node.dart';
import '../models/direct_file.dart';
import '../models/goto_entry.dart';
import '../services/library_scanner.dart' show previewExtensions;
import '../services/translations.dart';
import 'compact_level.dart';
import 'smooth_scroll.dart';

class DetailPanel extends StatelessWidget {
  final LibraryItem? item;
  final ItemInfo? effectiveInfo; // 有效 info（含父文件夹继承 + 硬编码保底）
  final CategoryNode? folder;
  final DirectFile? file;
  final double backgroundOpacity;
  final void Function(GotoEntry entry)? onGotoTap;
  final void Function(String query)? onSearchByQuery;

  const DetailPanel({
    super.key,
    this.item,
    this.effectiveInfo,
    this.folder,
    this.file,
    this.backgroundOpacity = 1.0,
    this.onGotoTap,
    this.onSearchByQuery,
  });

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerLow.withValues(alpha: backgroundOpacity),
      child: _buildContent(context, c),
    );
  }

  Widget _buildContent(BuildContext context, double c) {
    if (item != null) return _buildItemDetail(context, c, item!);
    if (folder != null) return _buildFolderDetail(context, c, folder!);
    if (file != null) return _buildFileDetail(context, c, file!);
    return _buildEmpty(context, c);
  }

  Widget _buildEmpty(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        Strings.t('selectHint'),
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12 * c),
      ),
    );
  }

  Widget _buildItemDetail(BuildContext context, double c, LibraryItem item) {
    final info = effectiveInfo ?? item.info;
    return SmoothScroll(
      builder: (context, controller, physics) => ListView(
        controller: controller,
        physics: physics,
        padding: EdgeInsets.all(12 * c),
        children: [
        if (item.previewPath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(4 * c),
            child: Image.file(
              File(item.previewPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        SizedBox(height: 12 * c),
        Center(
          child: SelectableText(
            info.title,
            style: TextStyle(fontSize: 13 * c, fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(height: 8 * c),
        Divider(height: 1 * c),
        SizedBox(height: 6 * c),
        _buildDescriptionRow(context, c, Strings.t('description'), info.description),
        _buildRow(context, c, Strings.t('creator'), info.creator ?? ''),
        _buildRow(context, c, Strings.t('type'), info.type),
        _buildRow(context, c, Strings.t('contentRating'), info.contentRating),
        _buildRow(context, c, Strings.t('rating'), '${info.rating / 2} / 5'),
        _buildRow(context, c, Strings.t('classLabel'), info.classes.join('、'), valueWidget: _chipText(context, c, info.classes, 'class')),
        _buildRow(context, c, Strings.t('tags'), info.tags.join('、'), valueWidget: _chipText(context, c, info.tags, 'tags')),
        _buildRow(context, c, Strings.t('folderLabel'), item.category),
        SizedBox(height: 6 * c),
        Divider(height: 1 * c),
        SizedBox(height: 6 * c),
        _buildRow(context, c, Strings.t('size'), _formatSize(item.sizeInBytes)),
        _buildRow(context, c, Strings.t('modifiedTime'), _formatDate(item.modifiedTime)),
        _buildRow(context, c, Strings.t('path'), item.path),
        if (info.goto.isNotEmpty) ...[
          SizedBox(height: 8 * c),
          Divider(height: 1 * c),
          SizedBox(height: 6 * c),
          _buildGotoSection(context, c, info.goto),
        ],
      ],
      ),
    );
  }

  Widget _buildFolderDetail(BuildContext context, double c, CategoryNode folder) {
    final info = folder.info;
    final hasInfo = info != null;
    return SmoothScroll(
      builder: (context, controller, physics) => ListView(
        controller: controller,
        physics: physics,
        padding: EdgeInsets.all(12 * c),
        children: [
          Icon(Icons.folder, size: 48 * c, color: Colors.amber.shade400),
        SizedBox(height: 8 * c),
        Center(
          child: SelectableText(
            hasInfo ? info.title : folder.name,
            style: TextStyle(fontSize: 13 * c, fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(height: 8 * c),
        Divider(height: 1 * c),
        SizedBox(height: 6 * c),
        if (hasInfo) ...[
          _buildDescriptionRow(context, c, Strings.t('description'), info.description),
          _buildRow(context, c, Strings.t('creator'), info.creator ?? ''),
          _buildRow(context, c, Strings.t('type'), info.type),
          _buildRow(context, c, Strings.t('contentRating'), info.contentRating),
          _buildRow(context, c, Strings.t('rating'), '${info.rating / 2} / 5'),
          _buildRow(context, c, Strings.t('classLabel'), info.classes.join('、'), valueWidget: _chipText(context, c, info.classes, 'class')),
          _buildRow(context, c, Strings.t('tags'), info.tags.join('、'), valueWidget: _chipText(context, c, info.tags, 'tags')),
          SizedBox(height: 6 * c),
          Divider(height: 1 * c),
          SizedBox(height: 6 * c),
        ],
        _buildRow(context, c, Strings.t('path'), folder.path),
        _buildRow(context, c, Strings.t('size'), _formatSize(folder.sizeInBytes)),
        _buildRow(context, c, Strings.t('subfolderCount'), '${folder.subDirs.length}'),
        _buildRow(context, c, Strings.t('directItemCount'), '${folder.items.length}'),
      ],
      ),
    );
  }

  Widget _buildFileDetail(BuildContext context, double c, DirectFile file) {
    final ext = file.extension;
    final isImage = previewExtensions.any((e) => e == '.$ext');

    return SmoothScroll(
      builder: (context, controller, physics) => ListView(
        controller: controller,
        physics: physics,
        padding: EdgeInsets.all(12 * c),
        children: [
          if (isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(4 * c),
              child: Image.file(
                File(file.path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildFileIcon(context, ext, c),
              ),
            )
          else
            Center(
              child: Icon(_fileIcon(ext), size: 64 * c, color: _fileColor(ext)),
            ),
          SizedBox(height: 12 * c),
          Center(
            child: SelectableText(
              file.name,
              style: TextStyle(fontSize: 13 * c, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(height: 8 * c),
          Divider(height: 1 * c),
          SizedBox(height: 6 * c),
          _buildRow(context, c, Strings.t('extension'), ext.isNotEmpty ? '.$ext' : Strings.t('noExt')),
          _buildRow(context, c, Strings.t('size'), _formatSize(file.sizeInBytes)),
          _buildRow(context, c, Strings.t('modifiedTime'), _formatDate(file.modifiedTime)),
          SizedBox(height: 6 * c),
          Divider(height: 1 * c),
          SizedBox(height: 6 * c),
          _buildRow(context, c, Strings.t('path'), file.path),
        ],
      ),
    );
  }

  IconData _fileIcon(String ext) {
    switch (ext) {
      case 'mp4' || 'mkv' || 'avi' || 'mov' || 'wmv': return Icons.video_file;
      case 'mp3' || 'flac' || 'wav' || 'aac' || 'ogg': return Icons.audio_file;
      case 'pdf': return Icons.picture_as_pdf;
      case 'zip' || 'rar' || '7z' || 'tar' || 'gz': return Icons.folder_zip;
      case 'exe' || 'msi' || 'bat' || 'sh': return Icons.terminal;
      case 'txt' || 'md' || 'log': return Icons.article;
      case 'json' || 'xml' || 'yaml' || 'toml': return Icons.data_object;
      default: return Icons.insert_drive_file;
    }
  }

  Color _fileColor(String ext) {
    switch (ext) {
      case 'mp4' || 'mkv' || 'avi' || 'mov' || 'wmv': return Colors.blue.shade400;
      case 'mp3' || 'flac' || 'wav' || 'aac' || 'ogg': return Colors.purple.shade400;
      case 'pdf': return Colors.red.shade400;
      case 'zip' || 'rar' || '7z' || 'tar' || 'gz': return Colors.orange.shade400;
      case 'exe' || 'msi' || 'bat' || 'sh': return Colors.green.shade400;
      case 'txt' || 'md' || 'log': return Colors.grey.shade600;
      case 'json' || 'xml' || 'yaml' || 'toml': return Colors.teal.shade400;
      default: return Colors.grey.shade500;
    }
  }

  Widget _buildFileIcon(BuildContext context, String ext, double c) {
    return Icon(_fileIcon(ext), size: 64 * c, color: _fileColor(ext));
  }

  Widget _buildGotoSection(BuildContext context, double c, List<GotoEntry> goto) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 6 * c),
          child: Text(
            Strings.t('relatedItems'),
            style: TextStyle(
              fontSize: 11 * c,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Wrap(
          spacing: 6 * c,
          runSpacing: 4 * c,
          children: goto.map((entry) {
            return ActionChip(
              label: Text(entry.name, style: TextStyle(fontSize: 11 * c)),
              avatar: Icon(Icons.link, size: 12 * c),
              onPressed: () => onGotoTap?.call(entry),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.symmetric(horizontal: 4 * c),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDescriptionRow(BuildContext context, double c, String label, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: 6 * c),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56 * c,
            child: Text(label, style: TextStyle(fontSize: 11 * c, color: cs.onSurfaceVariant)),
          ),
          Expanded(child: _buildUrlText(context, c, text)),
        ],
      ),
    );
  }

  Widget _buildUrlText(BuildContext context, double c, String text) {
    final cs = Theme.of(context).colorScheme;
    final urlRegex = RegExp(r'https?://[^\s]+');
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in urlRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: const TextStyle(color: Colors.blue),
        recognizer: TapGestureRecognizer()..onTap = () => _openUrl(url),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return SelectableText.rich(
      TextSpan(style: TextStyle(fontSize: 11 * c, color: cs.onSurface), children: spans),
    );
  }

  void _openUrl(String url) {
    Process.run('cmd', ['/c', 'start', url]);
  }

  Widget _buildRow(BuildContext context, double c, String label, String value, {Widget? valueWidget}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: 5 * c),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56 * c,
            child: Text(label, style: TextStyle(fontSize: 11 * c, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: valueWidget ?? SelectableText(value, style: TextStyle(fontSize: 11 * c, color: cs.onSurface)),
          ),
        ],
      ),
    );
  }

  Widget _chipText(BuildContext context, double c, List<String> values, String field) {
    final cs = Theme.of(context).colorScheme;
    if (onSearchByQuery == null || values.isEmpty) {
      return SelectableText(values.join(', '), style: TextStyle(fontSize: 11 * c, color: cs.onSurface));
    }
    final spans = <InlineSpan>[];
    for (int i = 0; i < values.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(text: ', ', style: TextStyle(fontSize: 11 * c, color: cs.onSurface)));
      }
      spans.add(TextSpan(
        text: values[i],
        style: TextStyle(fontSize: 11 * c, color: cs.primary),
        recognizer: TapGestureRecognizer()..onTap = () => onSearchByQuery!('$field:${values[i]}'),
      ));
    }
    return SelectableText.rich(
      TextSpan(style: TextStyle(fontSize: 11 * c, color: cs.onSurface), children: spans),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
