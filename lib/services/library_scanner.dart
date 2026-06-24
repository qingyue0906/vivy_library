import 'dart:convert';
import 'dart:io';

import '../models/category_node.dart';
import '../models/item_info.dart';
import '../models/library_item.dart';

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

    final nodeFutures = childDirPaths.map((path) => _buildNode(
      folderPath: path,
      isRootLevel: isRootLevel,
    ));
    final nodes = await Future.wait(nodeFutures);
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
    final entities = await _safeList(dir);

    final subDirPaths = <String>[];
    final directItemPaths = <String>[];

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

    // 并发构建子文件夹节点和直接项目
    final subDirFutures = subDirPaths.map((p) => _buildDirNodeRecursive(p));
    final itemFutures = directItemPaths.map((p) => buildSingleItem(
      category: folderName,
      categoryPath: folderPath,
      folderName: _baseName(p),
      itemPath: p,
    ));
    final subDirResults = await Future.wait(subDirFutures);
    final itemResults = await Future.wait(itemFutures);

    return CategoryNode(
      path: folderPath,
      name: folderName,
      info: info,
      subDirs: subDirResults.toList(),
      items: itemResults.toList(),
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
      _findPreviewFile(itemPath, null),
      _collectSizeAndModifiedTime(itemPath),
    ]);

    final info = results[0] as ItemInfo;
    final previewPath = results[1] as String?;
    final stats = results[2] as _SizeAndTime;

    // 如果 info 指定了 preview（相对路径），优先用之
    String? resolvedPreview = previewPath;
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
      sizeInBytes: stats.totalSize,
      modifiedTime: stats.latestModifiedTime,
    );
  }

  /// 读取并解析 info.json,失败或不存在时回退到默认值。
  Future<ItemInfo> _loadItemInfo(String itemPath, ItemInfo defaults) async {
    final jsonFile = File('$itemPath${Platform.pathSeparator}info.json');
    if (!await jsonFile.exists()) {
      return defaults;
    }
    try {
      final content = await jsonFile.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      return ItemInfo.fromJson(decoded, defaults);
    } catch (e) {
      return defaults;
    }
  }

  /// 寻找预览图:优先找文件名以 "preview" 开头的图片,找不到则用任意一张图片。
  /// [customPreviewRel] 是 info.json 指定的相对路径，优先级最高（在调用方处理）。
  Future<String?> _findPreviewFile(String itemPath, String? customPreviewRel) async {
    final dir = Directory(itemPath);
    if (!await dir.exists()) return null;

    final entries = (await _safeList(dir)).whereType<File>().toList();

    for (final file in entries) {
      final name = _baseName(file.path).toLowerCase();
      if (name == 'preview${_extOf(name)}') {
        return file.path;
      }
    }

    for (final file in entries) {
      final name = _baseName(file.path).toLowerCase();
      if (_hasPreviewExtension(name) && name != 'info.json') {
        return file.path;
      }
    }

    return null;
  }

  /// 从文件名提取小写扩展名（含点），无扩展返回空串。
  String _extOf(String lowerCaseFileName) {
    final dot = lowerCaseFileName.lastIndexOf('.');
    return dot >= 0 ? lowerCaseFileName.substring(dot) : '';
  }

  bool _hasPreviewExtension(String lowerCaseFileName) {
    return previewExtensions.any((ext) => lowerCaseFileName.endsWith(ext));
  }

  /// 递归遍历项目文件夹,统计总大小,并找出排除 info.json/预览图后
  /// 最新的业务文件修改时间。
  Future<_SizeAndTime> _collectSizeAndModifiedTime(String itemPath) async {
    int totalSize = 0;
    DateTime? latestModifiedTime;

    final dir = Directory(itemPath);
    if (!await dir.exists()) {
      return _SizeAndTime(0, DateTime.now());
    }

    try {
      final entities = await dir.list(recursive: true).toList();

      for (final entity in entities) {
        if (entity is! File) continue;

        final stat = await entity.stat();
        totalSize += stat.size;

        final fileName = _baseName(entity.path).toLowerCase();
        final isInfoFile = fileName == 'info.json';
        final isPreviewFile =
            fileName.startsWith('preview') && _hasPreviewExtension(fileName);

        if (!isInfoFile && !isPreviewFile) {
          final modified = stat.modified;
          if (latestModifiedTime == null || modified.isAfter(latestModifiedTime)) {
            latestModifiedTime = modified;
          }
        }
      }
    } catch (e) {
      // 对应 Python 的 except: pass
    }

    if (latestModifiedTime == null) {
      final dirStat = await dir.stat();
      latestModifiedTime = dirStat.modified;
    }

    return _SizeAndTime(totalSize, latestModifiedTime);
  }

  String _baseName(String fullPath) {
    final normalized = fullPath.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.last;
  }
}

class _SizeAndTime {
  final int totalSize;
  final DateTime latestModifiedTime;
  const _SizeAndTime(this.totalSize, this.latestModifiedTime);
}
