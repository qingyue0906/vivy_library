import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ScriptExecMode { result, terminal, silent }

class ScriptEntry {
  final String id;
  final String name;
  final String fileName;
  final ScriptExecMode execMode;
  final bool enabled;

  const ScriptEntry({
    required this.id,
    required this.name,
    required this.fileName,
    this.execMode = ScriptExecMode.result,
    this.enabled = true,
  });

  ScriptEntry copyWith({
    String? id,
    String? name,
    String? fileName,
    ScriptExecMode? execMode,
    bool? enabled,
  }) =>
      ScriptEntry(
        id: id ?? this.id,
        name: name ?? this.name,
        fileName: fileName ?? this.fileName,
        execMode: execMode ?? this.execMode,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fileName': fileName,
        'execMode': execMode.index,
        'enabled': enabled,
      };

  factory ScriptEntry.fromJson(Map<String, dynamic> json) => ScriptEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        fileName: json['fileName'] as String,
        execMode: ScriptExecMode.values[json['execMode'] as int],
        enabled: json['enabled'] as bool? ?? true,
      );
}

class ScriptResult {
  final String scriptName;
  final List<String> outputs;

  const ScriptResult({required this.scriptName, required this.outputs});
}

class ScriptService extends ChangeNotifier {
  static const _scriptsKey = 'scripts';
  static const _pythonPathKey = 'python_path';

  List<ScriptEntry> _scripts = [];
  String _pythonPath = '';

  List<ScriptEntry> get scripts => List.unmodifiable(_scripts);
  String get pythonPath => _pythonPath;

  String get _scriptsDir {
    final appData = Platform.environment['APPDATA'] ?? '${Platform.environment['HOME']}/.config';
    return '$appData/vivy_library/scripts';
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _pythonPath = prefs.getString(_pythonPathKey) ?? '';
    final raw = prefs.getString(_scriptsKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _scripts = list.map((e) => ScriptEntry.fromJson(e as Map<String, dynamic>)).toList();
    }
    _syncFiles();
  }

  Future<void> savePythonPath(String path) async {
    _pythonPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pythonPathKey, path);
    notifyListeners();
  }

  Future<void> importScript(String sourcePath) async {
    final dir = Directory(_scriptsDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final fileName = _basename(sourcePath);
    final dest = '${dir.path}/$fileName';
    if (await File(dest).exists()) await File(dest).delete();
    await File(sourcePath).copy(dest);

    final entry = ScriptEntry(
      id: _generateId(),
      name: _withoutExtension(fileName),
      fileName: fileName,
    );
    _scripts.add(entry);
    await _persist();
    notifyListeners();
  }

  String readDescriptionSync(ScriptEntry script) {
    final file = File('$_scriptsDir/${script.fileName}');
    if (!file.existsSync()) return '';
    return _parseDocstring(file);
  }

  Future<void> replaceAllScripts(List<ScriptEntry> scripts) async {
    _scripts = List.from(scripts);
    await _persist();
    notifyListeners();
  }

  Future<void> updateScript(ScriptEntry script) async {
    final idx = _scripts.indexWhere((s) => s.id == script.id);
    if (idx == -1) return;
    _scripts[idx] = script;
    await _persist();
    notifyListeners();
  }

  Future<void> deleteScript(ScriptEntry script) async {
    _scripts.removeWhere((s) => s.id == script.id);
    final file = File('$_scriptsDir/${script.fileName}');
    if (await file.exists()) await file.delete();
    await _persist();
    notifyListeners();
  }

  Future<String> _resolvePython() async {
    if (_pythonPath.isNotEmpty) return _pythonPath;
    try {
      final r = await Process.run('py', ['-3', '--version']);
      if (r.exitCode == 0) return 'py -3';
    } catch (_) {}
    return 'python';
  }

  Future<ScriptResult> executeScript(ScriptEntry script, List<String> paths) async {
    final python = await _resolvePython();
    final scriptPath = '$_scriptsDir/${script.fileName}';
    final outputs = <String>[];

    for (final path in paths) {
      try {
        final result = await Process.run(
          python,
          [scriptPath, path],
          runInShell: true,
        );
        final sb = StringBuffer()
          ..writeln('> $python $scriptPath "$path"')
          ..writeln('stdout:')
          ..writeln(result.stdout.toString().trim())
          ..writeln('stderr:')
          ..writeln(result.stderr.toString().trim())
          ..writeln('exitCode: ${result.exitCode}');
        outputs.add(sb.toString().trim());
      } catch (e) {
        outputs.add('> $python $scriptPath "$path"\nError: $e');
      }
    }
    return ScriptResult(scriptName: script.name, outputs: outputs);
  }

  void executeScriptTerminal(ScriptEntry script, List<String> paths) async {
    final python = _resolvePython();
    final scriptPath = '$_scriptsDir/${script.fileName}';
    for (final path in paths) {
      final cmd = '"${await python}" "$scriptPath" "$path"';
      Process.run('cmd', ['/c', 'start', 'cmd', '/c', cmd]);
    }
  }

  Future<ScriptResult> executeScriptSilent(ScriptEntry script, List<String> paths) async {
    final python = await _resolvePython();
    final scriptPath = '$_scriptsDir/${script.fileName}';
    final outputs = <String>[];

    for (final path in paths) {
      try {
        final result = await Process.run(
          python,
          [scriptPath, path],
          runInShell: true,
        );
        outputs.add('${script.name} @ "$path" -> exit ${result.exitCode}');
      } catch (e) {
        outputs.add('${script.name} @ "$path" -> Error: $e');
      }
    }
    return ScriptResult(scriptName: script.name, outputs: outputs);
  }

  void _syncFiles() {
    final dir = Directory(_scriptsDir);
    if (!dir.existsSync()) return;
    final existing = dir.listSync().whereType<File>().map((f) => _basename(f.path)).toSet();
    _scripts.removeWhere((s) => !existing.contains(s.fileName));
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_scripts.map((s) => s.toJson()).toList());
    await prefs.setString(_scriptsKey, raw);
  }

  String _generateId() {
    // Simple UUID-like id without dependency on uuid package
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = (now % 99999).toString().padLeft(5, '0');
    return '${now}_$random';
  }

  String _basename(String path) {
    return path.replaceAll('\\', '/').split('/').last;
  }

  String _withoutExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  String _parseDocstring(File file) {
    try {
      final content = file.readAsStringSync(encoding: utf8);
      final lines = content.split('\n');
      final startCommentMarkers = {'#!', '# -*-'};
      int i = 0;
      while (i < lines.length && startCommentMarkers.any((m) => lines[i].trimLeft().startsWith(m))) {
        i++;
      }
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('"""') || trimmed.startsWith("'''")) {
        final quote = trimmed.substring(0, 3);
        String rest = trimmed.substring(3);
        if (rest.endsWith(quote)) {
          rest = rest.substring(0, rest.length - 3);
          return rest.trim();
        }
        if (rest.isNotEmpty) rest += '\n';
        i++;
        while (i < lines.length) {
          final line = lines[i];
          if (line.contains(quote)) {
            final idx = line.indexOf(quote);
            rest += line.substring(0, idx);
            break;
          }
          rest = '$rest$line\n';
          i++;
        }
        return rest.trim();
      }
    } catch (_) {}
    return '';
  }
}
