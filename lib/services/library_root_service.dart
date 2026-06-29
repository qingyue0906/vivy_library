import 'dart:convert';
import '../models/library_root.dart';
import 'app_data_service.dart';

class LibraryRootService {
  static const String _listKey = 'library_roots';
  static const String _currentKey = 'current_library_root';

  Future<List<LibraryRoot>> loadAll() async {
    final jsonString = await AppDataService.getString(_listKey);
    if (jsonString == null) return [];
    try {
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded.map((e) => LibraryRoot.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<LibraryRoot> roots) async {
    await AppDataService.setString(_listKey, jsonEncode(roots.map((e) => e.toJson()).toList()));
  }

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

  Future<List<LibraryRoot>> renameRoot(String path, String newName) async {
    final current = await loadAll();
    final index = current.indexWhere((e) => e.path == path);
    if (index != -1) {
      current[index] = LibraryRoot(name: newName, path: path);
      await saveAll(current);
    }
    return current;
  }

  Future<void> setCurrentRootPath(String path) async {
    await AppDataService.setString(_currentKey, path);
  }

  Future<String?> getCurrentRootPath() async {
    return AppDataService.getString(_currentKey);
  }
}