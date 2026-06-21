import 'package:flutter/material.dart';
import '../models/item_info.dart';
import '../models/library_item.dart';
import '../providers/library_state.dart';
import '../services/preset_service.dart';

class EditDialog extends StatefulWidget {
  final List<LibraryItem> targets;
  final bool isBatch;
  final LibraryState state;

  const EditDialog({
    super.key,
    required this.targets,
    required this.isBatch,
    required this.state,
  });

  @override
  State<EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<EditDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _creatorCtrl;
  late TextEditingController _classCtrl;
  late TextEditingController _tagsCtrl;

  String _type = 'application';
  String _contentRating = 'G';
  int _rating = 10;

  bool _isSaving = false;

  bool _cbDesc = false;
  bool _cbCreator = false;
  bool _cbType = false;
  bool _cbContentRating = false;
  bool _cbRating = false;
  bool _cbClass = false;
  bool _cbTags = false;

  String _classMode = 'overwrite';
  String _tagsMode = 'overwrite';

  Map<String, List<String>> _presets = {};

  @override
  void initState() {
    super.initState();
    _loadPresets();
    if (!widget.isBatch) {
      final info = widget.targets.first.info;
      _titleCtrl = TextEditingController(text: info.title);
      _descCtrl = TextEditingController(text: info.description);
      _creatorCtrl = TextEditingController(text: info.creator ?? '');
      _type = info.type;
      _contentRating = info.contentRating;
      _rating = info.rating;
      _classCtrl = TextEditingController(text: info.classes.join(', '));
      _tagsCtrl = TextEditingController(text: info.tags.join(', '));
    } else {
      _titleCtrl = TextEditingController();
      _descCtrl = TextEditingController();
      _creatorCtrl = TextEditingController();
      _classCtrl = TextEditingController();
      _tagsCtrl = TextEditingController();
    }
  }

  Future<void> _loadPresets() async {
    final presets = await PresetService.loadAll();
    setState(() => _presets = presets);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _creatorCtrl.dispose();
    _classCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      title: Text(
        widget.isBatch
            ? '批量编辑 (${widget.targets.length} 项)'
            : '编辑：${widget.targets.first.info.title}',
        style: const TextStyle(fontSize: 14),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.isBatch) ...[
                _buildField('标题', _titleCtrl),
                const SizedBox(height: 8),
                _buildField('描述', _descCtrl, maxLines: 2),
                const SizedBox(height: 8),
                _buildPresetField('创建者', _creatorCtrl, 'creator'),
                const SizedBox(height: 8),
              ],
              if (widget.isBatch) ...[
                _buildCheckableField('描述', _cbDesc, _buildField('', _descCtrl, maxLines: 2)),
                const SizedBox(height: 6),
                _buildCheckableField('创建者', _cbCreator, _buildPresetField('', _creatorCtrl, 'creator')),
                const SizedBox(height: 6),
              ],
              _buildRowFields(
                _buildDropdownField('类型', _type, _typeOptions, (v) => setState(() => _type = v!), widget.isBatch),
                _buildDropdownField('分级', _contentRating, _ratingOptions, (v) => setState(() => _contentRating = v!), widget.isBatch),
              ),
              const SizedBox(height: 8),
              if (!widget.isBatch) _buildRatingSlider(),
              if (widget.isBatch) _buildCheckableField('评分', _cbRating, _buildRatingSlider()),
              const SizedBox(height: 8),
              _buildClassOrTagsSection('class'),
              const SizedBox(height: 8),
              _buildClassOrTagsSection('tags'),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(fontSize: 12)),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  List<String> get _typeOptions => _presets['type'] ?? PresetService.defaults['type']!;
  List<String> get _ratingOptions => _presets['contentRating'] ?? PresetService.defaults['contentRating']!;

  Widget _buildCheckableField(String label, bool checked, Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 24,
          height: 32,
          child: Checkbox(
            value: checked,
            onChanged: (v) => setState(() {
              if (label == '描述') { _cbDesc = v ?? false; }
              else if (label == '创建者') { _cbCreator = v ?? false; }
              else if (label == '评分') { _cbRating = v ?? false; }
              else if (label == 'types') { _cbType = v ?? false; }
              else if (label == 'ratings') { _cbContentRating = v ?? false; }
            }),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty && label != 'types' && label != 'ratings')
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ),
              child,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRowFields(Widget left, Widget right) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {int maxLines = 1}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: TextStyle(fontSize: 12, color: cs.onSurface),
          decoration: _inputDecoration(),
        ),
      ],
    );
  }

  Widget _buildPresetField(String label, TextEditingController ctrl, String presetKey) {
    final cs = Theme.of(context).colorScheme;
    final presets = _presets[presetKey] ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: ctrl.text),
          optionsBuilder: (textEditingValue) {
            if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
            return presets.where((option) =>
                option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
          },
          onSelected: (selection) {
            if (presetKey == 'class' || presetKey == 'tags') {
              final current = ctrl.text.trim();
              final parts = current.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              if (!parts.contains(selection)) {
                parts.add(selection);
                ctrl.text = parts.join(', ');
                ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
              }
            } else {
              ctrl.text = selection;
              ctrl.selection = TextSelection.collapsed(offset: selection.length);
            }
          },
          fieldViewBuilder: (context, acController, focusNode, onSubmitted) {
            return TextField(
              controller: acController,
              focusNode: focusNode,
              style: TextStyle(fontSize: 12, color: cs.onSurface),
              onChanged: (v) => ctrl.text = v,
              decoration: _inputDecoration(),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: cs.surface,
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: (options.length * 32).clamp(0, 160).toDouble(),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Text(option, style: TextStyle(fontSize: 12, color: cs.onSurface)),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDropdownField(String label, String value, List<String> options, ValueChanged<String?> onChanged, bool isBatch) {
    final cs = Theme.of(context).colorScheme;
    final content = DropdownButtonFormField<String>(
      initialValue: options.contains(value) ? value : null,
      isDense: true,
      style: TextStyle(fontSize: 12, color: cs.onSurface),
      decoration: _inputDecoration(),
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o, style: TextStyle(fontSize: 12, color: cs.onSurface))))
          .toList(),
      onChanged: onChanged,
    );
    if (isBatch) {
      final cbLabel = label == '类型' ? 'types' : 'ratings';
      return _buildCheckableField(cbLabel, label == '类型' ? _cbType : _cbContentRating, content);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
        content,
      ],
    );
  }

  Widget _buildRatingSlider() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('评分：${(_rating / 2).toStringAsFixed(1)} / 5',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        SizedBox(
          height: 32,
          child: Slider(
            value: _rating.toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            onChanged: (v) => setState(() => _rating = v.round()),
          ),
        ),
      ],
    );
  }

  Widget _buildClassOrTagsSection(String key) {
    final isClass = key == 'class';
    final label = isClass ? '分类标签 (class, 逗号分隔)' : '标签 (tags, 逗号分隔)';
    final ctrl = isClass ? _classCtrl : _tagsCtrl;
    final checked = isClass ? _cbClass : _cbTags;
    final mode = isClass ? _classMode : _tagsMode;

    if (!widget.isBatch) {
      return _buildPresetField(label, ctrl, key);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 32,
              child: Checkbox(
                value: checked,
                onChanged: (v) => setState(() {
                  if (isClass) { _cbClass = v ?? false; }
                  else { _cbTags = v ?? false; }
                }),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            Expanded(child: _buildPresetField(label, ctrl, key)),
          ],
        ),
        if (checked) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: _buildModeRadios(mode, (v) {
              setState(() {
                if (isClass) { _classMode = v; }
                else { _tagsMode = v; }
              });
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildModeRadios(String currentMode, ValueChanged<String> onChanged) {
    return Row(
      children: [
        _buildRadio('覆盖', 'overwrite', currentMode, onChanged),
        const SizedBox(width: 8),
        _buildRadio('追加', 'append', currentMode, onChanged),
        const SizedBox(width: 8),
        _buildRadio('删除', 'remove', currentMode, onChanged),
      ],
    );
  }

  Widget _buildRadio(String label, String value, String currentMode, ValueChanged<String> onChanged) {
    final cs = Theme.of(context).colorScheme;
    final selected = currentMode == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? cs.primary : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration() {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
    );
  }

  List<String> _parseList(String text) {
    return text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      if (!widget.isBatch) {
        final newInfo = ItemInfo(
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          creator: _creatorCtrl.text.trim().isEmpty ? null : _creatorCtrl.text.trim(),
          type: _type,
          contentRating: _contentRating,
          rating: _rating,
          tags: _parseList(_tagsCtrl.text),
          classes: _parseList(_classCtrl.text),
        );
        await widget.state.saveItemInfo(widget.targets.first.path, newInfo);
      } else {
        await widget.state.batchEditItems(
          itemPaths: widget.targets.map((e) => e.path).toList(),
          description: _cbDesc ? _descCtrl.text.trim() : null,
          type: _cbType ? _type : null,
          contentRating: _cbContentRating ? _contentRating : null,
          tags: _cbTags ? _parseList(_tagsCtrl.text) : null,
          classes: _cbClass ? _parseList(_classCtrl.text) : null,
          classMode: _classMode,
          tagsMode: _tagsMode,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
