import 'dart:io';
import 'item_info.dart';
import 'library_item.dart';
import 'direct_file.dart';

/// 资源库的文件夹树节点。
///
/// 一个 CategoryNode 代表一个"分类文件夹"（define=='dir'），它可能包含：
/// - subDirs: 子文件夹（同样是 CategoryNode，可层层嵌套）
/// - items: 该文件夹"直接"包含的项目（define=='item' 或无 info 的文件夹）
///
/// 根目录是一个虚拟的 CategoryNode（path = 资源库根路径，info = null）。
class CategoryNode {
  final String path;
  final String name;
  final ItemInfo? info; // 文件夹自身的 info.json，可能没有
  final List<CategoryNode> subDirs;
  final List<LibraryItem> items;
  final List<DirectFile> files; // 该目录下的直接文件（非项目文件夹）

  const CategoryNode({
    required this.path,
    required this.name,
    this.info,
    this.subDirs = const [],
    this.items = const [],
    this.files = const [],
  });

  DateTime get modifiedTime {
    try { return File(path).lastModifiedSync(); } catch (_) { return DateTime.now(); }
  }
  int get sizeInBytes {
    int total = 0;
    for (final item in items) {
      total += item.sizeInBytes;
    }
    for (final file in files) {
      total += file.sizeInBytes;
    }
    for (final sub in subDirs) {
      total += sub.sizeInBytes;
    }
    return total;
  }

  /// 递归展平：返回该节点及其所有子文件夹下的全部项目。
  List<LibraryItem> get allItems {
    final result = <LibraryItem>[];
    result.addAll(items);
    for (final sub in subDirs) {
      result.addAll(sub.allItems);
    }
    return result;
  }

  /// 递归展平：返回该节点及其所有子文件夹下的全部直接文件。
  List<DirectFile> get allFiles {
    final result = <DirectFile>[];
    result.addAll(files);
    for (final sub in subDirs) {
      result.addAll(sub.allFiles);
    }
    return result;
  }

  /// 按路径查找子节点（含自身）。找不到返回 null。
  CategoryNode? findByPath(String targetPath) {
    if (path == targetPath) return this;
    for (final sub in subDirs) {
      final found = sub.findByPath(targetPath);
      if (found != null) return found;
    }
    return null;
  }

  /// 计算 [targetPath] 对应节点在本树中的所有祖先路径（从根到父节点）。
  /// 若 targetPath 不在本树中，返回空列表；若 targetPath 就是本节点，也返回空列表。
  List<String> ancestorPaths(String targetPath) {
    if (path == targetPath) return [];
    for (final sub in subDirs) {
      if (sub.path == targetPath) return [path];
      final found = sub.findByPath(targetPath);
      if (found != null) {
        return [path, ...sub.ancestorPaths(targetPath)];
      }
    }
    return [];
  }

  CategoryNode copyWith({
    String? path,
    String? name,
    ItemInfo? info,
    List<CategoryNode>? subDirs,
    List<LibraryItem>? items,
    List<DirectFile>? files,
  }) {
    return CategoryNode(
      path: path ?? this.path,
      name: name ?? this.name,
      info: info ?? this.info,
      subDirs: subDirs ?? this.subDirs,
      items: items ?? this.items,
      files: files ?? this.files,
    );
  }
}
