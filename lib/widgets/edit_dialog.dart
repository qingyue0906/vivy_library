import 'package:flutter/material.dart';
import '../models/item_info.dart';
import '../models/goto_entry.dart';
import '../models/library_item.dart';
import '../models/category_node.dart';
import '../providers/library_state.dart';
import '../services/translations.dart';
import 'goto_editor.dart';
import 'smooth_scroll.dart';

const _kDesc = 'kDesc';
const _kCreator = 'kCreator';
const _kRating = 'kRating';
const _kType = 'kType';
const _kContentRating = 'kContentRating';
const _kDefine = 'kDefine';
const _kPreview = 'kPreview';
const _kStar = 'kStar';

class EditDialog extends StatefulWidget {
  final List<LibraryItem> targets;
  final bool isBatch;
  final LibraryState state;
  final List<CategoryNode> folderTargets;

  const EditDialog({
    super.key,
    required this.targets,
    required this.isBatch,
    required this.state,
    this.folderTargets = const [],
  });

  @override
  State<EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<EditDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _creatorCtrl;
  late TextEditingController _typeCtrl;
  late TextEditingController _contentRatingCtrl;
  late TextEditingController _previewCtrl;
  List<String> _classes = [];
  List<String> _tags = [];
  int _rating = 10;
  String _define = 'item';
  bool _star = false;
  List<GotoEntry> _goto = [];

  bool _showClassInput = false;
  bool _showTagInput = false;
  late TextEditingController _classInputCtrl;
  late TextEditingController _tagInputCtrl;

  bool _isSaving = false;

  bool _cbDesc = false;
  bool _cbCreator = false;
  bool _cbType = false;
  bool _cbContentRating = false;
  bool _cbRating = false;
  bool _cbClass = false;
  bool _cbTags = false;
  bool _cbDefine = false;
  bool _cbPreview = false;
  bool _cbStar = false;
  bool _cbGoto = false;

  String _classMode = 'overwrite';
  String _tagsMode = 'overwrite';
  String _gotoMode = 'overwrite';

  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _classInputCtrl = TextEditingController();
    _tagInputCtrl = TextEditingController();
    if (widget.folderTargets.isNotEmpty && !widget.isBatch) {
      final info = widget.folderTargets.first.info ??
          ItemInfo.defaults(widget.folderTargets.first.name);
      _titleCtrl = TextEditingController(text: info.title);
      _descCtrl = TextEditingController(text: info.description);
      _creatorCtrl = TextEditingController(text: info.creator ?? '');
      _typeCtrl = TextEditingController(text: info.type);
      _contentRatingCtrl = TextEditingController(text: info.contentRating);
      _rating = info.rating;
      _define = info.define;
      _previewCtrl = TextEditingController(text: info.preview ?? '');
      _star = info.star;
      _goto = List.of(info.goto);
      _classes = List.of(info.classes);
      _tags = List.of(info.tags);
    } else if (widget.folderTargets.isNotEmpty && widget.isBatch) {
      _titleCtrl = TextEditingController();
      _descCtrl = TextEditingController();
      _creatorCtrl = TextEditingController();
      _typeCtrl = TextEditingController();
      _contentRatingCtrl = TextEditingController();
      _previewCtrl = TextEditingController();
    } else if (!widget.isBatch) {
      final info = widget.targets.first.info;
      _titleCtrl = TextEditingController(text: info.title);
      _descCtrl = TextEditingController(text: info.description);
      _creatorCtrl = TextEditingController(text: info.creator ?? '');
      _typeCtrl = TextEditingController(text: info.type);
      _contentRatingCtrl = TextEditingController(text: info.contentRating);
      _rating = info.rating;
      _define = info.define;
      _previewCtrl = TextEditingController(text: info.preview ?? '');
      _star = info.star;
      _goto = List.of(info.goto);
      _classes = List.of(info.classes);
      _tags = List.of(info.tags);
    } else {
      _titleCtrl = TextEditingController();
      _descCtrl = TextEditingController();
      _creatorCtrl = TextEditingController();
      _typeCtrl = TextEditingController();
      _contentRatingCtrl = TextEditingController();
      _previewCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _creatorCtrl.dispose();
    _typeCtrl.dispose();
    _contentRatingCtrl.dispose();
    _previewCtrl.dispose();
    _classInputCtrl.dispose();
    _tagInputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      title: Text(
        widget.folderTargets.isNotEmpty
            ? widget.isBatch
                ? Strings.tn('batchEditFolder', {'n': '${widget.folderTargets.length}'})
                : Strings.tn('editFolder', {'name': widget.folderTargets.first.name})
            : widget.isBatch
                ? Strings.tn('batchEdit', {'n': '${widget.targets.length}'})
                : Strings.tn('editItem', {'name': widget.targets.first.info.title}),
        style: const TextStyle(fontSize: 14),
      ),
      content: SizedBox(
        width: 420,
        child: SmoothScroll(
          builder: (context, controller, physics) => SingleChildScrollView(
            controller: controller,
            physics: physics,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              if (!widget.isBatch) ...[
                _buildField(Strings.t('title'), _titleCtrl),
                const SizedBox(height: 8),
                _buildField(Strings.t('description'), _descCtrl, maxLines: 4),
                const SizedBox(height: 8),
                _buildAutoField(label: Strings.t('creator'), controller: _creatorCtrl, options: widget.state.uniqueCreators),
                const SizedBox(height: 8),
              ],
              if (widget.isBatch) ...[
                _buildCheckableField(Strings.t('description'), _cbDesc, _buildField('', _descCtrl, maxLines: 4), id: _kDesc),
                const SizedBox(height: 6),
                _buildCheckableField(Strings.t('creator'), _cbCreator, _buildAutoField(label: '', controller: _creatorCtrl, options: widget.state.uniqueCreators), id: _kCreator),
                const SizedBox(height: 6),
              ],
              _buildRowFields(
                _buildAutoField(label: Strings.t('type'), controller: _typeCtrl, options: widget.state.uniqueTypes, isBatch: widget.isBatch, checked: _cbType, onCheckedChanged: (v) => _cbType = v, id: _kType),
                _buildAutoField(label: Strings.t('contentRating'), controller: _contentRatingCtrl, options: widget.state.uniqueContentRatings, isBatch: widget.isBatch, checked: _cbContentRating, onCheckedChanged: (v) => _cbContentRating = v, id: _kContentRating),
              ),
              const SizedBox(height: 8),
              if (!widget.isBatch) _buildRatingSlider(),
              if (widget.isBatch) _buildCheckableField(Strings.t('rating'), _cbRating, _buildRatingSlider(), id: _kRating),
              const SizedBox(height: 8),
              _buildChipSection(
                isClass: true,
                label: Strings.t('classLabel'),
                values: _classes,
                showInput: _showClassInput,
                suggestions: widget.state.uniqueClasses,
                inputCtrl: _classInputCtrl,
                onChanged: (v) => setState(() => _classes = v),
                onShowInputChanged: (v) => setState(() => _showClassInput = v),
                isBatch: widget.isBatch,
                checked: _cbClass,
                onCheckedChanged: (v) => _cbClass = v,
                mode: _classMode,
                onModeChanged: (v) => _classMode = v,
              ),
              const SizedBox(height: 8),
              _buildChipSection(
                isClass: false,
                label: Strings.t('tags'),
                values: _tags,
                showInput: _showTagInput,
                suggestions: widget.state.uniqueTags,
                inputCtrl: _tagInputCtrl,
                onChanged: (v) => setState(() => _tags = v),
                onShowInputChanged: (v) => setState(() => _showTagInput = v),
                isBatch: widget.isBatch,
                checked: _cbTags,
                onCheckedChanged: (v) => _cbTags = v,
                mode: _tagsMode,
                onModeChanged: (v) => _tagsMode = v,
              ),
              const SizedBox(height: 8),
              _buildStarField(widget.isBatch),
              const SizedBox(height: 8),
              _buildAdvancedToggle(),
              if (_showAdvanced) ...[
                const SizedBox(height: 8),
                _buildDefineField(widget.isBatch),
                const SizedBox(height: 8),
                _buildPreviewField(widget.isBatch),
                const SizedBox(height: 8),
                _buildGotoSection(),
              ],
            ],
          ),
        ),
      ),
    ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: Text(Strings.t('cancel'), style: const TextStyle(fontSize: 12)),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(Strings.t('save'), style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildAutoField({
    required String label,
    required TextEditingController controller,
    required List<String> options,
    bool isBatch = false,
    bool checked = false,
    ValueChanged<bool>? onCheckedChanged,
    String? id,
  }) {
    final cs = Theme.of(context).colorScheme;

    final content = Autocomplete<String>(
      initialValue: TextEditingValue(text: controller.text),
      optionsBuilder: (textEditingValue) {
        final text = textEditingValue.text.toLowerCase();
        if (text.isEmpty) return options;
        return options.where((o) => o.toLowerCase().contains(text));
      },
      onSelected: (selection) {
        controller.text = selection;
        controller.selection = TextSelection.collapsed(offset: selection.length);
      },
      fieldViewBuilder: (context, acController, focusNode, onSubmitted) {
        return TextField(
          controller: acController,
          focusNode: focusNode,
          style: TextStyle(fontSize: 12, color: cs.onSurface),
          onChanged: (v) => controller.text = v,
          decoration: _inputDecoration(),
        );
      },
      optionsViewBuilder: (context, onSelected, opts) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: cs.surface,
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: (opts.length * 32).clamp(0, 160).toDouble(),
              child: SmoothScroll(
                builder: (context, scrollController, physics) => ListView.builder(
                  controller: scrollController,
                  physics: physics,
                  padding: EdgeInsets.zero,
                  itemCount: opts.length,
                  itemBuilder: (context, index) {
                    final option = opts.elementAt(index);
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
          ),
        );
      },
    );

    if (isBatch) {
      return _buildCheckableField(label, checked, content, id: id);
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

  Widget _buildCheckableField(String label, bool checked, Widget child, {String? id}) {
    final cs = Theme.of(context).colorScheme;
    final showLabel = label.isNotEmpty && id != _kRating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 32,
              child: Checkbox(
                value: checked,
                onChanged: (v) => setState(() {
                  if (id == _kDesc) { _cbDesc = v ?? false; }
                  else if (id == _kCreator) { _cbCreator = v ?? false; }
                  else if (id == _kRating) { _cbRating = v ?? false; }
                  else if (id == _kType) { _cbType = v ?? false; }
                  else if (id == _kContentRating) { _cbContentRating = v ?? false; }
                  else if (id == _kDefine) { _cbDefine = v ?? false; }
                  else if (id == _kPreview) { _cbPreview = v ?? false; }
                  else if (id == _kStar) { _cbStar = v ?? false; }
                }),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            Expanded(child: child),
          ],
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

  Widget _buildChipSection({
    required bool isClass,
    required String label,
    required List<String> values,
    required bool showInput,
    required List<String> suggestions,
    required TextEditingController inputCtrl,
    required ValueChanged<List<String>> onChanged,
    required ValueChanged<bool> onShowInputChanged,
    bool isBatch = false,
    bool checked = false,
    ValueChanged<bool>? onCheckedChanged,
    String mode = 'overwrite',
    ValueChanged<String>? onModeChanged,
  }) {
    final cs = Theme.of(context).colorScheme;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...values.map((v) => Chip(
              label: Text(v, style: TextStyle(fontSize: 11, color: cs.onSurface)),
              deleteIcon: Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
              onDeleted: () => onChanged(values.where((x) => x != v).toList()),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              labelPadding: const EdgeInsets.only(left: 4, right: 2),
            )),
            if (showInput)
              _buildInlineChipInput(
                controller: inputCtrl,
                suggestions: suggestions,
                currentValues: values,
                onAdd: (v) {
                  if (!values.contains(v)) {
                    onChanged([...values, v]);
                  }
                  inputCtrl.clear();
                  onShowInputChanged(false);
                },
                onCancel: () {
                  inputCtrl.clear();
                  onShowInputChanged(false);
                },
              ),
            if (!showInput)
              ActionChip(
                avatar: Icon(Icons.add, size: 14, color: cs.primary),
                label: Text(Strings.t('add'), style: TextStyle(fontSize: 11, color: cs.primary)),
                onPressed: () => onShowInputChanged(true),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
          ],
        ),
      ],
    );

    if (!isBatch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          content,
        ],
      );
    }

    // 批量模式
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
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
            Expanded(child: content),
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

  Widget _buildInlineChipInput({
    required TextEditingController controller,
    required List<String> suggestions,
    required List<String> currentValues,
    required ValueChanged<String> onAdd,
    required VoidCallback onCancel,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        final text = textEditingValue.text.toLowerCase();
        if (text.isEmpty) return suggestions.where((s) => !currentValues.contains(s));
        return suggestions
            .where((s) => !currentValues.contains(s) && s.toLowerCase().contains(text));
      },
      onSelected: (selection) {
        onAdd(selection);
      },
      fieldViewBuilder: (context, acController, focusNode, onSubmitted) {
        return Container(
          width: 140,
          height: 28,
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: acController,
            focusNode: focusNode,
            autofocus: true,
            style: TextStyle(fontSize: 11, color: cs.onSurface),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              hintText: Strings.t('inputPlaceholder'),
              hintStyle: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              suffixIcon: IconButton(
                icon: Icon(Icons.check, size: 14, color: cs.primary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () {
                  final text = acController.text.trim();
                  if (text.isNotEmpty) {
                    onAdd(text);
                  } else {
                    onCancel();
                  }
                },
              ),
            ),
            onSubmitted: (value) {
              final text = value.trim();
              if (text.isNotEmpty) {
                onAdd(text);
              }
            },
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, opts) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: cs.surface,
            elevation: 4,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: (opts.length * 28).clamp(0, 140).toDouble(),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: opts.length,
                itemBuilder: (context, index) {
                  final option = opts.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Text(option, style: TextStyle(fontSize: 11, color: cs.onSurface)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRatingSlider() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(Strings.tn('ratingValue', {'n': (_rating / 2).toStringAsFixed(1)}),
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

  Widget _buildAdvancedToggle() {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
        icon: Icon(
          _showAdvanced ? Icons.expand_less : Icons.chevron_right,
          size: 18,
        ),
        label: Text(
          Strings.t('advanced'),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _buildDefineField(bool isBatch) {
    final cs = Theme.of(context).colorScheme;
    final content = DropdownButtonFormField<String>(
      initialValue: _define,
      isDense: true,
      style: TextStyle(fontSize: 12, color: cs.onSurface),
      decoration: _inputDecoration(),
      items: [
        DropdownMenuItem(value: 'item', child: Text(Strings.t('defineItem'))),
        DropdownMenuItem(value: 'dir', child: Text(Strings.t('defineDir'))),
        DropdownMenuItem(value: 'hide', child: Text(Strings.t('defineHide'))),
      ],
      onChanged: (v) => setState(() => _define = v ?? 'item'),
    );
    if (isBatch) {
      return _buildCheckableField(Strings.t('define'), _cbDefine, content, id: _kDefine);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(Strings.t('define'), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        content,
      ],
    );
  }

  Widget _buildPreviewField(bool isBatch) {
    if (isBatch) {
      return _buildCheckableField(Strings.t('preview'), _cbPreview,
          _buildField('', _previewCtrl), id: _kPreview);
    }
    return _buildField(Strings.t('previewHint'), _previewCtrl);
  }

  Widget _buildStarField(bool isBatch) {
    final cs = Theme.of(context).colorScheme;
    final content = Align(
      alignment: Alignment.centerLeft,
      child: Transform.scale(
        scale: 0.75,
        child: Switch(
          value: _star,
          onChanged: (v) => setState(() => _star = v),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
    if (isBatch) {
      return _buildCheckableField(Strings.t('star'), _cbStar, content, id: _kStar);
    }
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(Strings.t('star'), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildGotoSection() {
    final cs = Theme.of(context).colorScheme;
    if (!widget.isBatch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(Strings.t('gotoSection'),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          GotoEditor(
            entries: _goto,
            onChanged: (list) => _goto = list,
          ),
        ],
      );
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
                value: _cbGoto,
                onChanged: (v) => setState(() => _cbGoto = v ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            Expanded(
              child: Text(Strings.t('gotoSection'),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ),
          ],
        ),
        if (_cbGoto) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: _buildModeRadios(_gotoMode, (v) =>
                setState(() => _gotoMode = v)),
          ),
          const SizedBox(height: 4),
          GotoEditor(
            entries: _goto,
            onChanged: (list) => _goto = list,
          ),
        ],
      ],
    );
  }

  Widget _buildModeRadios(String currentMode, ValueChanged<String> onChanged) {
    return Row(
      children: [
        _buildRadio(Strings.t('overwrite'), 'overwrite', currentMode, onChanged),
        const SizedBox(width: 8),
        _buildRadio(Strings.t('append'), 'append', currentMode, onChanged),
        const SizedBox(width: 8),
        _buildRadio(Strings.t('remove'), 'remove', currentMode, onChanged),
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

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      bool needRescan = false;
      if (widget.isBatch) {
        if (widget.folderTargets.isNotEmpty) {
          needRescan = await widget.state.batchEditFolders(
            folderPaths: widget.folderTargets.map((e) => e.path).toList(),
            description: _cbDesc ? _descCtrl.text.trim() : null,
            creator: _cbCreator ? _creatorCtrl.text.trim() : null,
            type: _cbType ? _typeCtrl.text.trim() : null,
            contentRating: _cbContentRating ? _contentRatingCtrl.text.trim() : null,
            tags: _cbTags ? _tags : null,
            classes: _cbClass ? _classes : null,
            classMode: _classMode,
            tagsMode: _tagsMode,
            define: _cbDefine ? _define : null,
            preview: _cbPreview ? _previewCtrl.text.trim() : null,
            star: _cbStar ? _star : null,
            goto: _cbGoto ? _goto : null,
            gotoMode: _gotoMode,
          );
        } else {
          needRescan = await widget.state.batchEditItems(
            itemPaths: widget.targets.map((e) => e.path).toList(),
            description: _cbDesc ? _descCtrl.text.trim() : null,
            creator: _cbCreator ? _creatorCtrl.text.trim() : null,
            type: _cbType ? _typeCtrl.text.trim() : null,
            contentRating: _cbContentRating ? _contentRatingCtrl.text.trim() : null,
            tags: _cbTags ? _tags : null,
            classes: _cbClass ? _classes : null,
            classMode: _classMode,
            tagsMode: _tagsMode,
            define: _cbDefine ? _define : null,
            preview: _cbPreview ? _previewCtrl.text.trim() : null,
            star: _cbStar ? _star : null,
            goto: _cbGoto ? _goto : null,
            gotoMode: _gotoMode,
          );
        }
      } else {
        final isFolder = widget.folderTargets.isNotEmpty;
        final targetPath = isFolder
            ? widget.folderTargets.first.path
            : widget.targets.first.path;
        final oldInfo = isFolder
            ? widget.folderTargets.first.info ??
                ItemInfo.defaults(widget.folderTargets.first.name)
            : widget.targets.first.info;
        final newInfo = ItemInfo(
          uuid: oldInfo.uuid,
          define: _define,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          creator: _creatorCtrl.text.trim().isEmpty
              ? null
              : _creatorCtrl.text.trim(),
          type: _typeCtrl.text.trim().isEmpty ? oldInfo.type : _typeCtrl.text.trim(),
          contentRating: _contentRatingCtrl.text.trim().isEmpty ? oldInfo.contentRating : _contentRatingCtrl.text.trim(),
          rating: _rating,
          tags: _tags,
          classes: _classes,
          preview: _previewCtrl.text.trim().isEmpty
              ? null
              : _previewCtrl.text.trim(),
          goto: _goto,
          star: _star,
        );
        if (isFolder) {
          needRescan = await widget.state.saveFolderInfo(targetPath, newInfo);
        } else {
          needRescan = await widget.state.saveItemInfo(targetPath, newInfo);
        }
      }
      if (mounted) Navigator.pop(context);
      if (needRescan && mounted) {
        await widget.state.rescan();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.tn('saveFailed', {'error': '$e'})), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
