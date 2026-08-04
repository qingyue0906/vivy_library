import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../models/category_node.dart';
import '../models/item_info.dart';
import '../models/library_item.dart';
import '../models/direct_file.dart';

/// 支持的预览图后缀,对应 Python 里的 PREVIEW_EXTS。
const List<String> previewExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];

/// 默认跳过的 Windows/Linux 系统文件夹（不区分大小写）。
const Set<String> _systemFolderNames = {
  '\$recycle.bin',
  'system volume information',
  '\$winreagent',
  'config.msi',
  'msocache',
  'recovery',
};

/// 负责扫描根目录、递归构建文件夹树、读取每个项目/文件夹的 info.json、
/// 定位预览图、统计大小和修改时间。
///
/// 扫描规则：
/// - 根目录第一层文件夹默认当作 dir（分类文件夹，即使无 info.json）。
/// - 第二层起，读取 info.json 的 define 字段：
///   - 'dir' → 递归为 CategoryNode（文件夹）
///   - 'item' 或无 info / 无 define → 当作 LibraryItem（项目）
/// - 跳过以 '.' 开头的文件夹、'tools' 文件夹，以及 _systemFolderNames 中的系统文件夹。
class LibraryScanner {
  /// 扫描根目录，返回虚拟根 CategoryNode（path=rootDir，info=null）。
  Future<CategoryNode> scanAll(String rootDir) async {
    final rootDirectory = Directory(rootDir);
    if (!await rootDirectory.exists()) {
      return CategoryNode(path: rootDir, name: _baseName(rootDir));
    }

    final subDirs = await _scanLevel(
      parentPath: rootDir,
      isRootLevel: true,
    );
    return CategoryNode(
      path: rootDir,
      name: _baseName(rootDir),
      subDirs: subDirs,
    );
  }

  /// 判断文件夹名是否为默认系统文件夹（不区分大小写）。
  bool _isSystemFolder(String name) {
    return _systemFolderNames.contains(name.toLowerCase());
  }

  /// 安全地列出目录内容，遇到无权限等错误时返回空列表，避免整个扫描崩溃。
  Future<List<FileSystemEntity>> _safeList(Directory dir,
      {bool recursive = false}) async {
    try {
      return await dir.list(recursive: recursive).toList();
    } catch (e) {
      return [];
    }
  }

  /// 有界并发执行 [fn]：最多 [limit] 个任务同时运行，按原顺序返回结果。
  /// 避免大库下对全部子目录/文件同时开任务导致 IO 抖动。
  Future<List<R>> _mapConcurrent<T, R>(
    List<T> items,
    int limit,
    Future<R> Function(T item) fn,
  ) async {
    final results = List<R?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= items.length) return;
        results[i] = await fn(items[i]);
      }
    }

    final count = items.isEmpty ? 0 : limit.clamp(1, items.length);
    await Future.wait(List.generate(count, (_) => worker()));
    return results.map((r) => r as R).toList();
  }

  /// 用 FindFirstFileW/FindNextFileW 枚举目录（[maxDepth] 限制递归深度，
  /// 1=仅当前目录，null=不限），直接在枚举中取到每个条目的大小与修改
  /// 时间（WIN32_FIND_DATA 自带），避免对每个文件额外 stat。
  ///
  /// 实测在装有实时杀软/安全软件的机器上 File.stat 单次约 0.5ms 且不随
  /// 并发扩展，是大量小文件库刷新慢的主因；FindFirstFile 枚举则零额外
  /// 系统调用。已访问目录集合防止 junction/符号链接成环。
  List<_DirEntry> _win32Walk(String dirPath, {int? maxDepth}) {
    final results = <_DirEntry>[];
    final visited = <String>{dirPath.toLowerCase()};
    final stack = <(String, int)>[(dirPath, 0)];
    while (stack.isNotEmpty) {
      final (dir, depth) = stack.removeLast();
      final searchPath = '$dir\\*'.toNativeUtf16();
      final findData = calloc.allocate<WIN32_FIND_DATA>(
        sizeOf<WIN32_FIND_DATA>(),
      );
      final handle = FindFirstFile(searchPath, findData);
      malloc.free(searchPath);
      if (handle == INVALID_HANDLE_VALUE) {
        calloc.free(findData);
        continue;
      }
      try {
        var ok = true;
        while (ok) {
          final ref = findData.ref;
          final name = ref.cFileName;
          if (name != '.' && name != '..') {
            final full = '$dir\\$name';
            final isDir =
                (ref.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
            final size =
                ref.nFileSizeHigh * 0x100000000 + ref.nFileSizeLow;
            final modified = _fileTimeToDateTime(ref.ftLastWriteTime);
            results.add(_DirEntry(full, isDir, size, modified));
            if (isDir && (maxDepth == null || depth + 1 < maxDepth)) {
              if (visited.add(full.toLowerCase())) {
                stack.add((full, depth + 1));
              }
            }
          }
          ok = FindNextFile(handle, findData) != 0;
        }
      } finally {
        FindClose(handle);
        calloc.free(findData);
      }
    }
    return results;
  }

  /// FILETIME（1601-01-01 起的 100ns 间隔，UTC）转本地时间。
  DateTime _fileTimeToDateTime(FILETIME ft) {
    final ticks = (ft.dwHighDateTime << 32) + ft.dwLowDateTime;
    final micros = ticks ~/ 10 - 11644473600000000;
    return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true).toLocal();
  }

  /// 扫描某一层文件夹，返回该层的子文件夹节点列表 + 直接项目列表。
  /// 分类节点（dir）会递归；项目节点（item）构建为 LibraryItem 并放入 items。
  Future<List<CategoryNode>> _scanLevel({
    required String parentPath,
    required bool isRootLevel,
  }) async {
    final dir = Directory(parentPath);
    if (!await dir.exists()) return [];

    final entities = await _safeList(dir);

    // 先收集所有子文件夹路径，并发处理
    final childDirPaths = <String>[];
    for (final e in entities) {
      if (e is! Directory) continue;
      final name = _baseName(e.path);
      if (name.startsWith('.')) continue;
      if (name.toLowerCase() == 'tools') continue;
      if (_isSystemFolder(name)) continue;
      childDirPaths.add(e.path);
    }

    final nodes = await _mapConcurrent(
      childDirPaths,
      16,
      (path) => _buildNode(folderPath: path, isRootLevel: isRootLevel),
    );
    return nodes.whereType<CategoryNode>().toList();
  }

  /// 处理单个子文件夹：读 info 决定是 dir 还是 item。
  /// - 根目录第一层：强制为 dir（CategoryNode）。
  /// - 深层：define=='dir' → CategoryNode（递归）；否则 → item（LibraryItem）。
  /// 注意：item 会作为"父文件夹的 items"返回，所以这里返回 CategoryNode?，
  /// item 情况返回 null 并通过 outItems 回收项目。
  Future<CategoryNode?> _buildNode({
    required String folderPath,
    required bool isRootLevel,
  }) async {
    final folderName = _baseName(folderPath);
    final defaults = ItemInfo.defaults(folderName);
    final info = await _loadItemInfo(folderPath, defaults);

    // define == 'hide' 的文件夹/项目不在资源库中展示
    if (info.define == 'hide') {
      return null;
    }

    // 根目录第一层强制为 dir（hide 已提前排除）
    if (isRootLevel) {
      return await _buildDirNode(folderPath, folderName, info);
    }

    // 深层看 define
    if (info.define == 'dir') {
      return await _buildDirNode(folderPath, folderName, info);
    }

    // 当作 item（_buildLibraryItem 由调用方按需处理，这里返回 null 标记非 dir）
    // 但 _scanLevel 需要 item，所以我们改用另一种结构：返回的 node 的 items 里放它
    // 为了保持 _scanLevel 简单，这里把 item 情况编码为带特殊标记的 node
    // ——改用直接返回 _ItemMarker 让 _scanLevel 分流。
    return null;
  }

  /// 构建一个 dir 节点：递归扫描子层，把子层的 item 收进 this.items。
  Future<CategoryNode> _buildDirNode(
    String folderPath,
    String folderName,
    ItemInfo? info,
  ) async {
    final dir = Directory(folderPath);

    final subDirPaths = <String>[];
    final directItemPaths = <String>[];
    final directFiles = <DirectFile>[];

    if (Platform.isWindows) {
      // Windows：一次 FindFirstFile 枚举（深度 1）直接拿到
      // 子目录与直接文件的大小/修改时间，零额外 stat
      for (final e in _win32Walk(folderPath, maxDepth: 1)) {
        if (e.isDir) {
          final name = _baseName(e.path);
          if (name.startsWith('.')) continue;
          if (_isSystemFolder(name)) continue;
          // 深层子文件夹：读 info 判断 dir/item/hide
          final childDefaults = ItemInfo.defaults(name);
          final childInfo = await _loadItemInfo(e.path, childDefaults);
          if (childInfo.define == 'hide') continue;
          if (childInfo.define == 'dir') {
            subDirPaths.add(e.path);
          } else {
            directItemPaths.add(e.path);
          }
        } else {
          final name = _baseName(e.path);
          if (name.startsWith('.')) continue;
          if (name == 'info.json' || name == 'presets.json') continue;
          directFiles.add(DirectFile(
            path: e.path,
            name: name,
            sizeInBytes: e.size,
            modifiedTime: e.modified,
          ));
        }
      }
    } else {
      final entities = await _safeList(dir);

      for (final e in entities) {
        if (e is! Directory) continue;
        final name = _baseName(e.path);
        if (name.startsWith('.')) continue;
        if (_isSystemFolder(name)) continue;
        // 深层子文件夹：读 info 判断 dir/item/hide
        final childDefaults = ItemInfo.defaults(name);
        final childInfo = await _loadItemInfo(e.path, childDefaults);
        if (childInfo.define == 'hide') {
          continue;
        }
        if (childInfo.define == 'dir') {
          subDirPaths.add(e.path);
        } else {
          directItemPaths.add(e.path);
        }
      }

      // 收集直接文件（非目录）：并发 stat，避免 statSync 阻塞事件循环
      final directFilePairs = <(String, String)>[];
      for (final e in entities) {
        if (e is! File) continue;
        final name = _baseName(e.path);
        if (name.startsWith('.')) continue;
        if (name == 'info.json' || name == 'presets.json') continue;
        directFilePairs.add((e.path, name));
      }
      directFiles.addAll((await _mapConcurrent(
        directFilePairs,
        32,
        (p) async {
          try {
            final stat = await File(p.$1).stat();
            return DirectFile(
              path: p.$1,
              name: p.$2,
              sizeInBytes: stat.size,
              modifiedTime: stat.modified,
            );
          } catch (_) {
            return null;
          }
        },
      )).whereType<DirectFile>());
    }

    // 有界并发构建子文件夹节点和直接项目
    final subDirResults = await _mapConcurrent(
      subDirPaths,
      16,
      _buildDirNodeRecursive,
    );
    final itemResults = await _mapConcurrent(
      directItemPaths,
      16,
      (p) => buildSingleItem(
        category: folderName,
        categoryPath: folderPath,
        folderName: _baseName(p),
        itemPath: p,
      ),
    );

    return CategoryNode(
      path: folderPath,
      name: folderName,
      info: info,
      subDirs: subDirResults.toList(),
      items: itemResults.toList(),
      files: directFiles,
    );
  }

  /// 递归构建子文件夹节点（深层，已确认 define=='dir'）。
  Future<CategoryNode> _buildDirNodeRecursive(String folderPath) async {
    final folderName = _baseName(folderPath);
    final defaults = ItemInfo.defaults(folderName);
    final info = await _loadItemInfo(folderPath, defaults);
    return _buildDirNode(folderPath, folderName, info);
  }

  /// 处理单个项目文件夹,读取 info.json、定位预览图、统计大小和修改时间。
  /// 公开方法，供 goto path 即时扫描嵌套 item 使用。
  Future<LibraryItem> buildSingleItem({
    required String category,
    required String categoryPath,
    required String folderName,
    required String itemPath,
  }) async {
    final defaults = ItemInfo.defaults(folderName);

    final results = await Future.wait([
      _loadItemInfo(itemPath, defaults),
      _scanItemFiles(itemPath),
    ]);

    final info = results[0] as ItemInfo;
    final scan = results[1] as _ItemScan;

    // 如果 info 指定了 preview（相对路径），优先用之
    String? resolvedPreview = scan.previewPath;
    if (info.preview != null && info.preview!.isNotEmpty) {
      final candidate = File('$itemPath${Platform.pathSeparator}${info.preview}');
      if (await candidate.exists()) {
        resolvedPreview = candidate.path;
      }
    }

    return LibraryItem(
      category: category,
      categoryPath: categoryPath,
      folderName: folderName,
      path: itemPath,
      info: info,
      previewPath: resolvedPreview,
      sizeInBytes: scan.totalSize,
      modifiedTime: scan.latestModifiedTime,
    );
  }

  /// 读取并解析 info.json,失败或不存在时回退到默认值。
  Future<ItemInfo> _loadItemInfo(String itemPath, ItemInfo defaults) async {
    final jsonFile = File('$itemPath${Platform.pathSeparator}info.json');
    try {
      final content = await jsonFile.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      return ItemInfo.fromJson(decoded, defaults);
    } catch (e) {
      return defaults;
    }
  }

  /// 单次递归列举 + 并发 stat，一次性完成项目三项统计：
  /// 顶层预览图定位、总大小、排除 info.json/预览图后的最新业务文件时间。
  /// Windows 上用 FindFirstFile 枚举（零 stat），其他平台回退到
  /// Dart 递归列举 + 并发 stat。
  Future<_ItemScan> _scanItemFiles(String itemPath) async {
    final dir = Directory(itemPath);
    if (!await dir.exists()) {
      return _ItemScan(0, DateTime.now(), null);
    }

    final List<_DirEntry> entries;
    if (Platform.isWindows) {
      entries = _win32Walk(itemPath);
    } else {
      final entities = await _safeList(dir, recursive: true);
      final files = entities.whereType<File>().toList();
      final stats = await _mapConcurrent(files, 32, (f) async {
        try {
          return await f.stat();
        } catch (_) {
          return null;
        }
      });
      entries = [
        for (var i = 0; i < files.length; i++)
          if (stats[i] != null)
            _DirEntry(
              files[i].path,
              false,
              stats[i]!.size,
              stats[i]!.modified,
            ),
      ];
    }

    var (totalSize, mtime, previewPath) = _computeScan(itemPath, entries);
    DateTime latest;
    if (mtime != null) {
      latest = mtime;
    } else {
      try {
        latest = (await dir.stat()).modified;
      } catch (_) {
        latest = DateTime.now();
      }
    }
    return _ItemScan(totalSize, latest, previewPath);
  }

  /// 从条目列表（含大小/修改时间）计算项目统计：
  /// 总大小、最新业务文件时间（可能为空）、顶层预览图。
  (int, DateTime?, String?) _computeScan(
    String itemPath,
    List<_DirEntry> entries,
  ) {
    int totalSize = 0;
    DateTime? latestModifiedTime;
    final topLevelPaths = <String>[];
    final prefixLen = itemPath.length;
    for (final e in entries) {
      if (e.isDir) continue;
      final rel = e.path
          .substring(prefixLen)
          .replaceFirst(RegExp(r'^[\\/]'), '')
          .replaceAll('\\', '/');
      if (!rel.contains('/')) topLevelPaths.add(e.path);

      totalSize += e.size;
      final fileName = _baseName(e.path).toLowerCase();
      final isInfoFile = fileName == 'info.json';
      final isPreviewFile =
          fileName.startsWith('preview') && _hasPreviewExtension(fileName);
      if (!isInfoFile && !isPreviewFile) {
        final modified = e.modified;
        if (latestModifiedTime == null ||
            modified.isAfter(latestModifiedTime)) {
          latestModifiedTime = modified;
        }
      }
    }

    String? previewPath;
    for (final path in topLevelPaths) {
      final name = _baseName(path).toLowerCase();
      if (name == 'preview${_extOf(name)}') {
        previewPath = path;
        break;
      }
    }
    if (previewPath == null) {
      for (final path in topLevelPaths) {
        final name = _baseName(path).toLowerCase();
        if (_hasPreviewExtension(name) && name != 'info.json') {
          previewPath = path;
          break;
        }
      }
    }

    return (totalSize, latestModifiedTime, previewPath);
  }

  /// 从文件名提取小写扩展名（含点），无扩展返回空串。
  String _extOf(String lowerCaseFileName) {
    final dot = lowerCaseFileName.lastIndexOf('.');
    return dot >= 0 ? lowerCaseFileName.substring(dot) : '';
  }

  bool _hasPreviewExtension(String lowerCaseFileName) {
    return previewExtensions.any((ext) => lowerCaseFileName.endsWith(ext));
  }

  String _baseName(String fullPath) {
    final normalized = fullPath.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.last;
  }
}

/// 单次递归扫描一个项目文件夹的统计结果。
class _ItemScan {
  final int totalSize;
  final DateTime latestModifiedTime;
  final String? previewPath;
  const _ItemScan(this.totalSize, this.latestModifiedTime, this.previewPath);
}

/// 目录枚举条目（大小与修改时间来自枚举本身，无需 stat）。
class _DirEntry {
  final String path;
  final bool isDir;
  final int size;
  final DateTime modified;
  const _DirEntry(this.path, this.isDir, this.size, this.modified);
}
