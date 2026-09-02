import 'dart:io';

import 'package:flutter/material.dart';

import '../models/snapshot_meta.dart';
import '../providers/library_state.dart';
import '../services/snapshot_service.dart';
import '../services/translations.dart';
import 'smooth_scroll.dart';

/// 资源库按钮右键弹出的快照面板：
/// - 顶部：创建快照（快照模式下禁用）
/// - 中部：当前资源库的快照列表（拖拽排序 / 原地重命名 / 删除确认）
/// - 底部：管理所有快照、打开快照文件夹
///
/// 交互逻辑与资源库选择面板一致（拖拽手柄、行内展开菜单），
/// 避免引入新的交互范式。
class SnapshotPanel extends StatefulWidget {
  final LibraryState state;
  const SnapshotPanel({super.key, required this.state});

  @override
  State<SnapshotPanel> createState() => _SnapshotPanelState();
}

class _SnapshotPanelState extends State<SnapshotPanel> {
  List<SnapshotMeta> _snapshots = [];
  bool _isLoading = true;
  bool _showAll = false; // "管理所有快照"视图
  bool _creating = false; // 创建进行中，防重复触发
  String? _expandedId;
  String? _renamingId;
  final TextEditingController _renameCtrl = TextEditingController();

  LibraryState get _state => widget.state;
  String get _libPath => _state.currentRootPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _renameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = _showAll
        ? await SnapshotService.listAll()
        : (_libPath.isEmpty
            ? <SnapshotMeta>[]
            : await SnapshotService.listFor(_libPath));
    if (!mounted) return;
    setState(() {
      _snapshots = list;
      _isLoading = false;
    });
  }

  Future<void> _refresh() async {
    await _load();
  }

  // ===== 创建 =====

  /// 弹出创建对话框。controller 由 [_SnapshotCreateDialog] 自行管理生命周期，
  /// 避免在路由退出动画期间访问已 dispose 的 controller 造成元素树损坏。
  Future<void> _create() async {
    if (_creating) return;
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final defaultName = '${Strings.t('snapshot')} '
        '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}';

    final result = await showDialog<({String name, String note})>(
      context: context,
      builder: (_) => _SnapshotCreateDialog(defaultName: defaultName),
    );
    if (result == null || !mounted) return;
    final name = result.name.trim();
    if (name.isEmpty) return;

    _creating = true;
    try {
      await _state.createSnapshot(name: name, note: result.note.trim());
    } finally {
      _creating = false;
    }
    if (!mounted) return;
    await _refresh();
  }

  // ===== 选中 / 重命名 / 删除 =====

  Future<void> _enter(SnapshotMeta meta) async {
    final ok = await _state.loadSnapshot(meta);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Strings.t('snapshotLoadFailed')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _startRename(SnapshotMeta meta) {
    setState(() {
      _expandedId = null;
      _renamingId = meta.id;
      _renameCtrl.text = meta.name;
    });
  }

  void _cancelRename() => setState(() => _renamingId = null);

  Future<void> _confirmRename(SnapshotMeta meta) async {
    final newName = _renameCtrl.text.trim();
    setState(() => _renamingId = null);
    if (newName.isEmpty || newName == meta.name) return;
    await SnapshotService.rename(_libPath, meta.id, newName, meta.note);
    await _refresh();
  }

  Future<void> _delete(SnapshotMeta meta) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Strings.t('deleteSnapshot'), style: const TextStyle(fontSize: 15)),
        content: Text(Strings.tn('deleteSnapshotConfirm', {'name': meta.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(Strings.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(Strings.t('deleteSnapshot')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await SnapshotService.delete(_libPath, meta.id);
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _snapshots.removeAt(oldIndex);
    _snapshots.insert(newIndex, item);
    await SnapshotService.reorder(
      _libPath,
      _snapshots.map((m) => m.id).toList(),
    );
    if (mounted) setState(() {});
  }

  // ===== 构建 =====

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canCreate = !_state.isSnapshotMode && _libPath.isNotEmpty;
    return Material(
      color: cs.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题 + 创建按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.photo_camera, size: 15, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _showAll
                          ? Strings.t('manageAllSnapshots')
                          : Strings.t('snapshotManagement'),
                      style: TextStyle(fontSize: 12.5, color: cs.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_showAll)
                    TextButton(
                      onPressed: () {
                        setState(() => _showAll = false);
                        _refresh();
                      },
                      child: Text(Strings.t('back'), style: const TextStyle(fontSize: 12)),
                    )
                  else
                    TextButton.icon(
                      onPressed: (canCreate && !_creating) ? _create : null,
                      icon: const Icon(Icons.add, size: 15),
                      label: Text(
                        Strings.t('createSnapshot'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 列表
            Flexible(
              child: _isLoading
                  ? const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _snapshots.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Center(
                            child: Text(
                              _showAll
                                  ? Strings.t('noSnapshotsAll')
                                  : Strings.t('noSnapshots'),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ),
                        )
                      : (_showAll
                          ? SmoothScroll(
                              builder: (context, controller, physics) => ListView(
                                controller: controller,
                                physics: physics,
                                // 注意：不能用 shrinkWrap，否则内容超出面板高度时
                                // 会撑高 SmoothScroll 的 Stack 造成 RenderFlex 溢出。
                                children: [
                                  for (final meta in _snapshots)
                                    _buildTile(meta, showLibrary: true),
                                ],
                              ),
                            )
                          : SmoothScroll(
                              builder: (context, controller, physics) =>
                                  ReorderableListView.builder(
                                scrollController: controller,
                                physics: physics,
                                buildDefaultDragHandles: false,
                                onReorder: _onReorder,
                                proxyDecorator: (child, index, animation) {
                                  final cs = Theme.of(context).colorScheme;
                                  return Material(
                                    color: cs.surfaceContainerHigh,
                                    elevation: 4,
                                    borderRadius: BorderRadius.circular(8),
                                    child: child,
                                  );
                                },
                                itemCount: _snapshots.length,
                                itemBuilder: (context, i) => _buildTile(
                                  _snapshots[i],
                                  dragHandle: ReorderableDragStartListener(
                                    index: i,
                                    child: Icon(
                                      Icons.drag_indicator,
                                      size: 15,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            )),
            ),
            const Divider(height: 1),
            // 底部：管理所有快照 / 打开快照文件夹
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() => _showAll = true);
                    _refresh();
                  },
                  icon: const Icon(Icons.history, size: 15),
                  label: Text(
                    Strings.t('manageAllSnapshots'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _openSnapshotRoot,
                  icon: const Icon(Icons.folder_open, size: 15),
                  label: Text(
                    Strings.t('openSnapshotDir'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openSnapshotRoot() {
    Process.run('explorer', [SnapshotService.snapshotRoot]);
  }

  Widget _buildTile(SnapshotMeta meta, {Widget? dragHandle, bool showLibrary = false}) {
    return Column(
      key: ValueKey(meta.id),
      children: [
        ListTile(
          dense: true,
          selected: _state.isSnapshotMode &&
              _state.activeSnapshot?.id == meta.id,
          selectedTileColor:
              Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
          leading: dragHandle ??
              Icon(Icons.photo_camera, size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
          title: Text(
            showLibrary ? _libraryLabel(meta) : meta.name,
            style: const TextStyle(fontSize: 12.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${_formatDate(meta.createdAt)} · ${_formatSize(meta.sizeBytes)}',
            style: TextStyle(
                fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _enter(meta),
          trailing: InkWell(
            onTap: () {
              setState(() => _expandedId = _expandedId == meta.id ? null : meta.id);
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                _expandedId == meta.id ? Icons.expand_less : Icons.expand_more,
                size: 16,
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: _renamingId == meta.id
              ? _buildRenameRow(meta)
              : (_expandedId == meta.id ? _buildMenu(meta) : const SizedBox(width: double.infinity)),
        ),
      ],
    );
  }

  String _libraryLabel(SnapshotMeta meta) {
    final seg = meta.sourcePath.replaceAll('\\', '/').split('/');
    return '${seg.last} · ${meta.name}';
  }

  Widget _buildRenameRow(SnapshotMeta meta) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _renameCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: Strings.t('snapshotName'),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onSubmitted: (_) => _confirmRename(meta),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check, size: 16, color: Colors.green),
              onPressed: () => _confirmRename(meta),
              tooltip: Strings.t('save'),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.grey),
              onPressed: _cancelRename,
              tooltip: Strings.t('cancel'),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenu(SnapshotMeta meta) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          _menuItem(
            context,
            icon: Icons.drive_file_rename_outline,
            label: Strings.t('renameSnapshot'),
            onTap: () => _startRename(meta),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          _menuItem(
            context,
            icon: Icons.delete_outline,
            label: Strings.t('deleteSnapshot'),
            onTap: () => _delete(meta),
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _menuItem(BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = isDestructive ? Colors.red : cs.onSurface;
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

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}

/// 创建快照对话框：controller 由本 State 持有并在路由真正销毁时 dispose，
/// 避免"路由 pop 后退出动画期间访问已 dispose 的 controller"导致元素树损坏。
class _SnapshotCreateDialog extends StatefulWidget {
  final String defaultName;
  const _SnapshotCreateDialog({required this.defaultName});

  @override
  State<_SnapshotCreateDialog> createState() => _SnapshotCreateDialogState();
}

class _SnapshotCreateDialogState extends State<_SnapshotCreateDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.defaultName);
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop((name: _nameCtrl.text, note: _noteCtrl.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Strings.t('createSnapshot'), style: const TextStyle(fontSize: 15)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: Strings.t('snapshotName'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            style: const TextStyle(fontSize: 13),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: Strings.t('snapshotNote'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            style: const TextStyle(fontSize: 13),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(Strings.t('cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(Strings.t('createSnapshot')),
        ),
      ],
    );
  }
}
