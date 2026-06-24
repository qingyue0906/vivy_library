import 'package:flutter/material.dart';
import '../models/library_item.dart';
import '../models/category_node.dart';
import '../providers/library_state.dart';
import '../services/settings_service.dart';
import 'item_card.dart';
import 'folder_card.dart';
import 'dart:io';
import 'file_browser_panel.dart';
import 'class_nav_bar.dart';
import 'package:flutter/services.dart';
import 'compact_level.dart';

class GridArea extends StatelessWidget {
  final List<LibraryItem> items;
  final List<CategoryNode> subDirs;
  final LibraryState state;
  final double filePanelHeight;
  final void Function(double delta) onFilePanelResize;
  final VoidCallback? onFilePanelResizeEnd;
  final void Function(List<LibraryItem> targets, bool isBatch) onEditRequest;
  final void Function(CategoryNode folder) onFolderEditRequest;
  final void Function(List<CategoryNode> folders) onFolderBatchEditRequest;
  final GridSettings gridSettings;
  final double middleOpacity;

  const GridArea({
    super.key,
    required this.items,
    required this.subDirs,
    required this.state,
    required this.filePanelHeight,
    required this.onFilePanelResize,
    this.onFilePanelResizeEnd,
    required this.onEditRequest,
    required this.onFolderEditRequest,
    required this.onFolderBatchEditRequest,
    required this.gridSettings,
    this.middleOpacity = 1.0,
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
      child: Column(
        children: [
          ClassNavBar(state: state),
          Expanded(
            child: (items.isEmpty && subDirs.isEmpty)
                ? Center(child: Text('没有找到项目', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12 * c)))
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
              height: filePanelHeight,
              backgroundOpacity: middleOpacity,
              gifMode: gridSettings.fileGifMode,
            ),
          ],
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
        final folderMainAxisExtent = 48 * c + 4 * c + 34 * c + 12 * c; // 图标+间距+2行文字+vertical padding

        return CustomScrollView(
          slivers: [
            if (subDirs.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 4 * c, left: 2 * c),
                  child: Text(
                    '文件夹',
                    style: TextStyle(
                      fontSize: 11 * c,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisExtent: folderMainAxisExtent,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final node = subDirs[index];
                    return FolderCard(
                      key: GlobalObjectKey(node.path),
                      node: node,
                      displayWidth: cardWidth,
                      isSelected: state.isFolderSelected(node.path),
                      onTap: () => state.setSelectedFolder(node),
                      onDoubleTap: () => state.setSelectedCategory(node.path),
                      onCtrlTap: () => state.toggleFolderSelection(node),
                      onShiftTap: () => state.selectFolderRange(node, subDirs),
                      onRightClick: (globalPos) =>
                          _showFolderContextMenu(context, node, globalPos),
                    );
                  },
                  childCount: subDirs.length,
                ),
              ),
              if (items.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8 * c, bottom: 4 * c, left: 2 * c),
                    child: Text(
                      '项目',
                      style: TextStyle(
                        fontSize: 11 * c,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
            SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisExtent: mainAxisExtent,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = items[index];
                  return ItemCard(
                    key: GlobalObjectKey(item.path),
                    item: item,
                    aspectRatio: aspectRatio,
                    displayWidth: cardWidth,
                    displayHeight: imgHeight,
                    isSelected: state.isItemSelected(item.path),
                    onTap: () => state.setSelectedItem(item),
                    onCtrlTap: () => state.toggleItemSelection(item),
                    onShiftTap: () => state.selectRange(item, items),
                    onRightClick: (globalPos) =>
                        _showContextMenu(context, item, globalPos),
                    gifMode: gridSettings.cardGifMode,
                  );
                },
                childCount: items.length,
              ),
            ),
          ],
        );
      },
    );
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
              isBatch ? '批量编辑 (${selectedFolders.length} 项)' : '编辑',
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
            Text('定位到此处', style: TextStyle(fontSize: 11 * c)),
          ]),
        ),
        PopupMenuItem(
          value: 'enter',
          height: 28 * c,
          child: Row(children: [
            Icon(Icons.folder_open, size: 13 * c),
            SizedBox(width: 6 * c),
            Text('进入文件夹', style: TextStyle(fontSize: 11 * c)),
          ]),
        ),
        PopupMenuItem(
          value: 'open_folder',
          height: 28 * c,
          child: Row(children: [
            Icon(Icons.open_in_new, size: 13 * c),
            SizedBox(width: 6 * c),
            Text('在资源管理器中显示', style: TextStyle(fontSize: 11 * c)),
          ]),
        ),
      ],
    ).then((value) {
      if (value == null) return;
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
                isBatch ? '批量编辑 (${selectedItems.length} 项)' : '编辑',
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
              Text('定位到此处', style: TextStyle(fontSize: 11 * c)),
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
              Text('在资源管理器中显示', style: TextStyle(fontSize: 11 * c)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
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
}
