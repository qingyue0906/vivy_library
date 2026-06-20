import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exe_record.dart';

/// 负责读写"用户选过的程序列表",数据存在本地(对应原项目的 info_presets.json 思路,
/// 只是这次用 shared_preferences 封装好的本地存储,不用自己手动管理文件路径)。
class ExeHistoryService {
  static const String _storageKey = 'exe_history';

  /// 读取所有历史记录
  Future<List<ExeRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString == null) return [];

    try {
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded
          .map((e) => ExeRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // 数据损坏时返回空列表,不让应用崩溃,对应你 Python 项目里常见的 except: pass 兜底思路
      return [];
    }
  }

  /// 保存整份列表(覆盖式写入,简单直接,数据量不大不需要增量更新)
  Future<void> saveAll(List<ExeRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString =
        jsonEncode(records.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, jsonString);
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