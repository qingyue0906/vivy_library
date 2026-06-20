import 'dart:io';
import 'package:flutter/material.dart';

/// 简易文件属性对话框,展示路径/大小/创建时间/修改时间。
/// 不依赖系统原生属性窗口,避免 Windows Shell 在不同版本上的兼容性问题。
class FilePropertiesDialog extends StatelessWidget {
  final File file;

  const FilePropertiesDialog({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    // FutureBuilder 再次派上用场:stat() 是异步操作,
    // 对话框打开瞬间先显示 loading,数据到手后再渲染内容。
    return AlertDialog(
      title: const Text('属性', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 360,
        child: FutureBuilder<FileStat>(
          future: file.stat(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final stat = snapshot.data!;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRow('文件名', _baseName(file.path)),
                _buildRow('位置', _dirName(file.path)),
                _buildRow('大小', _formatSize(stat.size)),
                _buildRow('修改时间', _formatDate(stat.modified)),
                _buildRow('访问时间', _formatDate(stat.accessed)),
                // 注意:Windows 上 FileStat 没有单独的"创建时间"字段,
                // changed 在 Windows 上实际反映的是文件元数据变化时间,
                // 不完全等价于资源管理器属性框里的"创建时间",这里如实标注用途
                _buildRow('元数据变化时间', _formatDate(stat.changed)),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SelectableText(
              // 用 SelectableText 而不是 Text,方便用户复制路径之类的信息,
              // 这是属性对话框里一个很实用的小细节
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _baseName(String fullPath) =>
      fullPath.replaceAll('\\', '/').split('/').last;

  String _dirName(String fullPath) {
    final segments = fullPath.replaceAll('\\', '/').split('/')..removeLast();
    return segments.join('\\');
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
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}