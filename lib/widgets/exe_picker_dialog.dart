import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/exe_record.dart';
import '../services/exe_history_service.dart';
import '../services/translations.dart';
import 'smooth_scroll.dart';

/// "打开方式"对话框:展示历史选过的程序列表,支持选择已有记录、
/// 浏览新程序、删除历史记录。
/// 关闭时通过 Navigator.pop(context, 选中的ExeRecord) 把结果传回调用方,
/// 如果用户取消,pop 的值是 null。
class ExePickerDialog extends StatefulWidget {
  const ExePickerDialog({super.key});

  @override
  State<ExePickerDialog> createState() => _ExePickerDialogState();
}

class _ExePickerDialogState extends State<ExePickerDialog> {
  final ExeHistoryService _service = ExeHistoryService();
  List<ExeRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await _service.loadAll();
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  Future<void> _browseForNewExe() async {
    // FilePicker.platform.pickFiles 是 file_picker 包的核心 API,
    // type: FileType.custom + allowedExtensions 限制只能选 .exe 文件,
    // 对应 Windows 文件选择框里右下角的"文件类型"过滤器。
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['exe'],
      dialogTitle: Strings.t('selectExe'),
    );

    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    // 用文件名(去掉扩展名)作为默认显示名
    final fileName = path.replaceAll('\\', '/').split('/').last;
    final displayName = fileName.toLowerCase().endsWith('.exe')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;

    final newRecord = ExeRecord(path: path, displayName: displayName);
    final updated = await _service.addRecord(newRecord);

    setState(() => _records = updated);

    // 选完新程序后直接当作"用户的选择"返回给调用方,不需要再点一次确认,
    // 这样体验上跟系统"打开方式"选完程序立刻生效是一致的。
    if (mounted) Navigator.pop(context, newRecord);
  }

  Future<void> _deleteRecord(ExeRecord record) async {
    final updated = await _service.removeRecord(record.path);
    setState(() => _records = updated);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Strings.t('openWith'), style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 360,
        height: 320,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildRecordList()),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _browseForNewExe,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: Text(Strings.t('browseOther')),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(Strings.t('cancel')),
        ),
      ],
    );
  }

  Widget _buildRecordList() {
    if (_records.isEmpty) {
      return Center(
        child: Text(
          Strings.t('noRecords'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      );
    }

    return SmoothScroll(
      builder: (context, controller, physics) => ListView.builder(
        controller: controller,
        physics: physics,
        itemCount: _records.length,
        itemBuilder: (context, index) {
          final record = _records[index];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.apps, size: 18),
            title: Text(record.displayName, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              record.path,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 点击这一条记录,直接选中并关闭对话框
            onTap: () => Navigator.pop(context, record),
            // 右侧删除按钮,点击只删记录,不关闭对话框,不触发 onTap
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => _deleteRecord(record),
              tooltip: Strings.t('deleteRecord'),
            ),
          );
        },
      ),
    );
  }
}