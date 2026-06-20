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
  void _showPanel() {
    showGeneralDialog(
      context: context,
      barrierLabel: '资源库选择器',
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.05), // 很淡的遮罩,不会让背景明显变暗
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (context, animation, secondaryAnimation) {
        // 用 Align 把面板固定显示在屏幕左上区域,
        // 大致对应资源库按钮在左侧栏顶部的位置,
        // 不再追踪按钮的精确实时坐标,换取稳定性
        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 100, left: 12),
            child: _LibraryRootPanel(
              currentPath: widget.currentPath,
              onSelect: (path) {
                widget.onRootSelected(path);
                Navigator.of(context).pop();
              },
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _showPanel,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(Icons.video_library, size: 15),
            const SizedBox(width: 6),
            Expanded(
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
    );
  }

  String _displayLabel() {
    if (widget.currentPath.isEmpty) return '选择资源库';
    final segments = widget.currentPath.replaceAll('\\', '/').split('/');
    return segments.last;
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
  String? _expandedPath;
  String? _renamingPath; // 当前正在原地重命名的项,null 表示没有
  final TextEditingController _renameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _renameCtrl.dispose(); // 新增
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
    setState(() => _expandedPath = null);
    final updated = await _service.removeRoot(root.path);
    setState(() => _allRoots = updated);
  }

  void _startRename(LibraryRoot root) {
    setState(() {
      _expandedPath = null; // 进入重命名时,收起菜单
      _renamingPath = root.path;
      _renameCtrl.text = root.name;
    });
  }

  void _cancelRename() {
    setState(() => _renamingPath = null);
  }

  Future<void> _confirmRename(LibraryRoot root) async {
    final newName = _renameCtrl.text.trim();
    setState(() => _renamingPath = null);

    if (newName.isEmpty || newName == root.name) return;

    final updated = await _service.renameRoot(root.path, newName);
    setState(() => _allRoots = updated);
  }

  void _toggleExpanded(String path) {
    setState(() {
      _expandedPath = _expandedPath == path ? null : path;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
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
                        // 用普通 ListView(非 builder)+ Column 拼装,
                        // 因为现在每一项可能带展开的子菜单,高度不固定,
                        // 数据量本身也不大(用户添加的资源库数量通常很少),
                        // 不需要 builder 的按需渲染优化,用最简单可靠的方式拼装
                        : ListView(
                            shrinkWrap: true,
                            children: _filteredRoots
                                .map((root) => _RootListTile(
                                      key: ValueKey(root.path),
                                      root: root,
                                      isCurrent: root.path == widget.currentPath,
                                      isExpanded: _expandedPath == root.path,
                                      isRenaming: _renamingPath == root.path,
                                      renameController: _renameCtrl,
                                      onSelect: () => widget.onSelect(root.path),
                                      onToggleExpanded: () => _toggleExpanded(root.path),
                                      onStartRename: () => _startRename(root),
                                      onConfirmRename: () => _confirmRename(root),
                                      onCancelRename: _cancelRename,
                                      onRemove: () => _removeRoot(root),
                                      onOpenExplorer: () => Process.run('explorer', [root.path]),
                                    ))
                                .toList(),
                          ),
                  ),
                  const Divider(height: 1),
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

/// 单个资源库列表项。点击 more 按钮时,在这一项下方原地展开菜单选项,
/// 不依赖 Overlay/LayerLink,彻底规避列表项被回收导致的渲染崩溃问题。
class _RootListTile extends StatelessWidget {
  final LibraryRoot root;
  final bool isCurrent;
  final bool isExpanded;
  final bool isRenaming;
  final TextEditingController renameController;
  final VoidCallback onSelect;
  final VoidCallback onToggleExpanded;
  final VoidCallback onStartRename;
  final VoidCallback onConfirmRename;
  final VoidCallback onCancelRename;
  final VoidCallback onRemove;
  final VoidCallback onOpenExplorer;

  const _RootListTile({
    super.key,
    required this.root,
    required this.isCurrent,
    required this.isExpanded,
    required this.isRenaming,
    required this.renameController,
    required this.onSelect,
    required this.onToggleExpanded,
    required this.onStartRename,
    required this.onConfirmRename,
    required this.onCancelRename,
    required this.onRemove,
    required this.onOpenExplorer,
  });

  @override
  Widget build(BuildContext context) {
      return Column(
        children: [
          ListTile(
            dense: true,
            selected: isCurrent,
            selectedTileColor: Colors.blue.shade50,
            leading: const Icon(Icons.folder, size: 16),
            title: Text(root.name, style: const TextStyle(fontSize: 12.5)),
            subtitle: Text(
              root.path,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: onSelect,
            trailing: InkWell(
              onTap: onToggleExpanded,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
              ),
            ),
          ),

          // AnimatedSize 包裹这块会动态出现/消失的内容,
          // 让高度变化平滑过渡,避免单帧内的尺寸跳变冲击外层 Follower 的布局计算
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: isRenaming
                ? _buildRenameRow()
                : (isExpanded ? _buildMenu() : const SizedBox(width: double.infinity)),
          ),
        ],
      );
    }

  Widget _buildRenameRow() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: renameController,
              autofocus: true,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                hintText: '资源库显示名称',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onSubmitted: (_) => onConfirmRename(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check, size: 16, color: Colors.green),
            onPressed: onConfirmRename,
            tooltip: '保存',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.grey),
            onPressed: onCancelRename,
            tooltip: '取消',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildMenu() {
    return Container(
      color: Colors.grey.shade50,
      child: Column(
        children: [
          _menuItem(
            icon: Icons.drive_file_rename_outline,
            label: '命名资源库',
            onTap: onStartRename,
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          _menuItem(
            icon: Icons.folder_open,
            label: '在资源管理器中打开',
            onTap: onOpenExplorer,
          ),
          _menuItem(
            icon: Icons.delete_outline,
            label: '从列表中删除',
            onTap: onRemove,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? Colors.red : const Color(0xFF333333);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 32, right: 12, top: 9, bottom: 9),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 12.5, color: color)),
          ],
        ),
      ),
    );
  }
}