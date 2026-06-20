import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/library_root.dart';
import '../services/library_root_service.dart';
import 'dart:io';

/// 顶部"资源库选择"按钮 + 浮层。
/// 按钮本身用 CompositedTransformTarget 包裹作为锚点,
/// 点击后通过 Overlay 插入一个紧贴按钮下方的浮层(搜索 + 列表 + 打开其他)。
class LibraryRootSelector extends StatefulWidget {
  final String currentPath;
  final void Function(String path) onRootSelected;

  const LibraryRootSelector({
    super.key,
    required this.currentPath,
    required this.onRootSelected,
  });

  @override
  State<LibraryRootSelector> createState() => _LibraryRootSelectorState();
}

class _LibraryRootSelectorState extends State<LibraryRootSelector> {
  // LayerLink 是锚点和浮层之间"位置同步"的纽带,两边必须用同一个实例
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay(); // widget 销毁时记得清理浮层,避免残留
    super.dispose();
  }

  void _toggleOverlay() {
    if (_overlayEntry != null) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => _buildOverlayContent(),
    );
    overlay.insert(_overlayEntry!);
  }

  Widget _buildOverlayContent() {
    return Stack(
      children: [
        // 一个铺满全屏的透明层,点击浮层以外的区域时关闭浮层,
        // 这是下拉菜单/选择器类组件的标准交互:点外面自动收起
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _removeOverlay,
            child: Container(color: Colors.transparent),
          ),
        ),
        // CompositedTransformFollower:真正紧贴锚点出现的浮层内容
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 36), // 浮层出现在按钮下方,留出按钮自身高度的间距
          child: _LibraryRootPanel(
            currentPath: widget.currentPath,
            onSelect: (path) {
              widget.onRootSelected(path);
              _removeOverlay();
            },
            onClose: _removeOverlay,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // CompositedTransformTarget 包住按钮本身,作为浮层定位的锚点
    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _toggleOverlay,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.video_library, size: 15),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  _displayLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _displayLabel() {
    if (widget.currentPath.isEmpty) return '选择资源库';
    final segments = widget.currentPath.replaceAll('\\', '/').split('/');
    return segments.last; // 显示路径最后一段作为简短标签
  }
}

/// 浮层内部的实际内容:搜索框 + 已添加资源库列表 + 打开其他资源库按钮
class _LibraryRootPanel extends StatefulWidget {
  final String currentPath;
  final void Function(String path) onSelect;
  final VoidCallback onClose;

  const _LibraryRootPanel({
    required this.currentPath,
    required this.onSelect,
    required this.onClose,
  });

  @override
  State<_LibraryRootPanel> createState() => _LibraryRootPanelState();
}

class _LibraryRootPanelState extends State<_LibraryRootPanel> {
  final LibraryRootService _service = LibraryRootService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<LibraryRoot> _allRoots = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRoots() async {
    final roots = await _service.loadAll();
    setState(() {
      _allRoots = roots;
      _isLoading = false;
    });
  }

  List<LibraryRoot> get _filteredRoots {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _allRoots;
    return _allRoots
        .where((r) =>
            r.name.toLowerCase().contains(query) ||
            r.path.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _openOtherLibrary() async {
    // FilePicker 的 getDirectoryPath 专门用来选择文件夹(不是文件),
    // 对应 Windows 的"选择文件夹"对话框
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择资源库根目录',
    );
    if (path == null) return;

    final name = path.replaceAll('\\', '/').split('/').last;
    final newRoot = LibraryRoot(name: name, path: path);
    final updated = await _service.addRoot(newRoot);

    setState(() => _allRoots = updated);
    widget.onSelect(path);
  }

  Future<void> _removeRoot(LibraryRoot root) async {
    final updated = await _service.removeRoot(root.path);
    setState(() => _allRoots = updated);
  }

  void _showItemMenu(BuildContext context, LibraryRoot root, Offset globalPos) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1),
      constraints: const BoxConstraints(minWidth: 140),
      items: const [
        PopupMenuItem(
          value: 'open_explorer',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 14),
              SizedBox(width: 8),
              Text('在资源管理器中打开', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'remove',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 14, color: Colors.red),
              SizedBox(width: 8),
              Text('从列表中删除',
                  style: TextStyle(fontSize: 12, color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'remove') {
        _removeRoot(root);
      } else if (value == 'open_explorer') {
        // 用 Process 打开资源管理器到该路径
        // 这里复用之前已经熟悉的 dart:io Process 调用
        // ignore: discarded_futures
        Process.run('explorer', [root.path]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      // Material 包裹是必须的:OverlayEntry 里的内容默认没有 Material 祖先,
      // 像 InkWell 水波纹、阴影这些 Material 风格效果需要它才能正常显示
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 360),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 第一行:搜索框
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: '搜索资源库名称或路径...',
                        prefixIcon: const Icon(Icons.search, size: 16),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),

                  // 第二行:已添加资源库列表,多个时一行一个纵向排列
                  Flexible(
                    child: _filteredRoots.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _allRoots.isEmpty ? '还没有添加任何资源库' : '没有匹配的资源库',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _filteredRoots.length,
                            itemBuilder: (context, index) {
                              final root = _filteredRoots[index];
                              final isCurrent = root.path == widget.currentPath;
                              return ListTile(
                                dense: true,
                                selected: isCurrent,
                                selectedTileColor: Colors.blue.shade50,
                                leading: const Icon(Icons.folder, size: 16),
                                title: Text(root.name,
                                    style: const TextStyle(fontSize: 12.5)),
                                subtitle: Text(
                                  root.path,
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey.shade500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => widget.onSelect(root.path),
                                trailing: GestureDetector(
                                  onTapUp: (details) => _showItemMenu(
                                      context, root, details.globalPosition),
                                  child: const Icon(Icons.more_vert, size: 16),
                                ),
                              );
                            },
                          ),
                  ),

                  const Divider(height: 1),

                  // 第三行:打开其他资源库
                  InkWell(
                    onTap: _openOtherLibrary,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.create_new_folder_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('打开其他资源库...',
                              style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}