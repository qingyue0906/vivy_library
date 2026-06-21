import 'dart:convert';
import 'dart:io';

class PresetService {
  static const _fileName = 'presets.json';

  static String _filePath(String libraryRoot) => '$libraryRoot/$_fileName';

  static const Map<String, List<String>> defaults = {
    'creator': ['未知', 'Accelerator'],
    'type': ['application', 'game', 'video', 'image', 'music', 'document', 'other'],
    'contentRating': ['G', 'PG', 'PG-13', 'R', 'NC-17'],
    'class': ['工具', '多媒体', '二次元', '开发', '测试'],
    'tags': ['推荐', '最新', '经典', '视觉 lossy', 'AVIF'],
  };

  static Future<Map<String, List<String>>> loadAll(String libraryRoot) async {
    final file = File(_filePath(libraryRoot));
    if (!file.existsSync()) return Map.from(defaults);
    try {
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, List<String>.from(v as List)));
    } catch (_) {
      return Map.from(defaults);
    }
  }

  static Future<void> saveAll(String libraryRoot, Map<String, List<String>> presets) async {
    final file = File(_filePath(libraryRoot));
    await file.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(presets));
  }
}
