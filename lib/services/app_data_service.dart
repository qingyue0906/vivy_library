import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// 统一管理 %APPDATA%/vivy_library/ 下的所有数据文件。
/// 替代 SharedPreferences。
class AppDataService {
  static String get baseDir {
    final appData = Platform.environment['APPDATA'] ?? '${Platform.environment['HOME']}/.config';
    return '$appData/vivy_library';
  }

  static String get settingsPath => '$baseDir/settings.json';
  static String get scriptsMetaPath => '$baseDir/scripts.json';

  static Future<void> ensureDir() async {
    final dir = Directory(baseDir);
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  // ======== settings.json ========

  static Future<Map<String, dynamic>> loadSettings() async {
    final file = File(settingsPath);
    if (!await file.exists()) return {};
    try {
      final content = await file.readAsString(encoding: utf8);
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// 串行化所有写入，避免并发保存（如拖动结束同时触发多个面板 saveLayout）
  /// 竞争同一个 .tmp / settings.json 导致 rename 失败（errno=32 文件被占用）。
  static Future<void>? _writeChain;
  static int _writeSeq = 0;

  /// 原子写入：先写唯一命名的临时文件再 rename 到目标。
  /// - 串行化：后续写入等待前一次完成，互不干扰。
  /// - 唯一临时文件名（pid+自增序号）：即便并发也不会互相覆盖 .tmp。
  /// - rename 失败重试 3 次（间隔 25ms）以绕过 Windows 瞬时文件锁；
  ///   仍失败则退回直接覆盖写，确保布局等数据最终落盘。
  static Future<void> _atomicWrite(String targetPath, String content) async {
    final previous = _writeChain;
    final completer = Completer<void>();
    _writeChain = completer.future;
    try {
      await previous;
      final dir = Directory(baseDir);
      if (!await dir.exists()) await dir.create(recursive: true);
      final tmp = File('$targetPath.${pid}.${_writeSeq++}.tmp');
      await tmp.writeAsString(content, encoding: utf8);
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await tmp.rename(targetPath);
          return;
        } catch (_) {
          if (attempt == 2) break;
          await Future.delayed(const Duration(milliseconds: 25));
        }
      }
      // 回退：直接覆盖写
      await File(targetPath).writeAsString(
        content,
        encoding: utf8,
        flush: true,
      );
    } finally {
      completer.complete();
    }
  }

  static Future<void> saveSettings(Map<String, dynamic> data) async {
    await _atomicWrite(settingsPath, jsonEncode(data));
  }

  static Future<String?> getString(String key) async {
    final data = await loadSettings();
    return data[key] as String?;
  }

  static Future<void> setString(String key, String value) async {
    final data = await loadSettings();
    data[key] = value;
    await saveSettings(data);
  }

  static Future<double?> getDouble(String key) async {
    final data = await loadSettings();
    final v = data[key];
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return null;
  }

  static Future<void> setDouble(String key, double value) async {
    final data = await loadSettings();
    data[key] = value;
    await saveSettings(data);
  }

  static Future<int?> getInt(String key) async {
    final data = await loadSettings();
    final v = data[key];
    if (v is int) return v;
    return null;
  }

  static Future<void> setInt(String key, int value) async {
    final data = await loadSettings();
    data[key] = value;
    await saveSettings(data);
  }

  static Future<void> removeKey(String key) async {
    final data = await loadSettings();
    data.remove(key);
    await saveSettings(data);
  }

  static Future<void> clearAll() async {
    final dir = Directory(baseDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await ensureDir();
  }

  // ======== scripts.json ========

  static Future<String?> readScriptsMeta() async {
    final file = File(scriptsMetaPath);
    if (!await file.exists()) return null;
    try {
      return await file.readAsString(encoding: utf8);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeScriptsMeta(String content) async {
    await _atomicWrite(scriptsMetaPath, content);
  }

  // ======== 首次迁移 ========

  static bool _migrated = false;

  static Future<void> migrateIfNeeded() async {
    if (_migrated) return;
    final file = File(settingsPath);
    if (await file.exists()) {
      _migrated = true;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final all = prefs.getKeys();
    if (all.isEmpty) {
      _migrated = true;
      return;
    }
    final data = <String, dynamic>{};
    for (final key in all) {
      final v = prefs.get(key);
      if (v != null) data[key] = v;
    }
    await saveSettings(data);

    final scriptsRaw = prefs.getString('scripts');
    if (scriptsRaw != null) {
      await ensureDir();
      await File(scriptsMetaPath).writeAsString(scriptsRaw, encoding: utf8);
    }
    _migrated = true;
  }
}
