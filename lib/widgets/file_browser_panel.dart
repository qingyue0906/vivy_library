import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import '../models/library_item.dart';
import '../models/exe_record.dart';
import '../providers/library_state.dart';
import '../services/library_scanner.dart';
import '../services/script_service.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import 'exe_picker_dialog.dart';
import 'file_properties_dialog.dart';
import 'compact_level.dart';
import 'gif_image.dart';
import 'script_result_dialog.dart';
import 'smooth_scroll.dart';

class FileBrowserPanel extends StatefulWidget {
  final LibraryItem item;
  final LibraryState state;
  final ScriptService scriptService;
  final double height;
  final double backgroundOpacity;
  final GifDisplayMode gifMode;

  const FileBrowserPanel({
    super.key,
    required this.item,
    required this.state,
    required this.scriptService,
    required this.height,
    this.backgroundOpacity = 1.0,
    this.gifMode = GifDisplayMode.hover,
  });

  @override
  State<FileBrowserPanel> createState() => _FileBrowserPanelState();
}

class _FileBrowserPanelState extends State<FileBrowserPanel> {
  final FocusNode _focusNode = FocusNode();
  bool _isDragOver = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);
    return Container(
      height: widget.height,
      clipBehavior: _isDragOver ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: widget.backgroundOpacity),
        borderRadius: _isDragOver ? radius : null,
      ),
      child: Stack(
        children: [
          Column(
            children: [
              _buildHeader(context, c),
              Expanded(child: _buildFileGrid(context, c)),
            ],
          ),
          if (_isDragOver)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: cs.primary, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    final selectedCount = widget.state.selectedBrowserPaths.length;
    return Container(
      height: 30 * c,
      padding: EdgeInsets.symmetric(horizontal: 8 * c),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open, size: 12 * c, color: cs.onSurfaceVariant),
          SizedBox(width: 4 * c),
          Expanded(
            child: Text(
              selectedCount > 0
                  ? '${Strings.tn('fileContent', {'title': widget.item.info.title})}  ·  $selectedCount'
                  : Strings.tn('fileContent', {'title': widget.item.info.title}),
              style: TextStyle(
                fontSize: 11 * c,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (selectedCount > 0)
            _headerIconButton(
              c: c,
              cs: cs,
              icon: Icons.deselect,
              tooltip: Strings.t('deselectAll'),
              onTap: widget.state.clearBrowserSelection,
            ),
          _headerIconButton(
            c: c,
            cs: cs,
            icon: widget.state.showSystemFiles
                ? Icons.visibility_off
                : Icons.visibility,
            tooltip: widget.state.showSystemFiles
                ? Strings.t('hideInfo')
                : Strings.t('showInfo'),
            onTap: widget.state.toggleSystemFiles,
          ),
          _headerIconButton(
            c: c,
            cs: cs,
            icon: Icons.close,
            tooltip: Strings.t('closePanel'),
            onTap: widget.state.hideFileBrowser,
            iconColor: Colors.red.shade400,
          ),
        ],
      ),
    );
  }

  Widget _headerIconButton({
    required double c,
    required ColorScheme cs,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8 * c),
        child: Padding(
          padding: EdgeInsets.all(6 * c),
          child: Icon(
            icon,
            size: 16 * c,
            color: iconColor ?? cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildFileGrid(BuildContext context, double c) {
    final dir = Directory(widget.item.path);
    if (!dir.existsSync()) {
      return Center(child: Text(Strings.t('folderNotExist')));
    }

    final entries = dir
        .listSync()
        .where((e) => e is File || e is Directory)
        .toList()
      ..sort((a, b) => _baseName(a.path).compareTo(_baseName(b.path)));

    final visible = widget.state.showSystemFiles
        ? entries
        : entries.where((f) {
            final name = _baseName(f.path).toLowerCase();
            final isInfo = name == 'info.json';
            final isPreview = previewExtensions.any((ext) => name == 'preview$ext');
            return !isInfo && !isPreview;
          }).toList();

    final visiblePaths = visible.map((e) => e.path).toList();

    if (visible.isEmpty) {
      return _buildDropTarget(
        c,
        Center(
          child: Text(
            Strings.t('noFiles'),
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12 * c),
          ),
        ),
        visiblePaths,
      );
    }

    final grid = SmoothScroll(
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

    // 点击空白处清除选中；Ctrl+A 全选
    final interactive = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _focusNode.requestFocus();
        widget.state.clearBrowserSelection();
      },
      child: grid,
    );

    return _buildDropTarget(
      c,
      Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyA &&
              HardwareKeyboard.instance.isControlPressed) {
            widget.state.selectAllBrowserFiles(visiblePaths);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: interactive,
      ),
      visiblePaths,
    );
  }

  /// 用 DropRegion 包裹：拖入文件即复制到 item.path。
  Widget _buildDropTarget(double c, Widget child, List<String> visiblePaths) {
    return DropRegion(
      formats: const [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.translucent,
      onDropOver: (event) {
        setState(() => _isDragOver = true);
        final allowed = event.session.allowedOperations;
        if (allowed.contains(DropOperation.copy)) return DropOperation.copy;
        return allowed.isNotEmpty ? allowed.first : DropOperation.none;
      },
      onDropLeave: (event) {
        setState(() => _isDragOver = false);
      },
      onPerformDrop: (event) async {
        setState(() => _isDragOver = false);
        final paths = <String>[];
        for (final di in event.session.items) {
          paths.addAll(await _readFilePaths(di));
        }
        if (paths.isNotEmpty) {
          await widget.state.copyFilesToDirectory(paths, widget.item.path);
        }
      },
      child: child,
    );
  }

  Future<List<String>> _readFilePaths(DropItem dropItem) async {
    final reader = dropItem.dataReader;
    if (reader == null) return [];
    if (!reader.canProvide(Formats.fileUri)) return [];
    final completer = Completer<List<String>>();
    reader.getValue<Uri>(
      Formats.fileUri,
      (uri) {
        completer.complete(uri != null ? [uri.toFilePath()] : []);
      },
      onError: (e) => completer.complete([]),
    );
    return completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => [],
    );
  }

  Widget _buildFileItem(BuildContext context, FileSystemEntity file, double c) {
    return _FileGridItem(
      file: file,
      compactLevel: c,
      gifMode: widget.gifMode,
      isSelected: widget.state.isBrowserSelected(file.path),
      selectedPaths: widget.state.selectedBrowserPaths,
      onTap: () {
        _focusNode.requestFocus();
        widget.state.setSelectedBrowserFile(file.path);
      },
      onCtrlTap: () {
        _focusNode.requestFocus();
        widget.state.toggleBrowserSelection(file.path);
      },
      onShiftTap: () {
        _focusNode.requestFocus();
        final dir = Directory(widget.item.path);
        final list = <String>[];
        if (dir.existsSync()) {
          final entries = dir
              .listSync()
              .where((e) => e is File || e is Directory)
              .map((e) => e.path)
              .toList();
          entries.sort((a, b) => _baseName(a).compareTo(_baseName(b)));
          list.addAll(entries);
        }
        widget.state.selectBrowserRange(file.path, list);
      },
      onDoubleTap: () => _openFile(file.path),
      onRightClick: (globalPos) => _showContextMenu(context, file, globalPos),
    );
  }

  void _showContextMenu(BuildContext context, FileSystemEntity file, Offset globalPos) {
    widget.state.selectBrowserForContextMenu(file.path);
    final selected = widget.state.selectedBrowserPaths.toList();
    final isBatch = selected.length > 1;
    final paths = isBatch ? selected : [file.path];

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
              const Icon(Icons.open_in_new, size: 14),
              const SizedBox(width: 8),
              Text(
                isBatch ? Strings.tn('openN', {'n': '${paths.length}'}) : Strings.t('defaultOpen'),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        if (!isBatch)
          PopupMenuItem(
            value: 'open_as',
            height: 32,
            child: Row(
              children: [
                const Icon(Icons.apps, size: 14),
                const SizedBox(width: 8),
                Text(Strings.t('openAs'), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        if (!isBatch)
          PopupMenuItem(
            value: 'rename',
            height: 32,
            child: Row(
              children: [
                const Icon(Icons.drive_file_rename_outline, size: 14),
                const SizedBox(width: 8),
                Text(Strings.t('rename'), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        if (!isBatch) const PopupMenuDivider(),
        PopupMenuItem(
          value: 'locate',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.folder_open, size: 14),
              const SizedBox(width: 8),
              Text(
                isBatch
                    ? Strings.tn('locateNInExplorer', {'n': '${paths.length}'})
                    : Strings.t('showInExplorer'),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        if (!isBatch)
          PopupMenuItem(
            value: 'properties',
            height: 32,
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14),
                const SizedBox(width: 8),
                Text(Strings.t('properties'), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ..._buildScriptMenuItems(context),
        if (isBatch) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'deselect',
            height: 32,
            child: Row(
              children: [
                const Icon(Icons.deselect, size: 14),
                const SizedBox(width: 8),
                Text(Strings.t('deselectAll'), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ],
    ).then((value) async {
      if (value == null) return;
      if (value.startsWith('script:')) {
        final scriptId = value.substring(7);
        final script = widget.scriptService.scripts.where((s) => s.id == scriptId).firstOrNull;
        if (script != null) {
          _runScript(context, script, paths);
        }
        return;
      }
      switch (value) {
        case 'open':
          for (final p in paths) {
            _openFile(p);
          }
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
          if (isBatch) {
            Process.run('explorer', [widget.item.path]);
          } else {
            Process.run('explorer', ['/select,', file.path]);
          }
        case 'properties':
          showDialog(
            context: context,
            builder: (_) => FilePropertiesDialog(file: file),
          );
        case 'deselect':
          widget.state.clearBrowserSelection();
      }
    });
  }

  List<PopupMenuEntry<String>> _buildScriptMenuItems(BuildContext context) {
    final scripts = widget.scriptService.scripts.where((s) => s.enabled).toList();
    if (scripts.isEmpty) return const [];
    return [
      const PopupMenuDivider(),
      for (final script in scripts)
        PopupMenuItem<String>(
          value: 'script:${script.id}',
          height: 32,
          child: Tooltip(
            waitDuration: Duration.zero,
            message: widget.scriptService.readDescriptionSync(script),
            child: Row(children: [
              const Icon(Icons.code, size: 14),
              const SizedBox(width: 8),
              Expanded(child: Text(script.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
    ];
  }

  void _runScript(BuildContext context, ScriptEntry script, List<String> paths) {
    if (script.execMode == ScriptExecMode.terminal) {
      widget.scriptService.executeScriptTerminal(script, paths);
    } else {
      final future = script.execMode == ScriptExecMode.silent
          ? widget.scriptService.executeScriptSilent(script, paths)
          : widget.scriptService.executeScript(script, paths);
      future.then((result) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (_) => ScriptResultDialog(result: result),
          );
        }
      });
    }
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

    final error = await widget.state.renameFile(file.path, newName);
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
  final bool isSelected;
  final Set<String> selectedPaths;
  final VoidCallback onTap;
  final VoidCallback onCtrlTap;
  final VoidCallback onShiftTap;
  final VoidCallback onDoubleTap;
  final void Function(Offset globalPosition) onRightClick;

  const _FileGridItem({
    required this.file,
    required this.compactLevel,
    required this.gifMode,
    required this.isSelected,
    required this.selectedPaths,
    required this.onTap,
    required this.onCtrlTap,
    required this.onShiftTap,
    required this.onDoubleTap,
    required this.onRightClick,
  });

  @override
  State<_FileGridItem> createState() => _FileGridItemState();
}

class _FileGridItemState extends State<_FileGridItem> {
  bool _isHovering = false;
  final _snapshotterKey = GlobalKey<WidgetSnapshotterState>();
  static final _dragSnapshotKey = Object();
  DateTime? _lastTapTime;

  /// 构建拖拽配置：选中多项时为每个文件创建独立 DragItem，
  /// Windows 原生端会将各 provider 的路径合并为单个 CF_HDROP（多文件）。
  Future<DragConfiguration?> _buildDragConfig(
      Offset location, DragSession session) async {
    final selected = widget.selectedPaths;
    final paths = (widget.isSelected && selected.length > 1)
        ? selected.toList()
        : [widget.file.path];
    final snapshotter = _snapshotterKey.currentState;
    if (snapshotter == null || !snapshotter.mounted) return null;
    final snapshot =
        await snapshotter.getSnapshot(location, _dragSnapshotKey, () => null);
    if (snapshot == null) return null;
    final items = <DragConfigurationItem>[];
    for (int i = 0; i < paths.length; i++) {
      final dragItem = DragItem(localData: paths);
      dragItem.add(Formats.fileUri(Uri.file(paths[i])));
      items.add(DragConfigurationItem(
        item: dragItem,
        image: i == 0 ? snapshot : snapshot.retain(),
      ));
    }
    return DragConfiguration(
      items: items,
      allowedOperations: const [DropOperation.copy],
    );
  }

  /// 手动双击判定：300ms 内二次点击触发双击，单击立即响应无延迟。
  void _handleTap() {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300) {
      _lastTapTime = null;
      widget.onDoubleTap();
      return;
    }
    _lastTapTime = now;
    if (HardwareKeyboard.instance.isControlPressed) {
      widget.onCtrlTap();
    } else if (HardwareKeyboard.instance.isShiftPressed) {
      widget.onShiftTap();
    } else {
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.compactLevel;
    final cs = Theme.of(context).colorScheme;
    final name = _baseName(widget.file.path);
    final isDir = widget.file is Directory;
    final isImage = !isDir &&
        previewExtensions.any((ext) => name.toLowerCase().endsWith(ext));

    final selectedBorder = widget.isSelected
        ? Border.all(color: cs.primary, width: 1.5)
        : null;
    final selectedBg = widget.isSelected
        ? cs.primary.withValues(alpha: 0.12)
        : (_isHovering ? cs.onSurface.withValues(alpha: 0.08) : Colors.transparent);

    return WidgetSnapshotter(
      key: _snapshotterKey,
      child: BaseDraggableWidget(
        dragConfiguration: _buildDragConfig,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          child: GestureDetector(
            onTap: _handleTap,
            onSecondaryTapUp: (details) =>
                widget.onRightClick(details.globalPosition),
            child: Tooltip(
              message: name,
              waitDuration: const Duration(milliseconds: 500),
              child: Container(
                decoration: BoxDecoration(
                  color: selectedBg,
                  border: selectedBorder,
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
                              ? GifImage(
                                  file: widget.file as File,
                                  gifMode: widget.gifMode,
                                  cacheWidth: 120,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_) => _buildFileIcon(name, c),
                                )
                              : _buildFileIcon(name, c)),
                    ),
                    SizedBox(height: 4 * c),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9 * c,
                          color: widget.isSelected ? cs.primary : cs.onSurface,
                          fontWeight: widget.isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
