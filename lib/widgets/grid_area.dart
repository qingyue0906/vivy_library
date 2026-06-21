import 'package:flutter/material.dart';
import '../models/library_item.dart';
import '../providers/library_state.dart';
import 'item_card.dart';
import 'dart:io';
import 'file_browser_panel.dart';
import 'class_nav_bar.dart';
import 'package:flutter/services.dart';

class GridArea extends StatelessWidget {
  final List<LibraryItem> items;
  final LibraryState state;
  final double filePanelHeight;
  final void Function(double delta) onFilePanelResize;
  final VoidCallback? onFilePanelResizeEnd;
  final void Function(List<LibraryItem> targets, bool isBatch) onEditRequest;

  const GridArea({
    super.key,
    required this.items,
    required this.state,
    required this.filePanelHeight,
    required this.onFilePanelResize,
    this.onFilePanelResizeEnd,
    required this.onEditRequest,
  });

  @override
  Widget build(BuildContext context) {
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
                ? const Center(child: Text('没有找到项目'))
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildGrid(context),
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
                  height: 6,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(height: 1, color: Colors.black12),
                  ),
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

  // 把 LayoutBuilder + GridView 抽成独立方法,build 方法本身保持清晰,
  // 也方便我们单独核对这一块的括号是否配对正确
  Widget _buildGrid(BuildContext context) {
    const maxCardWidth = 200.0;
    const spacing = 10.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 算出这一行能放几列(逻辑和之前一样,这部分本身没有问题)
        final crossAxisCount = (constraints.maxWidth / (maxCardWidth + spacing))
            .floor()
            .clamp(1, 999);
        // 算出每张卡片实际应该多宽,让这一行卡片正好撑满,没有留白
        final cardWidth =
            (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                crossAxisCount;

        return SingleChildScrollView(
          child: SizedBox(
            width: constraints.maxWidth, // 用 LayoutBuilder 给的精确宽度撑满,而不是 double.infinity
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
      constraints: const BoxConstraints(minWidth: 150),
      items: [
        PopupMenuItem(
          value: 'edit',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.edit, size: 14),
              const SizedBox(width: 8),
              Text(
                isBatch ? '批量编辑 (${selectedItems.length} 项)' : '编辑',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open_folder',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.folder_open, size: 14),
              SizedBox(width: 8),
              Text('在资源管理器中显示', style: TextStyle(fontSize: 12)),
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