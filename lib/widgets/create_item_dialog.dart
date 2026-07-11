import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../models/item_info.dart';
import '../models/goto_entry.dart';
import '../providers/library_state.dart';
import '../services/translations.dart';
import 'image_cropper.dart';
import 'compact_level.dart';
import 'folder_tree_picker.dart';
import 'goto_editor.dart';
import 'smooth_scroll.dart';

class CreateItemDialog extends StatefulWidget {
  final LibraryState state;
  final String? defaultParentPath;
  final String? prefilledTitle;
  final List<String>? prefilledImportPaths;

  const CreateItemDialog({
    super.key,
    required this.state,
    this.defaultParentPath,
    this.prefilledTitle,
    this.prefilledImportPaths,
  });

  @override
  State<CreateItemDialog> createState() => _CreateItemDialogState();
}

class _CreateItemDialogState extends State<CreateItemDialog> {
  String? _parentPath;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _creatorCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  final _contentRatingCtrl = TextEditingController();
  int _rating = 5;
  List<String> _classes = [];
  List<String> _tags = [];
  bool _star = false;
  String _define = 'item';
  String? _previewImagePath;
  Uint8List? _croppedImageBytes;
  List<GotoEntry> _goto = [];
  bool _isSaving = false;
  bool _showAdvanced = false;
  bool _showClassInput = false;
  bool _showTagInput = false;
  final _classInputCtrl = TextEditingController();
  final _tagInputCtrl = TextEditingController();
  final _cropperKey = GlobalKey<ImageCropperState>();
  final List<String> _importedPaths = [];

  /// 拖拽悬停高亮状态：导入文件区 / 预览图区。
  bool _importDragOver = false;
  bool _previewDragOver = false;

  @override
  void initState() {
    super.initState();
    _parentPath = widget.defaultParentPath;
    if (_parentPath != null) _applyParentDefaults(_parentPath!);
    _titleCtrl.addListener(_onTitleChanged);
    if (widget.prefilledTitle != null) {
      _titleCtrl.text = widget.prefilledTitle!;
    }
    if (widget.prefilledImportPaths != null) {
      _importedPaths.addAll(widget.prefilledImportPaths!);
    }
  }

  void _onTitleChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _applyParentDefaults(String parentPath) {
    final parentInfo = widget.state.parentInfoOf(parentPath);
    if (parentInfo != null) {
      _typeCtrl.text = parentInfo.type;
      _contentRatingCtrl.text = parentInfo.contentRating;
      setState(() => _rating = parentInfo.rating);
      setState(() {
        _classes = List.of(parentInfo.classes);
        _tags = List.of(parentInfo.tags);
      });
    } else {
      _applyHardcodedDefaults();
    }
  }

  void _applyHardcodedDefaults() {
    final d = ItemInfo.hardcodedDefaults;
    _typeCtrl.text = d.type;
    _contentRatingCtrl.text = d.contentRating;
    setState(() => _rating = d.rating);
    setState(() {
      _classes = List.of(d.classes);
      _tags = List.of(d.tags);
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _creatorCtrl.dispose();
    _typeCtrl.dispose();
    _contentRatingCtrl.dispose();
    _classInputCtrl.dispose();
    _tagInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() => _previewImagePath = result.files.single.path);
    }
  }

  Future<void> _save() async {
    if (_parentPath == null || _parentPath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Strings.t('selectParentFolder')), backgroundColor: Colors.red),
      );
      return;
    }
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Strings.t('titleRequired')), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      Uint8List? cropped;
      if (_cropperKey.currentState != null && _previewImagePath != null) {
        try {
          cropped = await _cropperKey.currentState!.cropImage();
        } catch (_) {}
      }
      if (cropped == null && _croppedImageBytes != null) {
        cropped = _croppedImageBytes;
      }

      final info = ItemInfo(
        define: _define,
        title: title,
        description: _descCtrl.text.trim(),
        creator: _creatorCtrl.text.trim().isEmpty ? null : _creatorCtrl.text.trim(),
        type: _typeCtrl.text.trim(),
        contentRating: _contentRatingCtrl.text.trim(),
        rating: _rating,
        tags: _tags,
        classes: _classes,
        star: _star,
        goto: _goto,
      );

      final result = await widget.state.createItem(
        parentPath: _parentPath!,
        folderName: title,
        info: info,
        croppedImage: cropped,
        importedPaths: _importedPaths,
      );

      if (mounted) {
        if (result != null) {
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Strings.t('createFailed')), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(': '), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = CompactLevel.of(context);
    return AlertDialog(
      title: Text(Strings.t('createItem'), style: const TextStyle(fontSize: 14)),
      content: SizedBox(
        width: 500,
        child: SmoothScroll(
          builder: (context, controller, physics) => SingleChildScrollView(
            controller: controller,
            physics: physics,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFolderSelector(context, c, cs),
                const SizedBox(height: 8),
                _buildField(Strings.t('title'), _titleCtrl, isError: _titleCtrl.text.trim().isEmpty),
                const SizedBox(height: 8),
                _buildPreviewArea(context, c, cs),
                const SizedBox(height: 8),
                _buildImportSection(context, c, cs),
                const SizedBox(height: 8),
                _buildField(Strings.t('description'), _descCtrl, maxLines: 3),
                const SizedBox(height: 8),
                _buildAutoField(Strings.t('creator'), _creatorCtrl, widget.state.uniqueCreators),
                const SizedBox(height: 8),
                _buildRowFields(
                  _buildAutoField(Strings.t('type'), _typeCtrl, widget.state.uniqueTypes),
                  _buildAutoField(Strings.t('contentRating'), _contentRatingCtrl, widget.state.uniqueContentRatings),
                ),
                const SizedBox(height: 8),
                _buildRatingSlider(context, c, cs),
                const SizedBox(height: 8),
                _buildChipSection(
                  label: Strings.t('classLabel'),
                  values: _classes,
                  showInput: _showClassInput,
                  inputCtrl: _classInputCtrl,
                  suggestions: widget.state.uniqueClasses,
                  onChanged: (v) => setState(() => _classes = v),
                  onShowInputChanged: (v) => setState(() => _showClassInput = v),
                ),
                const SizedBox(height: 8),
                _buildChipSection(
                  label: Strings.t('tags'),
                  values: _tags,
                  showInput: _showTagInput,
                  inputCtrl: _tagInputCtrl,
                  suggestions: widget.state.uniqueTags,
                  onChanged: (v) => setState(() => _tags = v),
                  onShowInputChanged: (v) => setState(() => _showTagInput = v),
                ),
                const SizedBox(height: 8),
                _buildStarField(context, c, cs),
                const SizedBox(height: 8),
                _buildAdvancedToggle(context, cs),
                if (_showAdvanced) ...[
                  const SizedBox(height: 8),
                  _buildDefineField(context, cs),
                  const SizedBox(height: 8),
                  _buildGotoSection(context, c, cs),
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
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(Strings.t('create'), style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Future<void> _pickFolder() async {
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('selectParentFolder'), style: const TextStyle(fontSize: 14)),
        content: SizedBox(
          width: 300,
          height: 400,
          child: FolderTreePicker(
            root: widget.state.categoryRoot,
            selectedPath: _parentPath,
            onSelected: (p) => Navigator.pop(ctx, p),
          ),
        ),
      ),
    );
    if (path != null) {
      setState(() => _parentPath = path);
      _applyParentDefaults(path);
    }
  }

  Widget _buildFolderSelector(BuildContext context, double c, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 4 * c),
          child: Text(Strings.t('parentFolder'), style: TextStyle(fontSize: 11 * c, color: cs.onSurfaceVariant)),
        ),
        InkWell(
          onTap: _pickFolder,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 10 * c, vertical: 8 * c),
            decoration: BoxDecoration(
              border: Border.all(color: _parentPath != null ? cs.primary : cs.error),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.folder, size: 14 * c, color: _parentPath != null ? cs.primary : cs.error),
                SizedBox(width: 4 * c),
                Expanded(
                  child: Text(
                    _parentPath ?? Strings.t('tapToSelectFolder'),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11 * c, color: _parentPath != null ? cs.onSurface : cs.onSurfaceVariant),
                  ),
                ),
                Icon(Icons.chevron_right, size: 14 * c, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _pickImportFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      for (final f in result.files) {
        if (f.path != null && !_importedPaths.contains(f.path)) {
          setState(() => _importedPaths.add(f.path!));
        }
      }
    }
  }

  void _pickImportFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null && !_importedPaths.contains(dir)) {
      setState(() => _importedPaths.add(dir));
    }
  }

  Widget _buildImportSection(BuildContext context, double c, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 4 * c),
          child: Text(Strings.t('importFiles'), style: TextStyle(fontSize: 11 * c, color: cs.onSurfaceVariant)),
        ),
        DropTarget(
          onDragEntered: (_) => setState(() => _importDragOver = true),
          onDragExited: (_) => setState(() => _importDragOver = false),
          onDragDone: (detail) {
            setState(() => _importDragOver = false);
            final paths = detail.files.map((f) => f.path).toList();
            for (final p in paths) {
              if (!_importedPaths.contains(p)) {
                setState(() => _importedPaths.add(p));
              }
            }
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(8 * c),
            decoration: BoxDecoration(
              color: _importDragOver
                  ? cs.primary.withValues(alpha: 0.08)
                  : null,
              border: Border.all(
                color: _importDragOver ? cs.primary : cs.outlineVariant,
                width: _importDragOver ? 2 : 1,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickImportFiles,
                        icon: Icon(Icons.file_open, size: 14 * c),
                        label: Text(Strings.t('selectFiles'), style: TextStyle(fontSize: 11 * c)),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 6 * c),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    SizedBox(width: 8 * c),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickImportFolder,
                        icon: Icon(Icons.create_new_folder, size: 14 * c),
                        label: Text(Strings.t('selectFolder'), style: TextStyle(fontSize: 11 * c)),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 6 * c),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4 * c),
                Text(Strings.t('dragHint'), style: TextStyle(fontSize: 10 * c, color: cs.onSurfaceVariant)),
                if (_importedPaths.isNotEmpty) ...[
                  SizedBox(height: 4 * c),
                  ..._importedPaths.map((p) {
                    final name = p.replaceAll("\\", "/").split("/").last;
                    return Padding(
                      padding: EdgeInsets.only(bottom: 2 * c),
                      child: Row(
                        children: [
                          Icon(Icons.insert_drive_file, size: 12 * c, color: cs.onSurfaceVariant),
                          SizedBox(width: 4 * c),
                          Expanded(
                            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10 * c, color: cs.onSurface)),
                          ),
                          InkWell(
                            onTap: () => setState(() => _importedPaths.remove(p)),
                            child: Icon(Icons.close, size: 12 * c, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewArea(BuildContext context, double c, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 4 * c),
          child: Text(Strings.t('previewImage'), style: TextStyle(fontSize: 11 * c, color: cs.onSurfaceVariant)),
        ),
        if (_previewImagePath != null)
          Column(
            children: [
              Center(
                child: ImageCropper(
                key: _cropperKey,
                imagePath: _previewImagePath!,
                width: 400,
                height: 250,
                ),
              ),
              SizedBox(height: 4 * c),
              TextButton.icon(
                onPressed: () => setState(() {
                  _previewImagePath = null;
                  _croppedImageBytes = null;
                }),
                icon: Icon(Icons.close, size: 14 * c),
                label: Text(Strings.t('remove'), style: TextStyle(fontSize: 11 * c)),
              ),
            ],
          )
        else
          DropTarget(
            onDragEntered: (_) => setState(() => _previewDragOver = true),
            onDragExited: (_) => setState(() => _previewDragOver = false),
            onDragDone: (detail) {
              setState(() => _previewDragOver = false);
              final paths = detail.files.map((f) => f.path).toList();
              if (paths.isNotEmpty) {
                final path = paths.first;
                if (_isImageExtension(path)) {
                  setState(() => _previewImagePath = path);
                }
              }
            },
            child: InkWell(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 100 * c,
                decoration: BoxDecoration(
                  color: _previewDragOver
                      ? cs.primary.withValues(alpha: 0.08)
                      : null,
                  border: Border.all(
                    color: _previewDragOver ? cs.primary : cs.outlineVariant,
                    width: _previewDragOver ? 2 : 1,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_photo_alternate, size: 24 * c, color: cs.onSurfaceVariant),
                      SizedBox(height: 4 * c),
                      Text(Strings.t('tapToSelectImage'), style: TextStyle(fontSize: 11 * c, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _isImageExtension(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
  }

  Widget _buildField(String label, TextEditingController ctrl, {int maxLines = 1, bool isError = false}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 11),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: isError ? cs.error : cs.outlineVariant),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAutoField(String label, TextEditingController controller, List<String> options) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        Autocomplete<String>(
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
              style: const TextStyle(fontSize: 11),
              onChanged: (v) => controller.text = v,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onSubmitted: (_) => onSubmitted(),
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
                            child: Text(option, style: TextStyle(fontSize: 11, color: cs.onSurface)),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRowFields(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildRatingSlider(BuildContext context, double c, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 2 * c),
          child: Text('${Strings.t("rating")}: ${_rating / 2} / 5', style: TextStyle(fontSize: 11 * c, color: cs.onSurfaceVariant)),
        ),
        Slider(
          value: _rating.toDouble(),
          min: 0, max: 10, divisions: 10,
          onChanged: (v) => setState(() => _rating = v.round()),
        ),
      ],
    );
  }

  Widget _buildChipSection({
    required String label,
    required List<String> values,
    required bool showInput,
    required TextEditingController inputCtrl,
    required List<String> suggestions,
    required ValueChanged<List<String>> onChanged,
    required ValueChanged<bool> onShowInputChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        Wrap(
          spacing: 4, runSpacing: 4,
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
                  final parts = v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                  final newValues = List<String>.from(values);
                  var added = false;
                  for (final part in parts) {
                    if (!newValues.contains(part)) {
                      newValues.add(part);
                      added = true;
                    }
                  }
                  if (added) onChanged(newValues);
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
        return suggestions.where((s) => !currentValues.contains(s) && s.toLowerCase().contains(text));
      },
      onSelected: (selection) => onAdd(selection),
      fieldViewBuilder: (context, acController, focusNode, onSubmitted) {
        return Container(
          width: 140, height: 28,
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: acController,
            focusNode: focusNode,
            autofocus: true,
            style: const TextStyle(fontSize: 11),
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
                  if (text.isNotEmpty) onAdd(text);
                  else onCancel();
                },
              ),
            ),
            onSubmitted: (value) {
              final text = value.trim();
              if (text.isNotEmpty) onAdd(text);
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

  Widget _buildStarField(BuildContext context, double c, ColorScheme cs) {
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

  Widget _buildAdvancedToggle(BuildContext context, ColorScheme cs) {
    return InkWell(
      onTap: () => setState(() => _showAdvanced = !_showAdvanced),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more, size: 14, color: cs.onSurfaceVariant),
            SizedBox(width: 4),
            Text(Strings.t('advanced'), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildDefineField(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(Strings.t('define'), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        DropdownButtonFormField<String>(
          value: _define,
          items: ['item', 'dir', 'hide'].map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 11)))).toList(),
          onChanged: (v) => setState(() => _define = v ?? 'item'),
          isDense: true,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ],
    );
  }

  Widget _buildGotoSection(BuildContext context, double c, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(Strings.t('gotoSection'), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        GotoEditor(
          entries: _goto,
          onChanged: (list) => setState(() => _goto = list),
        ),
      ],
    );
  }
}
