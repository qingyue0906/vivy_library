import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/library_root.dart';

/// 管理"用户添加过的资源库列表"的持久化,以及"当前选中的资源库"。
/// 跟 ExeHistoryService 是同一套模式:JSON 字符串存进 shared_preferences。
class LibraryRootService {
  static const String _listKey = 'library_roots';
  static const String _currentKey = 'current_library_root';

  Future<List<LibraryRoot>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_listKey);
    if (jsonString == null) return [];
    try {
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded
          .map((e) => LibraryRoot.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveAll(List<LibraryRoot> roots) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _listKey, jsonEncode(roots.map((e) => e.toJson()).toList()));
  }

  /// 添加一个资源库(路径已存在则不重复添加,只更新名称)
  Future<List<LibraryRoot>> addRoot(LibraryRoot root) async {
    final current = await loadAll();
    current.removeWhere((e) => e.path == root.path);
    current.add(root);
    await saveAll(current);
    return current;
  }

  Future<List<LibraryRoot>> removeRoot(String path) async {
    final current = await loadAll();
    current.removeWhere((e) => e.path == path);
    await saveAll(current);
    return current;
  }

  /// 更新某个资源库的显示名称(不影响实际文件夹路径,纯粹是 App 内的别名)
  Future<List<LibraryRoot>> renameRoot(String path, String newName) async {
    final current = await loadAll();
    final index = current.indexWhere((e) => e.path == path);
    if (index != -1) {
      current[index] = LibraryRoot(name: newName, path: path);
      await saveAll(current);
    }
    return current;
  }

  /// 记住"上次使用的资源库路径",下次启动应用直接用它,
  /// 不需要每次都重新选择
  Future<void> setCurrentRootPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentKey, path);
  }

  Future<String?> getCurrentRootPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentKey);
  }
}