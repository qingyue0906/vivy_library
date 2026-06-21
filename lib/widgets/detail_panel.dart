import 'dart:io';
import 'package:flutter/material.dart';
import '../models/library_item.dart';

class DetailPanel extends StatelessWidget {
  final LibraryItem? item;

  const DetailPanel({super.key, this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerLow,
      child: item == null ? _buildEmpty() : _buildDetail(context, item!),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Text(
        '选择一个项目\n查看详情',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      ),
    );
  }

  Widget _buildDetail(BuildContext context, LibraryItem item) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (item.previewPath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(item.previewPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),

        const SizedBox(height: 16),

        Text(
          item.info.title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 8),

        _buildRow(context, '分类', item.category),
        _buildRow(context, '类型', item.info.type),
        _buildRow(context, '分级', item.info.contentRating),
        _buildRow(context, '评分', '${item.info.rating / 2} / 5'),
        if (item.info.creator != null)
          _buildRow(context, '创建者', item.info.creator!),
        if (item.info.description != '无描述')
          _buildRow(context, '描述', item.info.description),
        if (item.info.classes.isNotEmpty)
          _buildRow(context, '标签分类', item.info.classes.join('、')),
        if (item.info.tags.isNotEmpty)
          _buildRow(context, '标签', item.info.tags.join('、')),

        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),

        _buildRow(context, '大小', _formatSize(item.sizeInBytes)),
        _buildRow(context, '修改时间', _formatDate(item.modifiedTime)),
        _buildRow(context, '路径', item.path),
      ],
    );
  }

  Widget _buildRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: cs.onSurface),
            ),
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
