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

  final double filePanelHeight;                        // 新增
  final void Function(double delta) onFilePanelResize;  // 新增

  // 编辑回调由父级(ShellPage)传入,因为对话框需要在页面级别弹出
  final void Function(List<LibraryItem> targets, bool isBatch) onEditRequest;

  const GridArea({
    super.key,
    required this.items,
    required this.state,

    required this.filePanelHeight,        // 新增
    required this.onFilePanelResize,      // 新增

    required this.onEditRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true, // 网格区域默认获取键盘焦点,这样不用先点一下才能用快捷键
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyA &&
            HardwareKeyboard.instance.isControlPressed) {
          state.selectAll(items);
          return KeyEventResult.handled; // 告诉 Flutter 这个按键已经被处理了
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
                    // ...GridView 保持不变...
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const maxCardWidth = 200.0;
                      const spacing = 10.0;
                      const textAreaHeight = 40.0;

                      final crossAxisCount =
                          (constraints.maxWidth / (maxCardWidth + spacing)).floor().clamp(1, 999);
                      final cardWidth =
                          (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
                      final imageHeight = cardWidth * 2 / 3;
                      final cardHeight = imageHeight + textAreaHeight;
                      final aspectRatio = cardWidth / cardHeight;

                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: maxCardWidth,
                          childAspectRatio: aspectRatio,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ItemCard(
                            item: item,
                            isSelected: state.isItemSelected(item.path),
                            imageHeight: imageHeight,     // 新增
                            textHeight: textAreaHeight,   // 新增
                            onTap: () => state.setSelectedItem(item),
                            onCtrlTap: () => state.toggleItemSelection(item),
                            onShiftTap: () => state.selectRange(item, items),
                            onRightClick: (globalPos) =>
                                _showContextMenu(context, item, globalPos),
                          );
                        },
                      );
                    },
                  ),
                ),
        ),

        if (state.fileBrowserVisible && state.selectedItem != null) ...[
          MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (details) => onFilePanelResize(details.delta.dy),
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

  void _showContextMenu(BuildContext context, LibraryItem tappedItem, Offset globalPos) {
    state.selectItemForContextMenu(tappedItem);
    final selectedItems = state.selectedItems;
    final isBatch = selectedItems.length > 1;

    final position = RelativeRect.fromLTRB(
      globalPos.dx,
      globalPos.dy,
      globalPos.dx + 1,
      globalPos.dy + 1,
    );
    // 其余不变...

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
    // Windows 下用 explorer /select,"path" 打开并选中目标文件夹
    Process.run('explorer', ['/select,', path]);
  }

  void _openWithDefault(String path) {
    // Windows 下 start 命令用默认程序打开文件夹
    Process.run('explorer', [path]);
  }
}