import 'package:archive/archive.dart';

/// 一本书的解析结果。阅读器一次载入一本书。
///
/// 不同格式的差异：
/// - txt：章节由 [text] 承载（纯文本）。
/// - md / epub：章节由 [html] 承载（富文本，交给 flutter_html 渲染）。
/// - pdf：每个 [EbookChapter] 对应一页，[pdfPage] 为 1 基页码，[html]/[text] 为空。
class EbookBook {
  final String path;
  final String name;
  final String format; // 'txt' | 'epub' | 'pdf' | 'md'
  final List<EbookChapter> chapters;

  /// epub 专用：解包后的压缩包，供 flutter_html 的自定义图片解析器按 entry 名读取内嵌图片。
  final Archive? archive;

  /// epub 专用：OPF 所在目录（相对压缩包根），用于解析图片相对路径。
  final String? opfDir;

  /// pdf 专用：已打开的 PdfDocument（惰性渲染页面图片）。
  final dynamic pdfDoc;

  EbookBook({
    required this.path,
    required this.name,
    required this.format,
    required this.chapters,
    this.archive,
    this.opfDir,
    this.pdfDoc,
  });
}

/// 文件夹树中的单个电子书文件叶（点击即可切换到该书）。
class EbookFileEntry {
  final String path;
  final String name;

  EbookFileEntry({required this.path, required this.name});
}

/// 文件夹树节点：children 为子文件夹，files 为该文件夹下的电子书文件。
/// 与 [VideoFolderNode] 完全对称，用于右侧面板渲染项目内的书籍树。
class EbookFolderNode {
  final String name;
  final String path; // 该文件夹的绝对路径（用于展开状态与归属判断）
  final List<EbookFolderNode> children = [];
  final List<EbookFileEntry> files = [];

  EbookFolderNode(this.name, this.path);
}

class EbookChapter {
  final String title;

  /// 纯文本（txt 或 md/epub 去标签后的正文，用于搜索与 txt 翻页渲染）。
  final String? text;

  /// 富文本 HTML（md 由 markdown 转换、epub 取 xhtml body 内部）。
  final String? html;

  /// epub 章节 xhtml 所在目录（相对压缩包根），用于解析内嵌图片。
  final String? baseDir;

  /// pdf 页码（1 基），非 pdf 为 null。
  final int? pdfPage;

  EbookChapter({
    required this.title,
    this.text,
    this.html,
    this.baseDir,
    this.pdfPage,
  });
}
