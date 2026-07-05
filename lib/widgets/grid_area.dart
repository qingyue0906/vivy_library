import 'package:flutter/material.dart';
import '../models/library_item.dart';
import '../models/category_node.dart';
import '../models/direct_file.dart';
import '../providers/library_state.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import 'item_card.dart';
import 'folder_card.dart';
import 'file_card.dart';
import 'dart:io';
import 'file_browser_panel.dart';
import 'file_properties_dialog.dart';
import 'exe_picker_dialog.dart';
import '../models/exe_record.dart';
import '../services/script_service.dart';
import 'class_nav_bar.dart';
import 'package:flutter/services.dart';
import 'compact_level.dart';
import 'script_result_dialog.dart';
import 'smooth_scroll.dart';

class GridArea extends StatelessWidget {
  final List<LibraryItem> items;
  final List<CategoryNode> subDirs;
  final List<DirectFile> files;
  final LibraryState state;
  final ScriptService scriptService;
  final double filePanelHeight;
  final void Function(double delta) onFilePanelResize;
  final VoidCallback? onFilePanelResizeEnd;
  final void Function(List<LibraryItem> targets, bool isBatch) onEditRequest;
  final void Function(CategoryNode folder) onFolderEditRequest;
  final void Function(List<CategoryNode> folders) onFolderBatchEditRequest;
  final VoidCallback? onCreateItem;
  final GridSettings gridSettings;
  final double middleOpacity;

  const GridArea({
    super.key,
    required this.items,
    required this.subDirs,
    required this.files,
    required this.state,
    required this.scriptService,
    required this.filePanelHeight,
    required this.onFilePanelResize,
    this.onFilePanelResizeEnd,
    required this.onEditRequest,
    required this.onFolderEditRequest,
    required this.onFolderBatchEditRequest,
    required this.gridSettings,
    this.middleOpacity = 1.0,
    this.onCreateItem,
  });

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyA &&
            HardwareKeyboard.instance.isControlPressed) {
          state.selectAll(items);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          Column(
            children: [
              ClassNavBar(state: state),
              Expanded(
                child: (items.isEmpty && subDirs.isEmpty && files.isEmpty)
                    ? Center(child: Text(Strings.t('noItems'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12 * c)))
                    : Padding(
                        padding: EdgeInsets.all(8 * c),
                        child: _buildGrid(context, c),
                      ),
              ),
              if (state.fileBrowserVisible && state.selectedItem != null) ...[
                MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanUpdate: (details) => onFilePanelResize(details.delta.dy),
                    onPanEnd: (_) => onFilePanelResizeEnd?.call(),
                    child: Container(
                      height: 4,
                      color: Colors.transparent,
                    ),
                  ),
                ),
                FileBrowserPanel(
                  item: state.selectedItem!,
                  state: state,
                  scriptService: scriptService,
                  height: filePanelHeight,
                  backgroundOpacity: middleOpacity,
                  gifMode: gridSettings.fileGifMode,
                ),
              ],
            ],
          ),
          Positioned(
            right: 16 * c,
            bottom: (state.fileBrowserVisible && state.selectedItem != null ? filePanelHeight : 0) + 16 * c,
            child: FloatingActionButton.small(
              heroTag: 'createItem',
              onPressed: onCreateItem,
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    final minCardWidth = gridSettings.minCardWidth;
    final maxCardWidth = gridSettings.maxCardWidth;
    final spacing = 8.0 * c;
    final fixedPerRow = gridSettings.itemsPerRow;
    final aspectRatio = gridSettings.aspectRatioValue;

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount;
        double cardWidth;

        if (fixedPerRow > 0) {
          crossAxisCount = fixedPerRow;
          cardWidth = (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
              crossAxisCount;
        } else {
          crossAxisCount = (constraints.maxWidth / (maxCardWidth + spacing))
              .floor()
              .clamp(1, 999);
          cardWidth =
              (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                  crossAxisCount;
          if (cardWidth < minCardWidth && crossAxisCount > 1) {
            crossAxisCount--;
            cardWidth = (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                crossAxisCount;
          }
        }

        final imgHeight = cardWidth / aspectRatio;
        final mainAxisExtent = imgHeight + 38 * c;
        final folderMainAxisExtent = cardWidth / aspectRatio * 0.5 + 50 * c;
        final fileMainAxisExtent = cardWidth / aspectRatio * 0.5 + 46 * c;

        final gSubDirs = state.groupedSubDirs;
        final gItems = state.groupedItems;
        final gFiles = state.groupedFiles;

        return SmoothScroll(
          builder: (context, controller, physics) => CustomScrollView(
            controller: controller,
            physics: physics,
            slivers: [
              if (gSubDirs.any((g) => g.entries.isNotEmpty)) ...[
                _sectionHeader(Strings.t('folderSection'), c, cs, top: false),
                ..._buildGroupedSlivers(
                  gSubDirs, crossAxisCount, folderMainAxisExtent, spacing, c, cs,
                  (node) => FolderCard(
                    key: GlobalObjectKey(node.path),
                    node: node,
                    displayWidth: cardWidth,
                    isSelected: state.isFolderSelected(node.path),
                    onTap: () => state.setSelectedFolder(node),
                    onDoubleTap: () => state.setSelectedCategory(node.path),
                    onCtrlTap: () => state.toggleFolderSelection(node),
                    onShiftTap: () => state.selectFolderRange(node, subDirs),
                    onRightClick: (globalPos) => _showFolderContextMenu(context, node, globalPos),
                  ),
                ),
              ],
              if (gItems.any((g) => g.entries.isNotEmpty)) ...[
                _sectionHeader(Strings.t('itemSection'), c, cs),
                ..._buildGroupedSlivers(
                  gItems, crossAxisCount, mainAxisExtent, spacing, c, cs,
                  (item) => ItemCard(
                    key: GlobalObjectKey(item.path),
                    item: item,
                    aspectRatio: aspectRatio,
                    displayWidth: cardWidth,
                    displayHeight: imgHeight,
                    isSelected: state.isItemSelected(item.path),
                    onTap: () => state.setSelectedItem(item),
                    onCtrlTap: () => state.toggleItemSelection(item),
                    onShiftTap: () => state.selectRange(item, items),
                    onRightClick: (globalPos) => _showContextMenu(context, item, globalPos),
                    gifMode: gridSettings.cardGifMode,
                  ),
                ),
              ],
              if (gFiles.any((g) => g.entries.isNotEmpty)) ...[
                _sectionHeader(Strings.t('fileSection'), c, cs),
                ..._buildGroupedSlivers(
                  gFiles, crossAxisCount, fileMainAxisExtent, spacing, c, cs,
                  (file) => FileCard(
                    key: GlobalObjectKey(file.path),
                    file: file,
                    displayWidth: cardWidth,
                    isSelected: state.selectedFile?.path == file.path,
                    onTap: () => state.setSelectedFile(file),
                    onDoubleTap: () => _openFile(file.path),
                    onRightClick: (globalPos) => _showFileContextMenu(context, file, globalPos),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title, double c, ColorScheme cs, {bool top = true}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(top: top ? 8 * c : 0, bottom: 4 * c, left: 2 * c),
        child: Text(title, style: TextStyle(fontSize: 11 * c, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
      ),
    );
  }

  List<Widget> _buildGroupedSlivers<T>(List<GroupedEntries<T>> groups, int crossAxisCount,
      double mainAxisExtent, double spacing, double c, ColorScheme cs,
      Widget Function(T) cardBuilder) {
    final slivers = <Widget>[];
    for (final group in groups) {
      if (group.entries.isEmpty) continue;
      if (group.groupLabel.isNotEmpty) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(2 * c, 4 * c, 0, 2 * c),
            child: Text(group.groupLabel, style: TextStyle(fontSize: 10 * c, color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
          ),
        ));
      }
      slivers.add(SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisExtent: mainAxisExtent,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => cardBuilder(group.entries[index]),
          childCount: group.entries.length,
        ),
      ));
    }
    return slivers;
  }

  void _showFolderContextMenu(
      BuildContext context, CategoryNode node, Offset globalPos) {
    final c = CompactLevel.of(context);
    state.selectFolderForContextMenu(node);
    final selectedFolders = state.selectedFolders;
    final isBatch = selectedFolders.length > 1;

    final position = RelativeRect.fromLTRB(
      globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1,
    );
    showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(minWidth: 150 * c),
      items: [
        PopupMenuItem(
          value: 'edit',
          height: 28 * c,
          child: Row(children: [
            Icon(Icons.edit, size: 13 * c),
            SizedBox(width: 6 * c),
            Text(
              isBatch ? Strings.tn('batchEditN', {'n': '${selectedFolders.length}'}) : Strings.t('edit'),
              style: TextStyle(fontSize: 11 * c),
            ),
          ]),
        ),
        PopupMenuItem(
          value: 'locate',
          height: 28 * c,
          child: Row(children: [
            Icon(Icons.location_searching, size: 13 * c),
            SizedBox(width: 6 * c),
            Text(Strings.t('locateHere'), style: TextStyle(fontSize: 11 * c)),
          ]),
        ),
        PopupMenuItem(
          value: 'enter',
          height: 28 * c,
          child: Row(children: [
            Icon(Icons.folder_open, size: 13 * c),
            SizedBox(width: 6 * c),
            Text(Strings.t('enterFolder'), style: TextStyle(fontSize: 11 * c)),
          ]),
        ),
        PopupMenuItem(
          value: 'open_folder',
          height: 28 * c,
          child: Row(children: [
            Icon(Icons.open_in_new, size: 13 * c),
            SizedBox(width: 6 * c),
            Text(Strings.t('openInExplorer'), style: TextStyle(fontSize: 11 * c)),
          ]),
        ),
        ..._buildScriptMenuItems(context),
      ],
    ).then((value) {
      if (value == null) return;
      if (value.startsWith('script:')) {
        final scriptId = value.substring(7);
        final script = scriptService.scripts.where((s) => s.id == scriptId).firstOrNull;
        if (script != null) {
          _runScript(context, script, selectedFolders.map((f) => f.path).toList());
        }
        return;
      }
      switch (value) {
        case 'edit':
          if (isBatch) {
            onFolderBatchEditRequest(selectedFolders);
          } else {
            onFolderEditRequest(node);
          }
        case 'locate':
          _locateFolder(node.path);
        case 'enter':
          state.setSelectedCategory(node.path);
        case 'open_folder':
          _openInExplorer(node.path);
      }
    });
  }

  void _showContextMenu(
      BuildContext context, LibraryItem tappedItem, Offset globalPos) {
    final c = CompactLevel.of(context);
    state.selectItemForContextMenu(tappedItem);
    final selectedItems = state.selectedItems;
    final isBatch = selectedItems.length > 1;

    final position = RelativeRect.fromLTRB(
      globalPos.dx,
      globalPos.dy,
      globalPos.dx + 1,
      globalPos.dy + 1,
    );

    showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(minWidth: 150 * c),
      items: [
        PopupMenuItem(
          value: 'edit',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.edit, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(
                isBatch ? Strings.tn('batchEditN', {'n': '${selectedItems.length}'}) : Strings.t('edit'),
                style: TextStyle(fontSize: 11 * c),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'locate',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.location_searching, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(Strings.t('locateHere'), style: TextStyle(fontSize: 11 * c)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open_folder',
          height: 28 * c,
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 13 * c),
              SizedBox(width: 6 * c),
              Text(Strings.t('openInExplorer'), style: TextStyle(fontSize: 11 * c)),
            ],
          ),
        ),
        ..._buildScriptMenuItems(context),
      ],
    ).then((value) {
      if (value == null) return;
      if (value.startsWith('script:')) {
        final scriptId = value.substring(7);
        final script = scriptService.scripts.where((s) => s.id == scriptId).firstOrNull;
        if (script != null) {
          _runScript(context, script, selectedItems.map((i) => i.path).toList());
        }
        return;
      }
      switch (value) {
        case 'edit':
          onEditRequest(selectedItems, isBatch);
        case 'locate':
          _locateItem(tappedItem);
        case 'open_folder':
          _openInExplorer(tappedItem.path);
      }
    });
  }

  void _locateFolder(String folderPath) {
    state.locateInTree(folderPath);
  }

  void _locateItem(LibraryItem item) {
    state.locateInTree(item.categoryPath);
    // 切换分类后，下一帧将对应项目滚动到可见区域
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = GlobalObjectKey(item.path);
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
        );
      }
    });
  }

  void _openInExplorer(String path) {
    Process.run('explorer', [path]);
  }

  void _openFile(String path) {
    Process.run('cmd', ['/c', 'start', '', path]);
  }

  void _showFileContextMenu(
      BuildContext context, DirectFile file, Offset globalPos) {
    final c = CompactLevel.of(context);
    final position = RelativeRect.fromLTRB(
      globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1,
    );
    showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(minWidth: 150 * c),
      items: [
        PopupMenuItem(
          value: 'open',
          height: 28 * c,
          child: Row(children: [
            Icon(Icons.open_in_new, size: 13 * c),
            SizedBox(width: 6 * c),
            Text(Strings.t('openWithDefault'), style: TextStyle(fontSize: 11 * c)),
          ]),
        ),
        PopupMenuItem(
          value: 'open_as',
          height: 28 * c,
          child: Row(children: [
            Icon(Icons.apps, size: 13 * c),
            SizedBox(width: 6 * c),
            Text(Strings.t('openAs'), style: TextStyle(fontSize: 11 * c)),
          ]),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'rename',
          height: 28 * c,
          child: Row(children: [
            Icon(Icons.drive_file_rename_outline, size: 13 * c),
            SizedBox(width: 6 * c),
            Text(Strings.t('rename'), style: TextStyle(fontSize: 11 * c)),
          ]),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'locate',
          height: 28 * c,
          child: Row(children: [
            Icon(Icons.folder_open, size: 13 * c),
            SizedBox(width: 6 * c),
            Text(Strings.t('openInExplorer'), style: TextStyle(fontSize: 11 * c)),
          ]),
        ),
        PopupMenuItem(
          value: 'properties',
          height: 28 * c,
          child: Row(children: [
            Icon(Icons.info_outline, size: 13 * c),
            SizedBox(width: 6 * c),
            Text(Strings.t('properties'), style: TextStyle(fontSize: 11 * c)),
          ]),
        ),
        ..._buildScriptMenuItems(context),
      ],
    ).then((value) async {
      if (value == null) return;
      if (value.startsWith('script:')) {
        final scriptId = value.substring(7);
        final script = scriptService.scripts.where((s) => s.id == scriptId).firstOrNull;
        if (script != null) {
          _runScript(context, script, [file.path]);
        }
        return;
      }
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
            builder: (_) => FilePropertiesDialog(file: File(file.path)),
          );
      }
    });
  }

  List<PopupMenuEntry<String>> _buildScriptMenuItems(BuildContext context) {
    final c = CompactLevel.of(context);
    final scripts = scriptService.scripts.where((s) => s.enabled).toList();
    if (scripts.isEmpty) return const [];
    return [
      PopupMenuDivider(),
      for (final script in scripts)
        PopupMenuItem<String>(
          value: 'script:${script.id}',
          height: 28 * c,
          child: Tooltip(
            waitDuration: Duration.zero,
            message: scriptService.readDescriptionSync(script),
            child: Row(children: [
              Icon(Icons.code, size: 13 * c),
              SizedBox(width: 6 * c),
              Expanded(child: Text(script.name, style: TextStyle(fontSize: 11 * c), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
    ];
  }

  void _runScript(BuildContext context, ScriptEntry script, List<String> paths) {
    if (script.execMode == ScriptExecMode.terminal) {
      scriptService.executeScriptTerminal(script, paths);
    } else {
      final future = script.execMode == ScriptExecMode.silent
          ? scriptService.executeScriptSilent(script, paths)
          : scriptService.executeScript(script, paths);
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

  void _showRenameDialog(BuildContext context, DirectFile file) {
    final currentName = file.name;
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
      BuildContext dialogContext, DirectFile file, String newName) async {
    if (newName.isEmpty) return;
    Navigator.pop(dialogContext);

    final error = await state.renameFile(file.path, newName);
    if (error != null && dialogContext.mounted) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(Strings.tn('renameFailed', {'error': error.toString()})), backgroundColor: Colors.red),
      );
    }
  }
}
