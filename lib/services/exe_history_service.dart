import 'dart:convert';
import '../models/exe_record.dart';
import 'app_data_service.dart';

class ExeHistoryService {
  static const String _storageKey = 'exe_history';

  Future<List<ExeRecord>> loadAll() async {
    final jsonString = await AppDataService.getString(_storageKey);
    if (jsonString == null) return [];
    try {
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded.map((e) => ExeRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<ExeRecord> records) async {
    await AppDataService.setString(_storageKey, jsonEncode(records.map((e) => e.toJson()).toList()));
  }

  /// 新增一条记录(如果路径已存在则不重复添加,只是把它移到最前面,
  /// 体现"最近使用"的顺序)
  Future<List<ExeRecord>> addRecord(ExeRecord record) async {
    final current = await loadAll();
    current.removeWhere((e) => e.path == record.path);
    current.insert(0, record);
    await saveAll(current);
    return current;
  }

  /// 删除一条记录
  Future<List<ExeRecord>> removeRecord(String path) async {
    final current = await loadAll();
    current.removeWhere((e) => e.path == path);
    await saveAll(current);
    return current;
  }
}