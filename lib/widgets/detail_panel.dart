import 'dart:io';
import 'package:flutter/material.dart';
import '../models/library_item.dart';

class DetailPanel extends StatelessWidget {
  final LibraryItem? item; // null 表示没有选中任何项目

  const DetailPanel({super.key, this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade50,
      child: item == null ? _buildEmpty() : _buildDetail(item!),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Text(
        '选择一个项目\n查看详情',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey, fontSize: 13),
      ),
    );
  }

  Widget _buildDetail(LibraryItem item) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 预览图
        if (item.previewPath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(item.previewPath!),
              fit: BoxFit.cover,
              // errorBuilder 同卡片里的处理
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),

        const SizedBox(height: 16),

        // 标题
        Text(
          item.info.title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 8),

        // 各字段逐行显示
        _buildRow('分类', item.category),
        _buildRow('类型', item.info.type),
        _buildRow('分级', item.info.contentRating),
        _buildRow('评分', '${item.info.rating / 2} / 5'),
        if (item.info.creator != null)
          _buildRow('创建者', item.info.creator!),
        if (item.info.description != '无描述')
          _buildRow('描述', item.info.description),
        if (item.info.classes.isNotEmpty)
          _buildRow('标签分类', item.info.classes.join('、')),
        if (item.info.tags.isNotEmpty)
          _buildRow('标签', item.info.tags.join('、')),

        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),

        // 文件信息
        _buildRow('大小', _formatSize(item.sizeInBytes)),
        _buildRow('修改时间', _formatDate(item.modifiedTime)),
        _buildRow('路径', item.path),
      ],
    );
  }

  // 用 if (...) widget 这种写法在 children 列表里条件渲染,
  // 等价于 Python 里 [widget] if condition else [] 的列表推导式,
  // 是 Flutter 里最常用的"某个字段有值才显示对应行"的写法。
  Widget _buildRow(String label, String value) {
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
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
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