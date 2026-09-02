import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/category_node.dart';
import '../models/direct_file.dart';
import '../models/item_info.dart';
import '../models/library_item.dart';
import '../models/snapshot_meta.dart';
import 'app_data_service.dart';
import 'snapshot_preview.dart';

/// 快照中记录的项目顶层文件条目（只有名称/大小/时间/是否目录，
/// 不存文件内容；用于快照模式下底部文件面板的只读展示）。
class SnapshotFileEntry {
  final String name;
  final int sizeInBytes;
  final DateTime modifiedTime;
  final bool isDir;

  const SnapshotFileEntry({
    required this.name,
    this.sizeInBytes = 0,
    required this.modifiedTime,
    this.isDir = false,
  });

  factory SnapshotFileEntry.fromJson(Map<String, dynamic> json) {
    return SnapshotFileEntry(
      name: json['name'] as String,
      sizeInBytes: json['size'] as int? ?? 0,
      modifiedTime: DateTime.tryParse(json['modified'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isDir: json['dir'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': sizeInBytes,
        'modified': modifiedTime.toIso8601String(),
        'dir': isDir,
      };
}

/// 加载快照后的内存数据：还原的树 + 每个项目的顶层文件清单。
class SnapshotTree {
  final CategoryNode root;
  final Map<String, List<SnapshotFileEntry>> itemFiles;
  const SnapshotTree({required this.root, required this.itemFiles});
}

/// 快照服务：负责快照的创建、加载、列表、重命名、删除、排序，
/// 以及 CategoryNode/LibraryItem/DirectFile 与 tree.json 之间的序列化。
///
/// 存储布局（%APPDATA%/vivy_library/snapshot/）：
///   <库路径hash>/
///     index.json                快照列表（数组顺序=拖拽顺序，单一事实来源）
///     <时间戳id>/
///       tree.json               完整 CategoryNode 树 + 项目文件清单
///       previews/               压缩预览图（文件名=原路径hash）
class SnapshotService {
  static String get snapshotRoot =>
      '${AppDataService.baseDir}${Platform.pathSeparator}snapshot';

  /// 资源库路径的稳定短哈希（FNV-1a 双种子 64 位 hex，16 字符）。
  static String hashFor(String libraryPath) {
    final norm = libraryPath.replaceAll('\\', '/').toLowerCase();
    return '${_fnv(norm, 0x811c9dc5)}${_fnv(norm, 0x01000193)}';
  }

  static String _fnv(String s, int seed) {
    var h = seed & 0xFFFFFFFF;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// 单条预览图/文件的短哈希（用于 previews/ 文件名去重）。
  static String hashOf(String path) => hashFor(path);

  /// 库目录路径（不存在则返回 null）。
  static String? _libDir(String libraryPath) {
    final dir = '$snapshotRoot${Platform.pathSeparator}${hashFor(libraryPath)}';
    return dir;
  }

  static String _indexPath(String libraryPath) {
    final dir = _libDir(libraryPath)!;
    return '$dir${Platform.pathSeparator}index.json';
  }

  static String _snapshotDir(String libraryPath, String id) {
    final dir = _libDir(libraryPath)!;
    return '$dir${Platform.pathSeparator}$id';
  }

  static String _treePath(String libraryPath, String id) {
    return '${_snapshotDir(libraryPath, id)}${Platform.pathSeparator}tree.json';
  }

  // ====================== 列表 ======================

  /// 某资源库的全部快照（顺序=拖拽排序）。目录缺失的条目自动剔除。
  static Future<List<SnapshotMeta>> listFor(String libraryPath) async {
    final indexPath = _indexPath(libraryPath);
    final file = File(indexPath);
    if (!await file.exists()) return [];
    try {
      final decoded =
          jsonDecode(await file.readAsString(encoding: utf8)) as Map<String, dynamic>;
      final list = (decoded['snapshots'] as List<dynamic>? ?? [])
          .map((e) => SnapshotMeta.fromJson(e as Map<String, dynamic>))
          .toList();
      return list
          .where((m) => Directory(_snapshotDir(libraryPath, m.id)).existsSync())
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 全部资源库的所有快照（"管理所有快照"用）。
  static Future<List<SnapshotMeta>> listAll() async {
    final root = Directory(snapshotRoot);
    if (!await root.exists()) return [];
    final result = <SnapshotMeta>[];
    await for (final lib in root.list()) {
      if (lib is! Directory) continue;
      try {
        final indexPath = '${lib.path}${Platform.pathSeparator}index.json';
        final file = File(indexPath);
        if (!await file.exists()) continue;
        final decoded =
            jsonDecode(await file.readAsString(encoding: utf8)) as Map<String, dynamic>;
        final list = (decoded['snapshots'] as List<dynamic>? ?? [])
            .map((e) => SnapshotMeta.fromJson(e as Map<String, dynamic>))
            .toList();
        for (final m in list) {
          if (Directory(_snapshotDir(m.sourcePath, m.id)).existsSync()) {
            result.add(m);
          }
        }
      } catch (_) {}
    }
    return result;
  }

  static Future<void> _writeIndex(String libraryPath, List<SnapshotMeta> metas) async {
    await AppDataService.writeText(
      _indexPath(libraryPath),
      const JsonEncoder.withIndent('  ').convert({
        'libraryPath': libraryPath,
        'snapshots': metas.map((m) => m.toJson()).toList(),
      }),
    );
  }

  // ====================== 创建 ======================

  /// 创建快照：序列化内存树 + 枚举项目顶层文件 + 处理预览图。
  /// [onProgress] 进度回调（done/total/message），用于 UI 进度条。
  static Future<SnapshotMeta?> create({
    required String sourcePath,
    required CategoryNode root,
    required String name,
    required String note,
    required void Function(int done, int total, String message) onProgress,
  }) async {
    try {
      final id = _timestampId();
      final snapDir = _snapshotDir(sourcePath, id);
      final previewsDir = '$snapDir${Platform.pathSeparator}previews';

      final items = root.allItems;

      // 1. 枚举每个项目的顶层文件（只记名称/大小/时间/是否目录）
      final itemFiles = await _collectItemFiles(items);

      // 2. 处理预览图：短边360 JPEG q80，失败复制原图
      final previewItems = items.where((i) => i.previewPath != null).toList();
      final previewRefs = <String, String>{};
      final total = previewItems.length;
      for (var i = 0; i < previewItems.length; i++) {
        final item = previewItems[i];
        final src = item.previewPath!;
        final hash = hashOf(src);
        final ext = _extOf(src);
        final jpgPath = '$previewsDir${Platform.pathSeparator}$hash.jpg';
        final fallbackPath = '$previewsDir${Platform.pathSeparator}$hash$ext';
        onProgress(i, total, item.info.title);
        final ok = await compute(
          processPreviewSync,
          PreviewJob(src, jpgPath),
        );
        if (ok) {
          previewRefs[item.path] =
              'previews${Platform.pathSeparator}$hash.jpg'.replaceAll('\\', '/');
        } else {
          final copied = await compute(
            copyOriginalPreviewSync,
            PreviewJob(src, fallbackPath),
          );
          if (copied) {
            previewRefs[item.path] =
                'previews${Platform.pathSeparator}$hash$ext'.replaceAll('\\', '/');
          }
        }
      }

      // 3. 序列化树
      final treeJson = _treeToJson(root, previewRefs, itemFiles);
      await Directory(snapDir).create(recursive: true);
      await AppDataService.writeText(
        _treePath(sourcePath, id),
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'sourcePath': sourcePath,
          'tree': treeJson,
        }),
      );

      // 4. 统计快照总大小（tree.json + previews）
      final sizeBytes = await _dirSize(snapDir);

      // 5. 更新 index.json（追加到末尾）
      final meta = SnapshotMeta(
        id: id,
        name: name,
        note: note,
        sourcePath: sourcePath,
        createdAt: DateTime.now(),
        sizeBytes: sizeBytes,
      );
      final metas = await listFor(sourcePath);
      metas.add(meta);
      await _writeIndex(sourcePath, metas);
      onProgress(total, total, '');
      return meta;
    } catch (_) {
      return null;
    }
  }

  /// 时间戳快照 ID：yyyyMMdd_HHmmss_xx（xx 为随机后缀防同秒冲突）。
  static String _timestampId() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final base = '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final rand = Random().nextInt(1296); // 36*36
    return '${base}_${rand.toRadixString(36).padLeft(2, '0')}';
  }

  static String _extOf(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot).toLowerCase() : '';
  }

  /// 有界并发枚举项目顶层文件。
  static Future<Map<String, List<SnapshotFileEntry>>> _collectItemFiles(
    List<LibraryItem> items,
  ) async {
    final result = <String, List<SnapshotFileEntry>>{};
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= items.length) return;
        final item = items[i];
        final list = <SnapshotFileEntry>[];
        try {
          final dir = Directory(item.path);
          if (await dir.exists()) {
            await for (final e in dir.list(followLinks: false)) {
              final name = e.path.replaceAll('\\', '/').split('/').last;
              if (name.startsWith('.')) continue;
              if (e is Directory) {
                list.add(SnapshotFileEntry(
                  name: name,
                  modifiedTime: DateTime.now(),
                  isDir: true,
                ));
              } else if (e is File) {
                try {
                  final stat = await e.stat();
                  list.add(SnapshotFileEntry(
                    name: name,
                    sizeInBytes: stat.size,
                    modifiedTime: stat.modified,
                  ));
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
        list.sort((a, b) => a.name.compareTo(b.name));
        result[item.path] = list;
      }
    }
    final count = items.isEmpty ? 0 : 16.clamp(1, items.length);
    await Future.wait(List.generate(count, (_) => worker()));
    return result;
  }

  static Future<int> _dirSize(String dir) async {
    var total = 0;
    try {
      await for (final e in Directory(dir).list(recursive: true)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  // ====================== 加载 ======================

  /// 加载快照：反序列化树，并把 previewRef 重写为快照内绝对路径。
  static Future<SnapshotTree?> load(SnapshotMeta meta) async {
    final treePath = _treePath(meta.sourcePath, meta.id);
    final file = File(treePath);
    if (!await file.exists()) return null;
    try {
      final decoded =
          jsonDecode(await file.readAsString(encoding: utf8)) as Map<String, dynamic>;
      final snapDir = _snapshotDir(meta.sourcePath, meta.id);
      return _treeFromJson(decoded['tree'] as Map<String, dynamic>, snapDir);
    } catch (_) {
      return null;
    }
  }

  // ====================== 重命名 / 删除 / 排序 ======================

  static Future<bool> rename(
    String libraryPath,
    String id,
    String newName,
    String newNote,
  ) async {
    final metas = await listFor(libraryPath);
    final idx = metas.indexWhere((m) => m.id == id);
    if (idx == -1) return false;
    metas[idx] = metas[idx].copyWith(name: newName, note: newNote);
    await _writeIndex(libraryPath, metas);
    return true;
  }

  static Future<bool> delete(String libraryPath, String id) async {
    final dir = Directory(_snapshotDir(libraryPath, id));
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        return false;
      }
    }
    final metas = await listFor(libraryPath);
    metas.removeWhere((m) => m.id == id);
    await _writeIndex(libraryPath, metas);
    return true;
  }

  static Future<void> reorder(String libraryPath, List<String> orderedIds) async {
    final metas = await listFor(libraryPath);
    final byId = {for (final m in metas) m.id: m};
    final ordered = <SnapshotMeta>[];
    for (final id in orderedIds) {
      final m = byId[id];
      if (m != null) ordered.add(m);
    }
    // 兜底：列表外的快照（理论上不存在）追加到末尾
    for (final m in metas) {
      if (!orderedIds.contains(m.id)) ordered.add(m);
    }
    await _writeIndex(libraryPath, ordered);
  }

  // ====================== 序列化 ======================

  static Map<String, dynamic> _treeToJson(
    CategoryNode root,
    Map<String, String> previewRefs,
    Map<String, List<SnapshotFileEntry>> itemFiles,
  ) {
    return _nodeToJson(root, previewRefs, itemFiles);
  }

  static Map<String, dynamic> _nodeToJson(
    CategoryNode node,
    Map<String, String> previewRefs,
    Map<String, List<SnapshotFileEntry>> itemFiles,
  ) {
    return {
      'path': node.path,
      'name': node.name,
      'info': node.info?.toJson(),
      'subDirs': [
        for (final s in node.subDirs) _nodeToJson(s, previewRefs, itemFiles),
      ],
      'items': [
        for (final i in node.items)
          {
            'path': i.path,
            'category': i.category,
            'categoryPath': i.categoryPath,
            'folderName': i.folderName,
            'info': i.info.toJson(),
            'sizeInBytes': i.sizeInBytes,
            'modifiedTime': i.modifiedTime.toIso8601String(),
            'previewRef': previewRefs[i.path],
            'files': [
              for (final f in itemFiles[i.path] ?? const <SnapshotFileEntry>[])
                f.toJson(),
            ],
          },
      ],
      'files': [
        for (final f in node.files)
          {
            'name': f.name,
            'size': f.sizeInBytes,
            'modified': f.modifiedTime.toIso8601String(),
          },
      ],
    };
  }

  static SnapshotTree _treeFromJson(Map<String, dynamic> json, String snapDir) {
    final itemFiles = <String, List<SnapshotFileEntry>>{};
    final root = _nodeFromJson(json, snapDir, itemFiles);
    return SnapshotTree(root: root, itemFiles: itemFiles);
  }

  static CategoryNode _nodeFromJson(
    Map<String, dynamic> json,
    String snapDir,
    Map<String, List<SnapshotFileEntry>> itemFiles,
  ) {
    final infoRaw = json['info'];
    final items = <LibraryItem>[];
    for (final i in (json['items'] as List<dynamic>? ?? [])) {
      final m = i as Map<String, dynamic>;
      final item = LibraryItem(
        category: m['category'] as String,
        categoryPath: m['categoryPath'] as String,
        folderName: m['folderName'] as String,
        path: m['path'] as String,
        info: ItemInfo.fromJson(m['info'] as Map<String, dynamic>, ItemInfo.hardcodedDefaults),
        previewPath: m['previewRef'] == null
            ? null
            : '$snapDir${Platform.pathSeparator}${(m['previewRef'] as String).replaceAll('/', Platform.pathSeparator)}',
        sizeInBytes: m['sizeInBytes'] as int? ?? 0,
        modifiedTime: DateTime.tryParse(m['modifiedTime'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
      items.add(item);
      final files = <SnapshotFileEntry>[];
      for (final f in (m['files'] as List<dynamic>? ?? [])) {
        files.add(SnapshotFileEntry.fromJson(f as Map<String, dynamic>));
      }
      itemFiles[item.path] = files;
    }
    final nodePath = json['path'] as String;
    final files = <DirectFile>[];
    for (final f in (json['files'] as List<dynamic>? ?? [])) {
      final m = f as Map<String, dynamic>;
      files.add(DirectFile(
        path: '$nodePath${Platform.pathSeparator}${m['name']}',
        name: m['name'] as String,
        sizeInBytes: m['size'] as int? ?? 0,
        modifiedTime:
            DateTime.tryParse(m['modified'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
      ));
    }
    return CategoryNode(
      path: nodePath,
      name: json['name'] as String,
      info: infoRaw == null
          ? null
          : ItemInfo.fromJson(infoRaw as Map<String, dynamic>, ItemInfo.hardcodedDefaults),
      subDirs: [
        for (final s in (json['subDirs'] as List<dynamic>? ?? []))
          _nodeFromJson(s as Map<String, dynamic>, snapDir, itemFiles),
      ],
      items: items,
      files: files,
    );
  }
}
