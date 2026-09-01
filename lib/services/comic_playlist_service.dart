import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart'
    show Archive, InputFileStream, ZipDecoder;
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

  // ===== 压缩包中心目录索引缓存（LRU）=====
  // 只保存条目元数据（名称/压缩方法/大小/本地头偏移），不持有整包内容；
  // 单页读取时按偏移只解压该条目，避免整包解压内容常驻内存。
  static final Map<String, _ZipIndex> _indexCache = {};
  static final List<String> _indexLru = [];
  static const _maxCachedIndexes = 4;

  /// 回退路径用的流式解码缓存（zip 中心目录解析失败时使用）。
  /// archive 包的 zip 条目内容是惰性的：条目数据按需从 [InputFileStream]
  /// 读取，因此流必须保持打开直到缓存被淘汰，淘汰/清空时 close 释放句柄。
  static final Map<String, _ArchiveHandle> _archiveCache = {};
  static final List<String> _archiveLru = [];
  static const _maxCachedArchives = 4;

  // ===== 已解压页字节缓存（LRU，页数与字节数双上限）=====
  static final Map<String, Uint8List> _pageBytes = {};
  static final List<String> _pageLru = [];
  static const _maxCachedPages = 12;
  static const _maxCachedPageBytes = 192 * 1024 * 1024;
  static int _cachedPageBytes = 0;

  /// 读取压缩包中心目录索引：只读包尾 EOCD + 中央目录（不读整包）。
  /// 支持 zip64（包 >4GB 或条目 >65535）：通过 Zip64 EOCD Locator/Record
  /// 与条目 extra field 0x0001 读取 64 位大小与偏移。
  /// 解析失败返回 null（调用方回退到 InputFileStream 流式解码，同样不整包入内存）。
  static Future<_ZipIndex?> _readZipIndex(String archivePath) async {
    final file = File(archivePath);
    final length = await file.length();
    const eocdMin = 22;
    if (length < eocdMin) return null;
    final raf = await file.open();
    try {
      // EOCD 在文件末尾 22 字节处（可带最长 65535 字节注释），
      // 读取尾部在最后 64KB+22 字节内倒查签名 0x06054b50。
      final tailLen = length > eocdMin + 0xFFFF ? eocdMin + 0xFFFF : length;
      await raf.setPosition(length - tailLen);
      final tail = await raf.read(tailLen);
      var eocdPos = -1;
      for (var i = tailLen - eocdMin; i >= 0; i--) {
        if (_u32(tail, i) == 0x06054b50) {
          eocdPos = i;
          break;
        }
      }
      if (eocdPos < 0) return null;

      var totalEntries = _u16(tail, eocdPos + 10);
      var cdSize = _u32(tail, eocdPos + 12);
      var cdOffset = _u32(tail, eocdPos + 16);
      // zip64 标志：EOCD 字段为 0xFFFF/0xFFFFFFFF 时读取 Zip64 记录。
      if (totalEntries == 0xFFFF || cdSize == 0xFFFFFFFF ||
          cdOffset == 0xFFFFFFFF) {
        final parsed = await _readZip64Eocd(raf, tail, eocdPos);
        if (parsed == null) return null;
        totalEntries = parsed.$1;
        cdSize = parsed.$2;
        cdOffset = parsed.$3;
      }

      await raf.setPosition(cdOffset);
      final cd = await raf.read(cdSize);
      if (cd.length != cdSize) return null;
      final entries = <_ZipEntry>[];
      var pos = 0;
      while (pos + 46 <= cd.length) {
        if (_u32(cd, pos) != 0x02014b50) break;
        final method = _u16(cd, pos + 10);
        var compressedSize = _u32(cd, pos + 20);
        var uncompressedSize = _u32(cd, pos + 24);
        final nameLen = _u16(cd, pos + 28);
        final extraLen = _u16(cd, pos + 30);
        final commentLen = _u16(cd, pos + 32);
        var localHeaderOffset = _u32(cd, pos + 42);
        final name = utf8.decode(
          cd.sublist(pos + 46, pos + 46 + nameLen),
          allowMalformed: true,
        );
        // Zip64 extended information (extra id 0x0001)：仅当对应 u32 字段
        // 为 0xFFFFFFFF 时按固定顺序补齐 64 位值。
        var ex = pos + 46 + nameLen;
        final exEnd = ex + extraLen;
        while (ex + 4 <= exEnd) {
          final id = _u16(cd, ex);
          final size = _u16(cd, ex + 2);
          final dataStart = ex + 4;
          final dataEnd = dataStart + size;
          if (id == 0x0001) {
            var p = dataStart;
            if (uncompressedSize == 0xFFFFFFFF && p + 8 <= dataEnd) {
              uncompressedSize = _u64(cd, p);
              p += 8;
            }
            if (compressedSize == 0xFFFFFFFF && p + 8 <= dataEnd) {
              compressedSize = _u64(cd, p);
              p += 8;
            }
            if (localHeaderOffset == 0xFFFFFFFF && p + 8 <= dataEnd) {
              localHeaderOffset = _u64(cd, p);
              p += 8;
            }
          }
          ex = dataEnd;
        }
        // 跳过目录条目（名称以 / 或 \ 结尾）
        if (!name.endsWith('/') && !name.endsWith('\\')) {
          entries.add(_ZipEntry(
            name: name,
            method: method,
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            localHeaderOffset: localHeaderOffset,
          ));
        }
        pos += 46 + nameLen + extraLen + commentLen;
      }
      if (entries.isEmpty) return null;
      return _ZipIndex(entries);
    } catch (_) {
      return null;
    } finally {
      await raf.close();
    }
  }

  /// 读取 Zip64 EOCD：定位器（0x07064b50）固定位于 EOCD 前 20 字节，
  /// 内含 Zip64 EOCD Record 偏移；Record（0x06064b50）从 +32 起依次为
  /// 8 字节 totalEntries、cdSize、cdOffset。返回 (totalEntries, cdSize, cdOffset)。
  static Future<(int, int, int)?> _readZip64Eocd(
    RandomAccessFile raf,
    List<int> tail,
    int eocdPos,
  ) async {
    final locPos = eocdPos - 20;
    if (locPos < 0 || _u32(tail, locPos) != 0x07064b50) return null;
    final zip64EocdOffset = _u64(tail, locPos + 8);
    await raf.setPosition(zip64EocdOffset);
    final rec = await raf.read(56);
    if (rec.length != 56 || _u32(rec, 0) != 0x06064b50) return null;
    var totalEntries = _u64(rec, 32);
    if (totalEntries == 0) totalEntries = _u64(rec, 24);
    final cdSize = _u64(rec, 40);
    final cdOffset = _u64(rec, 48);
    if (cdSize == 0 || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) {
      return null;
    }
    return (totalEntries, cdSize, cdOffset);
  }

  static Future<_ZipIndex?> _getZipIndex(String archivePath) async {
    final cached = _indexCache[archivePath];
    if (cached != null) {
      _indexLru
        ..remove(archivePath)
        ..add(archivePath);
      return cached;
    }
    final index = await _readZipIndex(archivePath);
    if (index == null) return null;
    _indexCache[archivePath] = index;
    _indexLru.add(archivePath);
    while (_indexLru.length > _maxCachedIndexes) {
      _indexCache.remove(_indexLru.removeAt(0));
    }
    return index;
  }

  /// 按中心目录条目读取并解压单个文件：seek 到本地头，只读该条目
  /// 的压缩字节后解压，整包内容不进入内存。
  /// stored（0）直接返回压缩字节；deflate（8）用 raw zlib 解压。
  static Future<Uint8List?> _readEntryBytes(
    String archivePath,
    _ZipEntry entry,
  ) async {
    try {
      final raf = await File(archivePath).open();
      try {
        await raf.setPosition(entry.localHeaderOffset);
        final header = await raf.read(30);
        if (header.length != 30 || _u32(header, 0) != 0x04034b50) {
          return null;
        }
        final nameLen = _u16(header, 26);
        final extraLen = _u16(header, 28);
        final dataOffset =
            entry.localHeaderOffset + 30 + nameLen + extraLen;
        await raf.setPosition(dataOffset);
        final compressed = await raf.read(entry.compressedSize);
        if (compressed.length != entry.compressedSize) return null;
        if (entry.method == 0) {
          // stored：压缩即原文
          return compressed;
        }
        if (entry.method == 8) {
          // deflate：raw zlib 解压（zip 条目为无头部 deflate 流）
          final z = ZLibDecoder(raw: true);
          return Uint8List.fromList(z.convert(compressed));
        }
        return null;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// 回退：流式解码压缩包（不再 readAsBytes 整包入内存）。
  /// [InputFileStream] 为随机访问 + 缓冲的文件流，只读中央目录与所需条目数据；
  /// 条目内容惰性解压，峰值内存 = 单页大小而非整包大小。
  /// 同步文件 IO 会短暂占用调用线程（P1 将迁移到 worker isolate）。
  static _ArchiveHandle? _getArchive(String archivePath) {
    final cached = _archiveCache[archivePath];
    if (cached != null) {
      _archiveLru
        ..remove(archivePath)
        ..add(archivePath);
      return cached;
    }
    try {
      final stream = InputFileStream(archivePath, bufferSize: 1 << 20);
      final archive = ZipDecoder().decodeStream(stream);
      final handle = _ArchiveHandle(archive, stream);
      _archiveCache[archivePath] = handle;
      _archiveLru.add(archivePath);
      while (_archiveLru.length > _maxCachedArchives) {
        final evict = _archiveLru.removeAt(0);
        _archiveCache.remove(evict)?.stream.closeSync();
      }
      return handle;
    } catch (_) {
      return null;
    }
  }

  static void _cachePage(String id, Uint8List bytes) {
    final old = _pageBytes[id];
    if (old != null) _cachedPageBytes -= old.length;
    _pageBytes[id] = bytes;
    _cachedPageBytes += bytes.length;
    _pageLru
      ..remove(id)
      ..add(id);
    while (_pageLru.length > _maxCachedPages ||
        _cachedPageBytes > _maxCachedPageBytes) {
      if (_pageLru.isEmpty) break;
      final removed = _pageBytes.remove(_pageLru.removeAt(0));
      if (removed != null) _cachedPageBytes -= removed.length;
    }
  }

  /// 同步窥探已缓存的页字节（未缓存返回 null，用于避免已解压页的重复异步与闪烁）。
  static Uint8List? peekPageBytes(String id) => _pageBytes[id];

  /// 读取单页的图片字节：直接图从磁盘读取；压缩包内条目经中心目录
  /// 按偏移只读该条目并解压（带缓存）。失败返回 null。
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
      // 优先：中心目录索引按条目读取（整包不常驻内存，O(1) 查找）
      final index = await _getZipIndex(page.archivePath!);
      if (index != null) {
        final e = index.byName[page.entryName];
        if (e != null) {
          final bytes = await _readEntryBytes(page.archivePath!, e);
          if (bytes != null) {
            _cachePage(page.id, bytes);
            return bytes;
          }
        }
      }
      // 回退：流式解码后找条目（zip64 记录异常等解析失败场景，同样不整包入内存）
      final handle = _getArchive(page.archivePath!);
      if (handle != null) {
        for (final f in handle.archive.files) {
          if (f.isFile && f.name == page.entryName) {
            final content = f.content as List<int>;
            final bytes =
                content is Uint8List ? content : Uint8List.fromList(content);
            _cachePage(page.id, bytes);
            return bytes;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 清理全部静态缓存（关闭阅读器时调用，避免跨项目累积内存）。
  static void clearCache() {
    _pageBytes.clear();
    _pageLru.clear();
    _cachedPageBytes = 0;
    _indexCache.clear();
    _indexLru.clear();
    for (final h in _archiveCache.values) {
      h.stream.closeSync();
    }
    _archiveCache.clear();
    _archiveLru.clear();
  }

  static int _u16(List<int> b, int o) => b[o] | (b[o + 1] << 8);

  static int _u32(List<int> b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static int _u64(List<int> b, int o) =>
      b[o] |
      (b[o + 1] << 8) |
      (b[o + 2] << 16) |
      (b[o + 3] << 24) |
      (b[o + 4] << 32) |
      (b[o + 5] << 40) |
      (b[o + 6] << 48) |
      (b[o + 7] << 56);

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

  /// 直接以单个 zip/cbz 压缩包构建阅读列表（双击压缩包场景）。
  /// 只索引这一个包，避免递归扫描整个项目目录（大项目下会逐个读
  /// 无关包的中央目录，非常慢）。
  static Future<ComicPlaylist> buildFromArchive(String archivePath) async {
    final node = await _buildArchiveNode(archivePath);
    if (node == null) return ComicPlaylist(entries: [], tree: []);
    final entries = <ComicPage>[];
    _collect(node, entries);
    return ComicPlaylist(entries: entries, tree: [node]);
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
  /// 优先用中心目录索引（只读包尾，不加载整包）；解析失败回退流式解码。
  static Future<ComicFolderNode?> _buildArchiveNode(String archivePath) async {
    final index = await _getZipIndex(archivePath);
    if (index != null) {
      final node = ComicFolderNode(
        p.basename(archivePath),
        archivePath,
        isArchive: true,
      );
      for (final e in index.entries) {
        if (isImageFile(e.name)) {
          final normalized = e.name.replaceAll('\\', '/');
          node.files.add(ComicPage(
            id: '$archivePath::${e.name}',
            archivePath: archivePath,
            entryName: e.name,
            name: normalized.split('/').last,
            dirPath: archivePath,
            sizeInBytes: e.uncompressedSize,
          ));
        }
      }
      node.files.sort((a, b) => _naturalCompare(a.entryName!, b.entryName!));
      return node.files.isEmpty ? null : node;
    }
    try {
      final handle = _getArchive(archivePath);
      if (handle == null) return null;
      final archive = handle.archive;
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
      return node.files.isEmpty ? null : node;
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

/// zip/cbz 中心目录索引（仅条目元数据，不持有包内容）。
/// [byName] 提供条目名 O(1) 查找，避免大包（数万条目）翻页时的线性扫描。
class _ZipIndex {
  final List<_ZipEntry> entries;
  final Map<String, _ZipEntry> byName;
  _ZipIndex(this.entries) : byName = {for (final e in entries) e.name: e};
}

/// 流式解码句柄：Archive 的条目内容惰性引用 [stream]（随机访问文件流），
/// 因此流必须保持打开，直到缓存淘汰或 [ComicPlaylistService.clearCache]。
class _ArchiveHandle {
  final Archive archive;
  final InputFileStream stream;
  const _ArchiveHandle(this.archive, this.stream);
}

/// 中心目录中的单个文件条目。
class _ZipEntry {
  final String name;
  final int method; // 0=stored, 8=deflate
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
  const _ZipEntry({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });
}
