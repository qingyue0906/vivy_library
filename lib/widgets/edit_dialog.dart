import 'package:flutter/material.dart';
import '../models/item_info.dart';
import '../models/library_item.dart';
import '../providers/library_state.dart';

/// 编辑对话框,同时处理单项编辑和批量编辑两种模式。
/// 对应 Python 里 EditDialog 和 BatchEditDialog 两个类。
class EditDialog extends StatefulWidget {
  final List<LibraryItem> targets; // 要编辑的项目列表
  final bool isBatch;              // true = 批量编辑模式
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
  // 单项编辑用的 controllers
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _creatorCtrl;

  // 批量编辑和单项编辑共用的字段
  String _type = 'application';
  String _contentRating = 'G';
  int _rating = 10;
  String _tagsText = '';   // 用逗号分隔的字符串,方便输入
  String _classesText = '';

  // 批量编辑专用:操作模式
  String _batchMode = 'overwrite';

  bool _isSaving = false;

  static const _typeOptions = [
    'application', 'game', 'video', 'image', 'music', 'document', 'other'
  ];
  static const _ratingOptions = [
    'G', 'PG', 'PG-13', 'R', 'NC-17'
  ];

  @override
  void initState() {
    super.initState();
    if (!widget.isBatch) {
      // 单项编辑:用第一个(也是唯一一个)项目的现有值预填
      final info = widget.targets.first.info;
      _titleCtrl = TextEditingController(text: info.title);
      _descCtrl = TextEditingController(text: info.description);
      _creatorCtrl = TextEditingController(text: info.creator ?? '');
      _type = info.type;
      _contentRating = info.contentRating;
      _rating = info.rating;
      _tagsText = info.tags.join(', ');
      _classesText = info.classes.join(', ');
    } else {
      // 批量编辑:字段初始为空,由用户决定改哪些
      _titleCtrl = TextEditingController();
      _descCtrl = TextEditingController();
      _creatorCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _creatorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isBatch
          ? '批量编辑 (${widget.targets.length} 项)'
          : '编辑：${widget.targets.first.info.title}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 批量编辑模式下显示操作模式选择
              if (widget.isBatch) ...[
                _buildBatchModeSelector(),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
              ],

              // 单项编辑才有标题/描述/创建者字段
              if (!widget.isBatch) ...[
                _buildTextField('标题', _titleCtrl),
                const SizedBox(height: 12),
                _buildTextField('描述', _descCtrl, maxLines: 3),
                const SizedBox(height: 12),
                _buildTextField('创建者', _creatorCtrl),
                const SizedBox(height: 16),
              ],

              // 类型和分级
              Row(
                children: [
                  Expanded(child: _buildDropdown('类型', _type, _typeOptions,
                      (v) => setState(() => _type = v!))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _buildDropdown(
                          '分级', _contentRating, _ratingOptions,
                          (v) => setState(() => _contentRating = v!))),
                ],
              ),

              // 评分滑块(仅单项编辑显示)
              if (!widget.isBatch) ...[
                const SizedBox(height: 12),
                _buildRatingSlider(),
              ],

              const SizedBox(height: 12),
              _buildTextField('分类标签 (class, 逗号分隔)', 
                  TextEditingController(text: _classesText),
                  onChanged: (v) => _classesText = v),
              const SizedBox(height: 12),
              _buildTextField('标签 (tags, 逗号分隔)',
                  TextEditingController(text: _tagsText),
                  onChanged: (v) => _tagsText = v),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildBatchModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('操作模式', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'overwrite', label: Text('覆盖')),
            ButtonSegment(value: 'append', label: Text('追加')),
            ButtonSegment(value: 'remove', label: Text('删除')),
          ],
          selected: {_batchMode},
          onSelectionChanged: (s) => setState(() => _batchMode = s.first),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController ctrl, {
    int maxLines = 1,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> options,
      void Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildRatingSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('评分：${(_rating / 2).toStringAsFixed(1)} / 5',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        Slider(
          value: _rating.toDouble(),
          min: 0,
          max: 10,
          divisions: 10,
          onChanged: (v) => setState(() => _rating = v.round()),
        ),
      ],
    );
  }

  // 把逗号分隔的字符串转成 List<String>,去掉空项和首尾空格
  // 对应 Python 里 split(',') + strip() 的那段处理
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
        // 单项编辑:直接用表单值构建新的 ItemInfo
        final newInfo = ItemInfo(
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          creator: _creatorCtrl.text.trim().isEmpty
              ? null
              : _creatorCtrl.text.trim(),
          type: _type,
          contentRating: _contentRating,
          rating: _rating,
          tags: _parseList(_tagsText),
          classes: _parseList(_classesText),
        );
        await widget.state.saveItemInfo(
            widget.targets.first.path, newInfo);
      } else {
        // 批量编辑:只传有实际输入内容的字段
        await widget.state.batchEditItems(
          itemPaths: widget.targets.map((e) => e.path).toList(),
          type: _type,
          contentRating: _contentRating,
          tags: _parseList(_tagsText),
          classes: _parseList(_classesText),
          mode: _batchMode,
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