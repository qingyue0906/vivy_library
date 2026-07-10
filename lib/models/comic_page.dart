/// 漫画/图片阅读器中的单页。
///
/// 两种来源：
/// - 直接图片：[sourcePath] 指向磁盘上的图片文件，[archivePath]/[entryName] 为 null。
/// - 压缩包内图片：[archivePath] 指向 zip/cbz 文件，[entryName] 为包内条目名，
///   [sourcePath] 为 null（读取时通过 [ComicPlaylistService.readPageBytes] 解压）。
class ComicPage {
  /// 唯一标识：直接图=文件路径；压缩包内=archivePath + '::' + entryName。
  final String id;

  /// 直接图片的磁盘路径（压缩包内条目为 null）。
  final String? sourcePath;

  /// 所属压缩包路径（直接图为 null）。
  final String? archivePath;

  /// 压缩包内条目完整名（直接图为 null）。
  final String? entryName;

  /// 显示名（文件名 / 条目名的 basename）。
  final String name;

  /// 归属目录：直接图=父目录绝对路径；压缩包内=压缩包路径（用于树展开定位）。
  final String dirPath;

  final int sizeInBytes;

  ComicPage({
    required this.id,
    this.sourcePath,
    this.archivePath,
    this.entryName,
    required this.name,
    required this.dirPath,
    required this.sizeInBytes,
  });

  /// 是否为压缩包内条目。
  bool get isArchived => archivePath != null;

  String get sizeText {
    final b = sizeInBytes;
    if (b < 1024) return '$b B';
    final kb = b / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
}

/// 文件夹树节点：children 为子文件夹（或压缩包节点），files 为该节点下的图片页。
/// [isArchive] 为 true 时表示该节点是一个 zip/cbz 压缩包（作为“虚拟文件夹”呈现）。
class ComicFolderNode {
  final String name;
  final String path; // 文件夹绝对路径 / 压缩包绝对路径
  final bool isArchive;
  final List<ComicFolderNode> children = [];
  final List<ComicPage> files = [];

  ComicFolderNode(this.name, this.path, {this.isArchive = false});
}

/// 一次构建出的完整阅读列表：扁平 entries（按阅读顺序）+ tree（用于侧边页码/文件夹树展示）。
class ComicPlaylist {
  final List<ComicPage> entries;
  final List<ComicFolderNode> tree;

  ComicPlaylist({required this.entries, required this.tree});
}
