import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdfx/pdfx.dart';
import 'package:path/path.dart' as p;
import '../models/ebook_book.dart';
import '../models/library_item.dart';

/// 电子书解析服务：将 txt / epub / pdf / md 文件解析为 [EbookBook]（含章节/TOC）。
/// 解析结果交给阅读器页面渲染；epub 的内嵌图片由页面侧通过 [EbookBook.archive] 解析。
class EbookService {
  static const bookExts = {'txt', 'epub', 'pdf', 'md'};

  static String _ext(String path) =>
      p.extension(path).toLowerCase().replaceAll('.', '');

  /// 是否为阅读器可打开的电子书文件。
  static bool isReadableFile(String path) => bookExts.contains(_ext(path));

  /// 递归扫描项目内全部电子书文件，按自然排序返回路径列表。
  static Future<List<String>> scanBookPaths(String root) async {
    final out = <String>[];
    final dir = Directory(root);
    if (!dir.existsSync()) return out;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && isReadableFile(entity.path)) {
        out.add(entity.path);
      }
    }
    out.sort((a, b) => _naturalCompare(p.basename(a), p.basename(b)));
    return out;
  }

  /// 载入一本书（按扩展名分派）。
  static Future<EbookBook> loadBook(String path) async {
    final ext = _ext(path);
    final name = p.basename(path);
    switch (ext) {
      case 'txt':
        return _loadTxt(path, name);
      case 'md':
        return _loadMd(path, name);
      case 'epub':
        return _loadEpub(path, name);
      case 'pdf':
        return _loadPdf(path, name);
      default:
        throw Exception('unsupported ebook format: $ext');
    }
  }

  // ===== TXT =====

  static Future<EbookBook> _loadTxt(String path, String name) async {
    final bytes = await File(path).readAsBytes();
    final text = _decode(bytes);
    final chapters = _splitTxt(text, name);
    return EbookBook(path: path, name: name, format: 'txt', chapters: chapters);
  }

  static List<EbookChapter> _splitTxt(String text, String name) {
    final headingRe = RegExp(
      r'^\s*(第\s*[0-9零一二三四五六七八九十百千万两]+\s*[章卷回部集]'
      r'|Chapter\s+\d+'
      r'|卷\s*[一二三四五六七八九十]+\s*'
      r'|#+\s+.+)',
      caseSensitive: false,
    );
    final chapters = <EbookChapter>[];
    var currentTitle = name;
    final buf = <String>[];
    void flush() {
      final content = buf.join('\n').trim();
      buf.clear();
      if (content.isNotEmpty) {
        chapters.add(EbookChapter(title: currentTitle, text: content));
      }
    }

    for (final line in text.split('\n')) {
      if (headingRe.hasMatch(line)) {
        flush();
        currentTitle = line.trim();
      }
      buf.add(line);
    }
    flush();
    if (chapters.isEmpty) {
      chapters.add(EbookChapter(title: name, text: text.trim()));
    }
    return chapters;
  }

  // ===== Markdown =====

  static Future<EbookBook> _loadMd(String path, String name) async {
    final bytes = await File(path).readAsBytes();
    final text = _decode(bytes);
    final chunks = _splitMd(text);
    final mdDir = p.dirname(path);
    final chapters = chunks
        .map((c) {
          final body = c.body;
          final raw = md.markdownToHtml(body);
          final inlined = _inlineImages(raw, mdDir: mdDir);
          return EbookChapter(
            title: c.title,
            html: inlined,
            text: _stripTags(inlined),
          );
        })
        .toList();
    return EbookBook(path: path, name: name, format: 'md', chapters: chapters);
  }

  static List<_MdChunk> _splitMd(String text) {
    final lines = text.split('\n');
    final chunks = <_MdChunk>[];
    var title = 'Markdown';
    final buf = <String>[];
    for (final line in lines) {
      if (RegExp(r'^#{1,6}\s+').hasMatch(line)) {
        if (buf.isNotEmpty) {
          chunks.add(_MdChunk(title, buf.join('\n')));
          buf.clear();
        }
        title = line.trim().replaceFirst(RegExp(r'^#{1,6}\s+'), '');
      }
      buf.add(line);
    }
    if (buf.isNotEmpty) chunks.add(_MdChunk(title, buf.join('\n')));
    if (chunks.isEmpty) chunks.add(_MdChunk('Markdown', text));
    return chunks;
  }

  // ===== EPUB =====

  static Future<EbookBook> _loadEpub(String path, String name) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final container = archive.findFile('META-INF/container.xml');
    if (container == null) throw Exception('invalid epub: no container.xml');
    final containerXml =
        XmlDocument.parse(_utf8(container.content as List<int>));
    final rootPath = containerXml
        .findAllElements('rootfile')
        .firstOrNull
        ?.getAttribute('full-path');
    if (rootPath == null || rootPath.isEmpty) {
      throw Exception('invalid epub: no rootfile');
    }
    final opfEntry = archive.findFile(rootPath);
    if (opfEntry == null) throw Exception('invalid epub: no opf');
    final opfXml = XmlDocument.parse(_utf8(opfEntry.content as List<int>));
    final opfDir = rootPath.contains('/')
        ? rootPath.substring(0, rootPath.lastIndexOf('/'))
        : '';

    final manifest = <String, _ManifestItem>{};
    for (final el in opfXml.findAllElements('item')) {
      final id = el.getAttribute('id');
      final href = el.getAttribute('href');
      final mt = el.getAttribute('media-type') ?? '';
      if (id != null && href != null) manifest[id] = _ManifestItem(href, mt);
    }

    final spine = opfXml
        .findAllElements('itemref')
        .map((e) => e.getAttribute('idref'))
        .whereType<String>()
        .toList();

    final chapters = <EbookChapter>[];
    for (final idref in spine) {
      final item = manifest[idref];
      if (item == null) continue;
      final full = resolveArchivePath(opfDir, item.href);
      final entry = archive.findFile(full);
      if (entry == null) continue;
      final doc = _utf8(entry.content as List<int>);
      final body = _extractBody(doc);
      final title = _firstHeading(doc) ?? p.basename(item.href);
      final inlined = _inlineImages(body,
          archive: archive, baseDir: p.dirname(full));
      chapters.add(EbookChapter(
        title: title,
        html: inlined,
        text: _stripTags(inlined),
        baseDir: p.dirname(full),
      ));
    }
    if (chapters.isEmpty) throw Exception('invalid epub: no content');
    return EbookBook(
      path: path,
      name: name,
      format: 'epub',
      chapters: chapters,
      archive: archive,
      opfDir: opfDir,
    );
  }

  // ===== PDF =====

  static Future<EbookBook> _loadPdf(String path, String name) async {
    final doc = await PdfDocument.openFile(path);
    final chapters = <EbookChapter>[];
    for (var i = 1; i <= doc.pagesCount; i++) {
      chapters.add(EbookChapter(title: 'Page $i', pdfPage: i));
    }
    return EbookBook(
      path: path,
      name: name,
      format: 'pdf',
      chapters: chapters,
      pdfDoc: doc,
    );
  }

  // ===== 工具 =====

  static String _decode(Uint8List bytes) {
    try {
      final s = utf8.decode(bytes, allowMalformed: true);
      // 若多数为替换字符，则退回到按字节解释（兼容本地编码）。
      if (s.contains('�') && s.codeUnits.where((c) => c == 0xFFFD).length > s.length ~/ 20) {
        return String.fromCharCodes(bytes);
      }
      return s;
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }

  static String _utf8(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true);

  /// 提取 <body> 内部，去掉 <head> 中的样式/脚本，交给 flutter_html 渲染。
  static String _extractBody(String doc) {
    final m = RegExp(r'<body[^>]*>([\s\S]*)</body>', caseSensitive: false)
        .firstMatch(doc);
    return m?.group(1)?.trim() ?? doc.trim();
  }

  static String? _firstHeading(String doc) {
    final m = RegExp(r'<h[1-3][^>]*>([\s\S]*?)</h[1-3]>',
            caseSensitive: false)
        .firstMatch(doc);
    if (m == null) return null;
    return _stripTags(m.group(1)!).trim();
  }

  /// 去除 HTML 标签并解码常见实体，得到可用于搜索的纯文本。
  /// 将 HTML 中的本地图片内联为 base64 data URI，使 flutter_html 无需自定义
  /// 图片加载器即可渲染 epub 压缩包内 / md 同目录的图片。
  static final _imgRegex = RegExp(
    r'''<img\b[^>]*?src\s*=\s*["']([^"'>]+)["'][^>]*?>''',
    caseSensitive: false,
  );

  static String _inlineImages(
    String html, {
    Archive? archive,
    String baseDir = '',
    String? mdDir,
  }) {
    return html.replaceAllMapped(_imgRegex, (m) {
      final tag = m.group(0)!;
      final src = m.group(1)!;
      if (src.startsWith('data:') ||
          src.startsWith('http://') ||
          src.startsWith('https://') ||
          src.startsWith('//')) {
        return tag;
      }
      List<int>? bytes;
      if (archive != null) {
        final entry = archive.findFile(resolveArchivePath(baseDir, src));
        if (entry != null) bytes = entry.content as List<int>;
      } else if (mdDir != null) {
        final file = File(p.join(mdDir, src));
        if (file.existsSync()) {
          try {
            bytes = file.readAsBytesSync();
          } catch (_) {}
        }
      }
      if (bytes == null) return tag;
      final dataUri = 'data:${_mimeOf(src)};base64,${base64Encode(bytes)}';
      return tag.replaceFirst(
        RegExp(r'''src\s*=\s*["'][^"'>]*["']'''),
        'src="$dataUri"',
      );
    });
  }

  static String _mimeOf(String src) {
    final e = src.toLowerCase().split('?').first.split('.').last;
    switch (e) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      default:
        return 'image/png';
    }
  }

  static String _stripTags(String html) {
    var s = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = s.replaceAll('&nbsp;', ' ');
    s = s.replaceAll('&amp;', '&');
    s = s.replaceAll('&lt;', '<');
    s = s.replaceAll('&gt;', '>');
    s = s.replaceAll('&quot;', '"');
    s = s.replaceAllMapped(
        RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// 以 '/' 为分隔符在压缩包内做相对路径解析（处理 . 与 ..）。
  static String resolveArchivePath(String base, String rel) {
    final baseDir = base.isEmpty ? '' : '$base/';
    final parts = (baseDir + rel).split('/');
    final out = <String>[];
    for (final part in parts) {
      if (part == '' || part == '.') continue;
      if (part == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else {
        out.add(part);
      }
    }
    return out.join('/');
  }

  /// 自然排序：连续数字段按数值比较，使 1,2,10 而非 1,10,2。大小写不敏感。
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
        var ja = ia;
        while (ja < sa.length && sa.codeUnitAt(ja) >= 0x30 && sa.codeUnitAt(ja) <= 0x39) {
          ja++;
        }
        var jb = ib;
        while (jb < sb.length && sb.codeUnitAt(jb) >= 0x30 && sb.codeUnitAt(jb) <= 0x39) {
          jb++;
        }
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

class _ManifestItem {
  final String href;
  final String mediaType;
  _ManifestItem(this.href, this.mediaType);
}

class _MdChunk {
  final String title;
  final String body;
  _MdChunk(this.title, this.body);
}
