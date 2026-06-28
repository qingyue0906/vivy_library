import 'dart:io';
import 'package:flutter/material.dart';
import '../services/translations.dart';

/// 简易文件属性对话框,展示路径/大小/创建时间/修改时间。
/// 不依赖系统原生属性窗口,避免 Windows Shell 在不同版本上的兼容性问题。
class FilePropertiesDialog extends StatelessWidget {
  final FileSystemEntity file;

  const FilePropertiesDialog({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Strings.t('propTitle'), style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 360,
        child: FutureBuilder<_SizeAndStat>(
          future: _computeSizeAndStat(file),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final stat = snapshot.data!.stat;
            final size = snapshot.data!.size;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRow(Strings.t('propFileName'), _baseName(file.path)),
                _buildRow(Strings.t('propLocation'), _dirName(file.path)),
                _buildRow(Strings.t('propSize'), _formatSize(size)),
                _buildRow(Strings.t('propModified'), _formatDate(stat.modified)),
                _buildRow(Strings.t('propAccessed'), _formatDate(stat.accessed)),
                // 注意:Windows 上 FileStat 没有单独的"创建时间"字段,
                // changed 在 Windows 上实际反映的是文件元数据变化时间,
                // 不完全等价于资源管理器属性框里的"创建时间",这里如实标注用途
                _buildRow(Strings.t('propChanged'), _formatDate(stat.changed)),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(Strings.t('close')),
        ),
      ],
    );
  }

  /// 计算实体大小：文件直接 stat；目录递归累加所有文件大小。
  /// 时间字段统一用实体自身的 FileStat（目录的时间戳是正确的）。
  Future<_SizeAndStat> _computeSizeAndStat(FileSystemEntity entity) async {
    final stat = await entity.stat();
    if (entity is Directory) {
      int total = 0;
      try {
        for (final e in entity.listSync(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              total += e.statSync().size;
            } catch (_) {}
          }
        }
      } catch (_) {}
      return _SizeAndStat(total, stat);
    }
    return _SizeAndStat(stat.size, stat);
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

class _SizeAndStat {
  final int size;
  final FileStat stat;
  const _SizeAndStat(this.size, this.stat);
}