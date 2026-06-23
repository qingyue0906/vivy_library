import 'package:flutter/material.dart';
import '../models/goto_entry.dart';

/// goto 列表编辑器：每条显示 name + uuid 输入框，可添加/删除。
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
  late List<GotoEntry> _list;

  @override
  void initState() {
    super.initState();
    _list = List.of(widget.entries);
  }

  void _notify() => widget.onChanged(List.of(_list));

  void _add() {
    setState(() => _list.add(const GotoEntry(name: '', uuid: '')));
    _notify();
  }

  void _remove(int index) {
    setState(() => _list.removeAt(index));
    _notify();
  }

  void _update(int index, {String? name, String? uuid}) {
    setState(() {
      _list[index] = _list[index].copyWith(name: name, uuid: uuid);
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _list.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: TextEditingController(text: _list[i].name)
                      ..selection = TextSelection.collapsed(
                        offset: _list[i].name.length,
                      ),
                    style: TextStyle(fontSize: 11, color: cs.onSurface),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '名称',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    onChanged: (v) => _update(i, name: v),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: _list[i].uuid)
                      ..selection = TextSelection.collapsed(
                        offset: _list[i].uuid.length,
                      ),
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurface, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'uuid',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    onChanged: (v) => _update(i, uuid: v),
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
