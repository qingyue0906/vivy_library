import 'dart:io';
import 'package:flutter/material.dart';
import '../models/library_item.dart';
import '../providers/library_state.dart';
import '../services/library_scanner.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import 'exe_picker_dialog.dart';
import '../models/exe_record.dart';
import 'file_properties_dialog.dart';
import 'compact_level.dart';
import 'gif_image.dart';
import 'smooth_scroll.dart';

class FileBrowserPanel extends StatelessWidget {
  final LibraryItem item;
  final LibraryState state;
  final double height;
  final double backgroundOpacity;
  final GifDisplayMode gifMode;

  const FileBrowserPanel({
    super.key,
    required this.item,
    required this.state,
    required this.height,
    this.backgroundOpacity = 1.0,
    this.gifMode = GifDisplayMode.hover,
  });

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      color: cs.surface.withValues(alpha: backgroundOpacity),
      child: Column(
        children: [
          _buildHeader(context, c),
          Expanded(child: _buildFileGrid(c)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 30 * c,
      padding: EdgeInsets.symmetric(horizontal: 8 * c),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border:
            Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open, size: 12 * c, color: cs.onSurfaceVariant),
          SizedBox(width: 4 * c),
          Text(
            Strings.tn('fileContent', {'title': item.info.title}),
            style: TextStyle(
                fontSize: 11 * c, fontWeight: FontWeight.w500, color: cs.onSurface),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: state.toggleSystemFiles,
            icon: Icon(
              state.showSystemFiles
                  ? Icons.visibility_off
                  : Icons.visibility,
              size: 14 * c,
            ),
            label: Text(
              state.showSystemFiles ? Strings.t('hideInfo') : Strings.t('showInfo'),
              style: TextStyle(fontSize: 11 * c),
            ),
            style: TextButton.styleFrom(
              padding:
                  EdgeInsets.symmetric(horizontal: 10 * c, vertical: 4 * c),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          SizedBox(width: 8 * c),
          InkWell(
            onTap: state.hideFileBrowser,
            borderRadius: BorderRadius.circular(12 * c),
            child: Container(
              padding:
                  EdgeInsets.symmetric(horizontal: 10 * c, vertical: 4 * c),
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(12 * c),
              ),
              child: Text(
                Strings.t('closePanel'),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11 * c,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileGrid(double c) {
    final dir = Directory(item.path);
    if (!dir.existsSync()) {
      return Center(child: Text(Strings.t('folderNotExist')));
    }

    final entries = dir
        .listSync()
        .where((e) => e is File || e is Directory)
        .toList()
      ..sort((a, b) => _baseName(a.path).compareTo(_baseName(b.path)));

    final visible = state.showSystemFiles
        ? entries
        : entries.where((f) {
            final name = _baseName(f.path).toLowerCase();
            final isInfo = name == 'info.json';
            final isPreview = previewExtensions.any((ext) => name == 'preview$ext');
            return !isInfo && !isPreview;
          }).toList();

    if (visible.isEmpty) {
      return Center(
        child: Text(
          Strings.t('noFiles'),
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12 * c),
        ),
      );
    }

    return SmoothScroll(
      builder: (context, controller, physics) => GridView.builder(
        controller: controller,
        physics: physics,
        padding: EdgeInsets.symmetric(horizontal: 8 * c, vertical: 6 * c),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 82 * c,
          mainAxisExtent: 96 * c,
          crossAxisSpacing: 4 * c,
          mainAxisSpacing: 4 * c,
        ),
        itemCount: visible.length,
        itemBuilder: (context, index) =>
            _buildFileItem(context, visible[index], c),
      ),
    );
  }

  Widget _buildFileItem(BuildContext context, FileSystemEntity file, double c) {
    return _FileGridItem(
      file: file,
      compactLevel: c,
      gifMode: gifMode,
      onDoubleTap: () => _openFile(file.path),
      onRightClick: (globalPos) => _showContextMenu(context, file, globalPos),
    );
  }

  void _showContextMenu(BuildContext context, FileSystemEntity file, Offset globalPos) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx + 1,
        globalPos.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'open',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 14),
              SizedBox(width: 8),
              Text(Strings.t('defaultOpen'), style: const TextStyle(fontSize: 12)),
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
              Text(Strings.t('openAs'), style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'rename',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.drive_file_rename_outline, size: 14),
              SizedBox(width: 8),
              Text(Strings.t('rename'), style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'locate',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 14),
              SizedBox(width: 8),
              Text(Strings.t('showInExplorer'), style: const TextStyle(fontSize: 12)),
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
              Text(Strings.t('properties'), style: const TextStyle(fontSize: 12)),
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

  void _showRenameDialog(BuildContext context, FileSystemEntity file) {
    final currentName = _baseName(file.path);
    final dotIndex = currentName.lastIndexOf('.');
    final nameWithoutExt =
        dotIndex > 0 ? currentName.substring(0, dotIndex) : currentName;

    final ctrl = TextEditingController(text: currentName);
    ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: nameWithoutExt.length);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Strings.t('rename'), style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: Strings.t('newFileName'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onSubmitted: (_) => _doRename(dialogContext, file, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(Strings.t('cancel')),
          ),
          FilledButton(
            onPressed: () => _doRename(dialogContext, file, ctrl.text.trim()),
            child: Text(Strings.t('rename')),
          ),
        ],
      ),
    );
  }

  Future<void> _doRename(
      BuildContext dialogContext, FileSystemEntity file, String newName) async {
    if (newName.isEmpty) return;
    Navigator.pop(dialogContext);

    final error = await state.renameFile(file.path, newName);
    if (error != null && dialogContext.mounted) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(Strings.tn('renameFailed', {'error': error.toString()})), backgroundColor: Colors.red),
      );
    }
  }

  void _openFile(String path) {
    Process.run('cmd', ['/c', 'start', '', path]);
  }

  String _baseName(String fullPath) {
    return fullPath.replaceAll('\\', '/').split('/').last;
  }
}

class _FileGridItem extends StatefulWidget {
  final FileSystemEntity file;
  final double compactLevel;
  final GifDisplayMode gifMode;
  final VoidCallback onDoubleTap;
  final void Function(Offset globalPosition) onRightClick;

  const _FileGridItem({
    required this.file,
    required this.compactLevel,
    required this.gifMode,
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
    final c = widget.compactLevel;
    final cs = Theme.of(context).colorScheme;
    final name = _baseName(widget.file.path);
    final isDir = widget.file is Directory;
    final isImage = !isDir &&
        previewExtensions.any((ext) => name.toLowerCase().endsWith(ext));
    final isGif = !isDir && name.toLowerCase().endsWith('.gif');

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
            decoration: BoxDecoration(
              color: _isHovering
                  ? cs.onSurface.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6 * c),
            ),
            padding: EdgeInsets.symmetric(vertical: 4 * c),
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
                  child: isDir
                      ? _buildFileIcon(name, c, isDir: true)
                      : (isImage
                          ? (isGif
                              ? GifImage(
                                  file: widget.file as File,
                                  gifMode: widget.gifMode,
                                  cacheWidth: 120,
                                  fit: BoxFit.cover,
                                  placeholderColor: cs.surfaceContainerHighest,
                                  errorBuilder: (_) => _buildFileIcon(name, c),
                                )
                              : Image.file(widget.file as File,
                                  cacheWidth: 120,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildFileIcon(name, c)))
                          : _buildFileIcon(name, c)),
                ),
                SizedBox(height: 4 * c),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9 * c),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileIcon(String fileName, double c, {bool isDir = false}) {
    if (isDir) {
      return Icon(Icons.folder, size: 28 * c, color: Colors.amber.shade400);
    }
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

    return Icon(icon, size: 28 * c, color: color);
  }

  String _baseName(String fullPath) {
    return fullPath.replaceAll('\\', '/').split('/').last;
  }
}
