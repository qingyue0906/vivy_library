import 'dart:convert';
import 'dart:io';

import '../models/item_info.dart';
import '../models/library_item.dart';

/// 支持的预览图后缀,对应 Python 里的 PREVIEW_EXTS。
const List<String> previewExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];

/// 负责扫描根目录、读取每个项目的 info.json、定位预览图、统计大小和修改时间。
/// 对应原 Python 项目里 MainWindow.scan_all_items 方法。
///
/// 这一版全部改成异步(Future/async/await),磁盘 IO 不会阻塞 Flutter 的 UI 线程。
class LibraryScanner {
  /// 扫描根目录下所有分类文件夹及其子项目,返回 LibraryItem 列表。
  ///
  /// 返回类型是 Future<List<LibraryItem>>,意思是"将来会给你一份 LibraryItem 列表"。
  /// 调用方需要写 `await scanner.scanAll(path)` 才能拿到真正的列表。
  Future<List<LibraryItem>> scanAll(String rootDir) async {
    final items = <LibraryItem>[];
    final rootDirectory = Directory(rootDir);

    // exists() 是异步版本,对应之前的 existsSync()
    if (!await rootDirectory.exists()) {
      return items;
    }

    // 第一层:遍历根目录下的分类文件夹
    // dir.list() 返回一个 Stream(数据流,会陆续吐出条目),
    // 用 await ... .toList() 把流里所有条目收集成一个真正的 List 再处理。
    final categoryEntities = await rootDirectory.list().toList();

    for (final categoryEntity in categoryEntities) {
      if (categoryEntity is! Directory) continue;
      final categoryName = _baseName(categoryEntity.path);
      if (categoryName.startsWith('.')) continue;
      if (categoryName.toLowerCase() == 'tools') continue;

      final itemEntities = await categoryEntity.list().toList();

      // 收集这个分类下所有"需要处理的项目文件夹路径",
      // 稍后用 Future.wait 并发处理,而不是一个个排队等。
      final folderTasks = <Future<LibraryItem>>[];

      for (final itemEntity in itemEntities) {
        if (itemEntity is! Directory) continue;
        final folderName = _baseName(itemEntity.path);
        if (folderName.startsWith('.')) continue;

        // 注意这里没有 await —— 我们先把每个 _buildLibraryItem 调用产生的
        // Future"收集"起来,而不是马上等它完成。这样所有项目可以同时开始处理。
        folderTasks.add(_buildLibraryItem(
          category: categoryName,
          folderName: folderName,
          itemPath: itemEntity.path,
        ));
      }

      // Future.wait:并发等待这一批 Future 全部完成,
      // 类似 Python asyncio.gather(...)。比一个个 await 快很多,
      // 因为磁盘 IO 等待的时间是重叠的,不是累加的。
      final builtItems = await Future.wait(folderTasks);
      items.addAll(builtItems);
    }

    return items;
  }

  /// 处理单个项目文件夹,读取 info.json、定位预览图、统计大小和修改时间。
  Future<LibraryItem> _buildLibraryItem({
    required String category,
    required String folderName,
    required String itemPath,
  }) async {
    final defaults = ItemInfo.defaults(folderName);

    // 这三个子任务彼此独立,互不依赖,所以也用 Future.wait 并发执行,
    // 而不是写三个 await 顺序等待。
    final results = await Future.wait([
      _loadItemInfo(itemPath, defaults),
      _findPreviewFile(itemPath),
      _collectSizeAndModifiedTime(itemPath),
    ]);

    // Future.wait 返回一个 List<dynamic>(因为三个 Future 的结果类型不同),
    // 需要手动转换回各自的真实类型。这是用 Future.wait 混合类型时的小代价,
    // 等你熟悉了 Dart 3 的 Record 语法后,可以用更优雅的方式避免这个转换。
    final info = results[0] as ItemInfo;
    final previewPath = results[1] as String?;
    final stats = results[2] as _SizeAndTime;

    return LibraryItem(
      category: category,
      folderName: folderName,
      path: itemPath,
      info: info,
      previewPath: previewPath,
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
  Future<String?> _findPreviewFile(String itemPath) async {
    final dir = Directory(itemPath);
    if (!await dir.exists()) return null;

    final entries = (await dir.list().toList()).whereType<File>().toList();

    for (final file in entries) {
      final name = _baseName(file.path).toLowerCase();
      if (name.startsWith('preview') && _hasPreviewExtension(name)) {
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
      // list(recursive: true) 同样是异步版本,逐个吐出所有子文件/文件夹条目
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