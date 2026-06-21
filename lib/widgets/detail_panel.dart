import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../models/library_item.dart';

class DetailPanel extends StatelessWidget {
  final LibraryItem? item;

  const DetailPanel({super.key, this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerLow,
      child: item == null ? _buildEmpty(cs) : _buildDetail(context, item!),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Text(
        '选择一个项目\n查看详情',
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
      ),
    );
  }

  Widget _buildDetail(BuildContext context, LibraryItem item) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (item.previewPath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(item.previewPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          item.info.title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 6),
        _buildRow(context, '分类', item.category),
        _buildRow(context, '类型', item.info.type),
        _buildRow(context, '分级', item.info.contentRating),
        _buildRow(context, '评分', '${item.info.rating / 2} / 5'),
        if (item.info.creator != null)
          _buildRow(context, '创建者', item.info.creator!),
        if (item.info.description != '无描述')
          _buildDescriptionRow(context, '描述', item.info.description),
        if (item.info.classes.isNotEmpty)
          _buildRow(context, '标签分类', item.info.classes.join('、')),
        if (item.info.tags.isNotEmpty)
          _buildRow(context, '标签', item.info.tags.join('、')),
        const SizedBox(height: 6),
        const Divider(height: 1),
        const SizedBox(height: 6),
        _buildRow(context, '大小', _formatSize(item.sizeInBytes)),
        _buildRow(context, '修改时间', _formatDate(item.modifiedTime)),
        _buildRow(context, '路径', item.path),
      ],
    );
  }

  Widget _buildDescriptionRow(BuildContext context, String label, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          Expanded(child: _buildUrlText(context, text)),
        ],
      ),
    );
  }

  Widget _buildUrlText(BuildContext context, String text) {
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
        style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () => _openUrl(url),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(style: TextStyle(fontSize: 11, color: cs.onSurface), children: spans),
    );
  }

  void _openUrl(String url) {
    Process.run('cmd', ['/c', 'start', url]);
  }

  Widget _buildRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 11, color: cs.onSurface)),
          ),
        ],
      ),
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
