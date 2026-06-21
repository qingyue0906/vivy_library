import 'dart:io';
import 'package:flutter/material.dart';
import '../models/library_item.dart';
import '../providers/library_state.dart';
import '../services/library_scanner.dart';
import 'exe_picker_dialog.dart';
import '../models/exe_record.dart';
import 'file_properties_dialog.dart';

class FileBrowserPanel extends StatelessWidget {
  final LibraryItem item;
  final LibraryState state;
  final double height; // 新增

  const FileBrowserPanel({
    super.key,
    required this.item,
    required this.state,
    required this.height, // 新增
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      color: cs.surface,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildFileGrid()),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border:
            Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open, size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            '${item.info.title} 的内容',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface),
          ),
          const Spacer(),
          // 显示/隐藏系统文件按钮
          TextButton.icon(
            onPressed: state.toggleSystemFiles,
            icon: Icon(
              state.showSystemFiles
                  ? Icons.visibility_off
                  : Icons.visibility,
              size: 14,
            ),
            label: Text(
              state.showSystemFiles ? '隐藏 Info/Preview' : '显示 Info/Preview',
              style: const TextStyle(fontSize: 11),
            ),
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          // 关闭按钮
          InkWell(
            onTap: state.hideFileBrowser,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '✕ 关闭',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileGrid() {
    final dir = Directory(item.path);
    if (!dir.existsSync()) {
      return const Center(child: Text('文件夹不存在'));
    }

    // 读取文件列表,只取第一层(不递归),按文件名排序
    final entries = dir
        .listSync()
        .whereType<File>()
        .toList()
      ..sort((a, b) => _baseName(a.path).compareTo(_baseName(b.path)));

    // 根据 showSystemFiles 决定是否过滤 info.json 和预览图
    final visible = state.showSystemFiles
        ? entries
        : entries.where((f) {
            final name = _baseName(f.path).toLowerCase();
            final isInfo = name == 'info.json';
            final isPreview = name.startsWith('preview') &&
                previewExtensions.any((ext) => name.endsWith(ext));
            return !isInfo && !isPreview;
          }).toList();

    if (visible.isEmpty) {
      return Center(
        child: Text(
          '没有可显示的文件',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 90,  // 每个文件项最大宽度,跟下面 _buildFileItem 里的宽度对应
        mainAxisExtent: 108,     // 每行固定高度(图标+文字总高度),避免文字行数不同导致错位
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: visible.length,
      itemBuilder: (context, index) =>
          _buildFileItem(context, visible[index]),
    );
  }

  Widget _buildFileItem(BuildContext context, File file) {
    return _FileGridItem(
      file: file,
      onDoubleTap: () => _openFile(file.path),
      onRightClick: (globalPos) => _showContextMenu(context, file, globalPos),
    );
  }

  void _showContextMenu(BuildContext context, File file, Offset globalPos) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx + 1,
        globalPos.dy + 1,
      ),
      items: const [
        PopupMenuItem(
          value: 'open',
          height: 32, // 默认是 48,这里调小
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 14),
              SizedBox(width: 8),
              Text('以默认方式打开', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open_as',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.apps, size: 14),
              SizedBox(width: 8),
              Text('打开方式...', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'rename',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.drive_file_rename_outline, size: 14),
              SizedBox(width: 8),
              Text('重命名', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'locate',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 14),
              SizedBox(width: 8),
              Text('在资源管理器中显示', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'properties',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14),
              SizedBox(width: 8),
              Text('属性', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    ).then((value) async {
      if (value == null) return;
      switch (value) {
        case 'open':
          _openFile(file.path);
        case 'open_as':
          final record = await showDialog<ExeRecord>(
            context: context,
            builder: (_) => const ExePickerDialog(),
          );
          if (record != null) {
            Process.run(record.path, [file.path]);
          }
        case 'rename':
          _showRenameDialog(context, file);
        case 'locate':
          Process.run('explorer', ['/select,', file.path]);
        case 'properties':
          showDialog(
            context: context,
            builder: (_) => FilePropertiesDialog(file: file),
          );
      }
    });
  }

  void _showRenameDialog(BuildContext context, File file) {
    final currentName = _baseName(file.path);
    // 把扩展名之前的部分预选中,符合 Windows 重命名时只选中文件名、
    // 不选扩展名的习惯,方便用户直接打字替换文件名主体部分
    final dotIndex = currentName.lastIndexOf('.');
    final nameWithoutExt =
        dotIndex > 0 ? currentName.substring(0, dotIndex) : currentName;

    final ctrl = TextEditingController(text: currentName);
    ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: nameWithoutExt.length);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '新文件名',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onSubmitted: (_) => _doRename(dialogContext, file, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => _doRename(dialogContext, file, ctrl.text.trim()),
            child: const Text('重命名'),
          ),
        ],
      ),
    );
  }

  Future<void> _doRename(
      BuildContext dialogContext, File file, String newName) async {
    if (newName.isEmpty) return;
    Navigator.pop(dialogContext); // 先关闭重命名对话框

    final error = await state.renameFile(file.path, newName);
    if (error != null && dialogContext.mounted) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text('重命名失败: $error'), backgroundColor: Colors.red),
      );
    }
  }

  void _openFile(String path) {
    // Windows 下用 explorer 打开单个文件,会调用系统默认程序
    // 对应原版 os.startfile(filepath)
    Process.run('cmd', ['/c', 'start', '', path]);
  }

  String _baseName(String fullPath) {
    return fullPath.replaceAll('\\', '/').split('/').last;
  }
}

/// 单个文件图标项,带 hover 高亮反馈,效果对应 Windows 资源管理器
/// 鼠标悬停在图标上时出现的浅色背景高亮。
class _FileGridItem extends StatefulWidget {
  final File file;
  final VoidCallback onDoubleTap;
  final void Function(Offset globalPosition) onRightClick;

  const _FileGridItem({
    required this.file,
    required this.onDoubleTap,
    required this.onRightClick,
  });

  @override
  State<_FileGridItem> createState() => _FileGridItemState();
}

class _FileGridItemState extends State<_FileGridItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final name = _baseName(widget.file.path);
    final isImage =
        previewExtensions.any((ext) => name.toLowerCase().endsWith(ext));

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapUp: (details) =>
            widget.onRightClick(details.globalPosition),
        child: Tooltip(
          message: name,
          waitDuration: const Duration(milliseconds: 500),
          child: Container(
            // hover 时出现浅灰背景,效果对应 Windows 资源管理器的图标悬停反馈
            decoration: BoxDecoration(
              color: _isHovering
                  ? Colors.black.withOpacity(0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.grey.shade100,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: isImage
                      ? Image.file(widget.file,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildFileIcon(name))
                      : _buildFileIcon(name),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileIcon(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
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

    return Icon(icon, size: 36, color: color);
  }

  String _baseName(String fullPath) {
    return fullPath.replaceAll('\\', '/').split('/').last;
  }
}