import 'package:flutter/material.dart';
import '../models/goto_entry.dart';

/// goto 列表编辑器：每条显示 name + uuid + path 输入框，可添加/删除。
///
/// 使用持久化 TextEditingController 列表，避免每次 build 新建控制器
/// 打断中文输入法组合（IME composition）导致拼音碎片化重复。
class GotoEditor extends StatefulWidget {
  final List<GotoEntry> entries;
  final ValueChanged<List<GotoEntry>> onChanged;

  const GotoEditor({
    super.key,
    required this.entries,
    required this.onChanged,
  });

  @override
  State<GotoEditor> createState() => _GotoEditorState();
}

class _GotoEditorState extends State<GotoEditor> {
  final List<TextEditingController> _nameCtrls = [];
  final List<TextEditingController> _uuidCtrls = [];
  final List<TextEditingController> _pathCtrls = [];

  @override
  void initState() {
    super.initState();
    _syncControllers(widget.entries);
  }

  void _syncControllers(List<GotoEntry> list) {
    while (_nameCtrls.length < list.length) {
      _nameCtrls.add(TextEditingController());
      _uuidCtrls.add(TextEditingController());
      _pathCtrls.add(TextEditingController());
    }
    while (_nameCtrls.length > list.length) {
      _nameCtrls.removeLast().dispose();
      _uuidCtrls.removeLast().dispose();
      _pathCtrls.removeLast().dispose();
    }
    for (int i = 0; i < list.length; i++) {
      _nameCtrls[i].text = list[i].name;
      _uuidCtrls[i].text = list[i].uuid;
      _pathCtrls[i].text = list[i].path ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in _nameCtrls) {
      c.dispose();
    }
    for (final c in _uuidCtrls) {
      c.dispose();
    }
    for (final c in _pathCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _notify() {
    final list = <GotoEntry>[];
    for (int i = 0; i < _nameCtrls.length; i++) {
      list.add(GotoEntry(
        name: _nameCtrls[i].text,
        uuid: _uuidCtrls[i].text.trim(),
        path: _pathCtrls[i].text.trim().isEmpty ? null : _pathCtrls[i].text.trim(),
      ));
    }
    widget.onChanged(list);
  }

  void _add() {
    setState(() {
      final newList = List<GotoEntry>.of(widget.entries)
        ..add(const GotoEntry(name: ''));
      _syncControllers(newList);
      widget.onChanged(newList);
    });
  }

  void _remove(int index) {
    setState(() {
      final newList = List<GotoEntry>.of(widget.entries)..removeAt(index);
      _syncControllers(newList);
      widget.onChanged(newList);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _nameCtrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _nameCtrls[i],
                    style: TextStyle(fontSize: 11, color: cs.onSurface),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '名称',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    onChanged: (_) => _notify(),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _pathCtrls[i],
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurface, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '相对路径（可空）',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    onChanged: (_) => _notify(),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _uuidCtrls[i],
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurface, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'uuid（可空）',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    onChanged: (_) => _notify(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 16),
                  color: Colors.red.shade400,
                  padding: const EdgeInsets.all(2),
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => _remove(i),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add, size: 14),
          label: const Text('添加关联', style: TextStyle(fontSize: 11)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}
