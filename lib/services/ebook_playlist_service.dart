import 'package:path/path.dart' as p;
import '../models/ebook_book.dart';
import '../models/library_item.dart';
import 'ebook_service.dart';

/// 电子书阅读列表：项目内全部可打开的电子书文件（txt/epub/pdf/md）。
/// 与漫画阅读列表不同，电子书阅读器一次只载入其中一本书；
/// 右侧面板同时显示项目内的书籍文件夹树(tree) 与当前书的目录(TOC)。
class EbookPlaylist {
  final List<String> entries; // 书文件路径
  final List<String> names; // 对应文件名（用于书切换器展示）
  final List<EbookFolderNode> tree; // 项目内书籍的文件夹树（用于右侧树形浏览）

  EbookPlaylist({
    required this.entries,
    required this.names,
    required this.tree,
  });

  /// 在项目根目录下构建一棵文件夹树，仅包含电子书文件（如同视频播放列表的 tree）。
  static List<EbookFolderNode> buildTree(String root, List<String> files) {
    final rootNode = EbookFolderNode(p.basename(root), root);
    for (final f in files) {
      final rel = p.relative(f, from: root);
      final parts = p.split(rel);
      var node = rootNode;
      for (var i = 0; i < parts.length - 1; i++) {
        final seg = parts[i];
        final childPath = p.join(node.path, seg);
        EbookFolderNode? child;
        for (final c in node.children) {
          if (c.path == childPath) {
            child = c;
            break;
          }
        }
        if (child == null) {
          child = EbookFolderNode(seg, childPath);
          node.children.add(child);
        }
        node = child;
      }
      node.files.add(EbookFileEntry(path: f, name: parts.last));
    }
    _sortNode(rootNode);
    return [rootNode];
  }

  static void _sortNode(EbookFolderNode node) {
    node.files
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    node.children.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    for (final c in node.children) {
      _sortNode(c);
    }
  }
}

class EbookPlaylistService {
  /// 构建项目内全部电子书的阅读列表。
  static Future<EbookPlaylist> build(LibraryItem item) =>
      buildFromPath(item.path);

  static Future<EbookPlaylist> buildFromPath(String root) async {
    final paths = await EbookService.scanBookPaths(root);
    final names = paths.map((e) => p.basename(e)).toList();
    final tree = EbookPlaylist.buildTree(root, paths);
    return EbookPlaylist(entries: paths, names: names, tree: tree);
  }
}
