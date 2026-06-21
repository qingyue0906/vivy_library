import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PresetService {
  static const _storageKey = 'edit_presets';

  static const Map<String, List<String>> defaults = {
    'creator': ['未知', 'Accelerator'],
    'type': ['application', 'game', 'video', 'image', 'music', 'document', 'other'],
    'contentRating': ['G', 'PG', 'PG-13', 'R', 'NC-17'],
    'class': ['工具', '多媒体', '二次元', '开发', '测试'],
    'tags': ['推荐', '最新', '经典', '视觉 lossy', 'AVIF'],
  };

  static Future<Map<String, List<String>>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null) return Map.from(defaults);
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, List<String>.from(v as List)));
    } catch (_) {
      return Map.from(defaults);
    }
  }

  static Future<void> saveAll(Map<String, List<String>> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(presets));
  }
}
