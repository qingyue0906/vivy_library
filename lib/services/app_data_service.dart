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

  static Future<void> saveSettings(Map<String, dynamic> data) async {
    await ensureDir();
    final tmp = File('$settingsPath.tmp');
    await tmp.writeAsString(jsonEncode(data), encoding: utf8);
    await tmp.rename(settingsPath);
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
    await ensureDir();
    final tmp = File('$scriptsMetaPath.tmp');
    await tmp.writeAsString(content, encoding: utf8);
    await tmp.rename(scriptsMetaPath);
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
