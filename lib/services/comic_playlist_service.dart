import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import '../models/library_item.dart';
import '../models/comic_page.dart';

/// 递归扫描项目文件夹，构建图片/漫画阅读列表（扁平 entries + 文件夹树）。
/// 支持磁盘上的图片文件与 zip/cbz 压缩包（压缩包作为“虚拟文件夹”节点列出其内图片）。
class ComicPlaylistService {
  /// 受支持的图片扩展名（含 NeeView 支持范围的 bmp/tiff）。
  static const imageExts = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tif', 'tiff',
  };

  /// 受支持的压缩包扩展名（cbz 本质即 zip）。
  static const archiveExts = {'zip', 'cbz'};

  static String _ext(String path) =>
      p.extension(path).toLowerCase().replaceAll('.', '');

  static bool isImageFile(String path) => imageExts.contains(_ext(path));

  static bool isArchiveFile(String path) => archiveExts.contains(_ext(path));

  /// 是否为阅读器可打开的文件（图片或 zip/cbz）。
  static bool isReadableFile(String path) =>
      isImageFile(path) || isArchiveFile(path);

  // ===== 压缩包解码缓存（LRU，最多保留数个已解码的 Archive 目录）=====
  static final Map<String, Archive> _archiveCache = {};
  static final List<String> _archiveLru = [];
  static const _maxCachedArchives = 4;

  static Future<Archive> _getArchive(String archivePath) async {
    final cached = _archiveCache[archivePath];
    if (cached != null) {
      _archiveLru
        ..remove(archivePath)
        ..add(archivePath);
      return cached;
    }
    final bytes = await File(archivePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    _archiveCache[archivePath] = archive;
    _archiveLru.add(archivePath);
    while (_archiveLru.length > _maxCachedArchives) {
      final evict = _archiveLru.removeAt(0);
      _archiveCache.remove(evict);
    }
    return archive;
  }

  // ===== 已解压页字节缓存（LRU，供主图与缩略图共享，避免重复解压）=====
  static final Map<String, Uint8List> _pageBytes = {};
  static final List<String> _pageLru = [];
  static const _maxCachedPages = 12;

  static void _cachePage(String id, Uint8List bytes) {
    _pageBytes[id] = bytes;
    _pageLru
      ..remove(id)
      ..add(id);
    while (_pageLru.length > _maxCachedPages) {
      _pageBytes.remove(_pageLru.removeAt(0));
    }
  }

  /// 同步窥探已缓存的页字节（未缓存返回 null，用于避免已解压页的重复异步与闪烁）。
  static Uint8List? peekPageBytes(String id) => _pageBytes[id];

  /// 读取单页的图片字节：直接图从磁盘读取；压缩包内条目解压后返回（带缓存）。失败返回 null。
  static Future<Uint8List?> readPageBytes(ComicPage page) async {
    final cached = _pageBytes[page.id];
    if (cached != null) {
      _pageLru
        ..remove(page.id)
        ..add(page.id);
      return cached;
    }
    try {
      if (!page.isArchived) {
        final bytes = await File(page.sourcePath!).readAsBytes();
        _cachePage(page.id, bytes);
        return bytes;
      }
      final archive = await _getArchive(page.archivePath!);
      for (final f in archive.files) {
        if (f.isFile && f.name == page.entryName) {
          final content = f.content as List<int>;
          final bytes =
              content is Uint8List ? content : Uint8List.fromList(content);
          _cachePage(page.id, bytes);
          return bytes;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 构建项目内全部图片/压缩包的阅读列表。
  static Future<ComicPlaylist> build(LibraryItem item) =>
      buildFromPath(item.path);

  /// 直接扫描一个文件夹路径构建阅读列表（用于“打开文件夹”）。
  static Future<ComicPlaylist> buildFromPath(String root) async {
    final rootNode = ComicFolderNode(p.basename(root), root);
    if (Directory(root).existsSync()) {
      await _scan(Directory(root), rootNode);
    }
    _sortNode(rootNode);
    final entries = <ComicPage>[];
    _collect(rootNode, entries);
    return ComicPlaylist(entries: entries, tree: [rootNode]);
  }

  static Future<void> _scan(Directory dir, ComicFolderNode node) async {
    List<FileSystemEntity> list;
    try {
      list = dir.listSync();
    } catch (_) {
      return;
    }
    final subDirs = <Directory>[];
    for (final e in list) {
      if (e is Directory) {
        subDirs.add(e);
      } else if (e is File) {
        final path = e.path;
        if (isImageFile(path)) {
          int size;
          try {
            size = e.lengthSync();
          } catch (_) {
            size = 0;
          }
          node.files.add(ComicPage(
            id: path,
            sourcePath: path,
            name: p.basename(path),
            dirPath: dir.path,
            sizeInBytes: size,
          ));
        } else if (isArchiveFile(path)) {
          final archiveNode = await _buildArchiveNode(path);
          if (archiveNode != null && archiveNode.files.isNotEmpty) {
            node.children.add(archiveNode);
          }
        }
      }
    }
    for (final d in subDirs) {
      final child = ComicFolderNode(p.basename(d.path), d.path);
      await _scan(d, child);
      if (child.files.isNotEmpty || child.children.isNotEmpty) {
        node.children.add(child);
      }
    }
  }

  /// 将 zip/cbz 解析为一个“虚拟文件夹”节点，列出其内的图片条目。
  static Future<ComicFolderNode?> _buildArchiveNode(String archivePath) async {
    try {
      final archive = await _getArchive(archivePath);
      final node = ComicFolderNode(
        p.basename(archivePath),
        archivePath,
        isArchive: true,
      );
      for (final f in archive.files) {
        if (f.isFile && isImageFile(f.name)) {
          final normalized = f.name.replaceAll('\\', '/');
          node.files.add(ComicPage(
            id: '$archivePath::${f.name}',
            archivePath: archivePath,
            entryName: f.name,
            name: normalized.split('/').last,
            dirPath: archivePath,
            sizeInBytes: f.size,
          ));
        }
      }
      node.files.sort((a, b) => _naturalCompare(a.entryName!, b.entryName!));
      return node;
    } catch (_) {
      return null;
    }
  }

  static void _sortNode(ComicFolderNode node) {
    node.files.sort((a, b) => _naturalCompare(a.name, b.name));
    node.children.sort((a, b) => _naturalCompare(a.name, b.name));
    for (final c in node.children) {
      _sortNode(c);
    }
  }

  /// DFS 收集阅读顺序：先本节点图片，后递归子节点（保证 entries 与树顺序一致）。
  static void _collect(ComicFolderNode node, List<ComicPage> out) {
    out.addAll(node.files);
    for (final c in node.children) {
      _collect(c, out);
    }
  }

  /// 自然排序：把连续数字段按数值比较，使 1,2,10 而非 1,10,2。大小写不敏感。
  static int _naturalCompare(String a, String b) {
    final sa = a.toLowerCase();
    final sb = b.toLowerCase();
    var ia = 0;
    var ib = 0;
    while (ia < sa.length && ib < sb.length) {
      final ca = sa.codeUnitAt(ia);
      final cb = sb.codeUnitAt(ib);
      final da = ca >= 0x30 && ca <= 0x39;
      final db = cb >= 0x30 && cb <= 0x39;
      if (da && db) {
        // 读取两侧完整数字段
        var ja = ia;
        while (ja < sa.length && sa.codeUnitAt(ja) >= 0x30 && sa.codeUnitAt(ja) <= 0x39) {
          ja++;
        }
        var jb = ib;
        while (jb < sb.length && sb.codeUnitAt(jb) >= 0x30 && sb.codeUnitAt(jb) <= 0x39) {
          jb++;
        }
        // 去前导零后按长度、再按字典序比较
        final na = sa.substring(ia, ja).replaceFirst(RegExp(r'^0+(?=\d)'), '');
        final nb = sb.substring(ib, jb).replaceFirst(RegExp(r'^0+(?=\d)'), '');
        if (na.length != nb.length) return na.length - nb.length;
        final cmp = na.compareTo(nb);
        if (cmp != 0) return cmp;
        ia = ja;
        ib = jb;
      } else {
        if (ca != cb) return ca - cb;
        ia++;
        ib++;
      }
    }
    return (sa.length - ia) - (sb.length - ib);
  }
}
