import 'package:flutter/material.dart';
import '../models/library_item.dart';
import '../providers/library_state.dart';
import '../services/settings_service.dart';
import 'item_card.dart';
import 'dart:io';
import 'file_browser_panel.dart';
import 'class_nav_bar.dart';
import 'package:flutter/services.dart';
import 'compact_level.dart';

class GridArea extends StatelessWidget {
  final List<LibraryItem> items;
  final LibraryState state;
  final double filePanelHeight;
  final void Function(double delta) onFilePanelResize;
  final VoidCallback? onFilePanelResizeEnd;
  final void Function(List<LibraryItem> targets, bool isBatch) onEditRequest;
  final GridSettings gridSettings;

  const GridArea({
    super.key,
    required this.items,
    required this.state,
    required this.filePanelHeight,
    required this.onFilePanelResize,
    this.onFilePanelResizeEnd,
    required this.onEditRequest,
    required this.gridSettings,
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
            child: items.isEmpty
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
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, double c) {
    final minCardWidth = gridSettings.minCardWidth;
    final maxCardWidth = gridSettings.maxCardWidth;
    final spacing = 8.0 * c;
    final fixedPerRow = gridSettings.itemsPerRow;

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

        return SingleChildScrollView(
          child: SizedBox(
            width: constraints.maxWidth,
            child: Wrap(
              alignment: WrapAlignment.start,
              spacing: spacing,
              runSpacing: spacing,
              children: items.map((item) {
                return SizedBox(
                  width: cardWidth,
                  child: ItemCard(
                    item: item,
                    isSelected: state.isItemSelected(item.path),
                    onTap: () => state.setSelectedItem(item),
                    onCtrlTap: () => state.toggleItemSelection(item),
                    onShiftTap: () => state.selectRange(item, items),
                    onRightClick: (globalPos) =>
                        _showContextMenu(context, item, globalPos),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
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
        case 'open_folder':
          _openInExplorer(tappedItem.path);
      }
    });
  }

  void _openInExplorer(String path) {
    Process.run('explorer', ['/select,', path]);
  }
}
