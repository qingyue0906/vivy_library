import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path/path.dart' as p;
import '../models/ebook_book.dart';
import '../services/ebook_service.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import '../services/ebook_playlist_service.dart';
import 'smooth_scroll.dart';

/// 内置电子书阅读器。窗口/全屏骨架、顶栏拖拽+窗口控件、右侧可拖拽面板、点击分区
/// 翻页、键盘、右键退出 均复用漫画阅读器同一套交互；内容区按格式与阅读模式渲染。
/// 参考 Foliate / ReadEra 等主流开源阅读器：目录(TOC)、字号/行距/字体/主题/页边距
/// 设置、书内搜索、文本选择/复制。
class EbookReaderPage extends StatefulWidget {
  final EbookPlaylist playlist;
  final int initialIndex;
  final String title;

  const EbookReaderPage({
    super.key,
    required this.playlist,
    this.initialIndex = 0,
    required this.title,
  });

  @override
  State<EbookReaderPage> createState() => _EbookReaderPageState();
}

class _EbookReaderPageState extends State<EbookReaderPage>
    with WindowListener {
  late int _bookIndex;
  EbookBook? _book;
  bool _loadingBook = false;
  String? _loadError;

  late EbookReadMode _mode;
  late double _fontSize;
  late double _lineHeight;
  late String _fontFamily;
  late EbookTheme _theme;
  late double _pageMargin;
  late bool _justify;
  late bool _showToc;

  int _chapterIndex = 0;

  // txt 翻页模式
  List<String> _pages = [];
  int _pageIndex = 0;
  String _pageSig = '';
  int? _pendingCharOffset;

  // 搜索
  String _query = '';
  List<_SearchResult> _results = [];

  // 滚动模式章节定位
  final Map<int, GlobalKey> _chapterKeys = {};
  // 滚动模式性能优化：缓存已构建章节/页面的实际高度，用于跳转时估算偏移（避免一次性构建全部内容）
  final Map<int, double> _itemHeights = {};
  double _avgItemHeight = 600.0;
  final ScrollController _contentScrollController = ScrollController();
  final ScrollController _tocScrollController = ScrollController();
  final ScrollController _treeScrollController = ScrollController();

  // 右侧书籍文件夹树的展开状态（默认全部展开，与视频/漫画阅读器一致）。
  final Set<String> _expandedNodes = {};

  void _collectTreePaths(EbookFolderNode node) {
    _expandedNodes.add(node.path);
    for (final c in node.children) _collectTreePaths(c);
  }

  bool _isFullscreen = false;
  bool _isMaximized = false;
  bool _showTop = false;
  bool _showBottom = false;
  Timer? _hideTimer;

  double _tocWidth = SettingsService.loadEbookTocWidthSync();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _mode = SettingsService.loadEbookReadModeSync();
    _fontSize = SettingsService.loadEbookFontSizeSync();
    _lineHeight = SettingsService.loadEbookLineHeightSync();
    _fontFamily = SettingsService.loadEbookFontFamilySync();
    _theme = SettingsService.loadEbookThemeSync();
    _pageMargin = SettingsService.loadEbookPageMarginSync();
    _justify = SettingsService.loadEbookJustifySync();
    _showToc = SettingsService.loadEbookShowTocSync();
    _bookIndex = widget.initialIndex.clamp(
      0,
      widget.playlist.entries.isEmpty
          ? 0
          : widget.playlist.entries.length - 1,
    );
    _loadBook(_bookIndex);
    for (final root in widget.playlist.tree) {
      _collectTreePaths(root);
    }
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _isMaximized = v);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    windowManager.removeListener(this);
    if (_isFullscreen) windowManager.setFullScreen(false);
    final doc = _book?.pdfDoc;
    if (doc != null) {
      try {
        doc.dispose();
      } catch (_) {}
    }
    _contentScrollController.dispose();
    _tocScrollController.dispose();
    _treeScrollController.dispose();
    super.dispose();
  }

  // ===== 载入书 =====

  Future<void> _loadBook(int index) async {
    final prevDoc = _book?.pdfDoc;
    if (prevDoc != null) {
      try {
        await prevDoc.dispose();
      } catch (_) {}
    }
    setState(() {
      _loadingBook = true;
      _loadError = null;
      _book = null;
      _pages = [];
      _pageIndex = 0;
      _chapterIndex = 0;
      _pageSig = '';
      _query = '';
      _results = [];
      _chapterKeys.clear();
      _itemHeights.clear();
    });
    try {
      final book = await EbookService.loadBook(widget.playlist.entries[index]);
      if (!mounted) {
        try {
          await book.pdfDoc?.dispose();
        } catch (_) {}
        return;
      }
      setState(() {
        _book = book;
        _loadingBook = false;
      });
      if (book.format == 'txt') {
        // 翻页页数是在 build 中按可用尺寸计算的，这里仅触发重建。
        WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingBook = false;
          _loadError = e.toString();
        });
      }
    }
  }

  void _switchBook(int index) {
    if (index == _bookIndex) return;
    _bookIndex = index;
    _loadBook(index);
  }

  // ===== 阅读主题配色 =====

  Color get _bgColor {
    switch (_theme) {
      case EbookTheme.light:
        return const Color(0xFFFCFCFA);
      case EbookTheme.dark:
        return const Color(0xFF16181C);
      case EbookTheme.sepia:
        return const Color(0xFFF3E9D2);
    }
  }

  Color get _fgColor {
    switch (_theme) {
      case EbookTheme.light:
        return const Color(0xFF1A1A1A);
      case EbookTheme.dark:
        return const Color(0xFFD2D2D2);
      case EbookTheme.sepia:
        return const Color(0xFF5B4636);
    }
  }

  List<String>? get _fontFallback {
    switch (_fontFamily) {
      case 'serif':
        return ['Georgia', 'Times New Roman', 'serif'];
      case 'mono':
        return ['Consolas', 'Courier New', 'monospace'];
      default:
        return null;
    }
  }

  TextStyle _textStyle({double? size, Color? color, FontWeight? weight}) =>
      TextStyle(
        fontSize: size ?? _fontSize,
        height: _lineHeight,
        fontFamilyFallback: _fontFallback,
        color: color ?? _fgColor,
        fontWeight: weight,
      );

  Map<String, Style> _htmlStyle() => {
        'body': Style(
          fontSize: FontSize(_fontSize),
          color: _fgColor,
          margin: Margins.zero,
        ),
        'p': Style(margin: Margins.only(bottom: 8), lineHeight: LineHeight(_lineHeight)),
        'li': Style(lineHeight: LineHeight(_lineHeight)),
        'a': Style(color: Colors.blueAccent),
        'img': Style(margin: Margins.symmetric(vertical: 6)),
      };

  // ===== 翻页导航 =====

  void _goNext() {
    if (_book == null) return;
    final fmt = _book!.format;
    if (fmt == 'txt' && _mode == EbookReadMode.paginated) {
      if (_pages.isNotEmpty && _pageIndex < _pages.length - 1) {
        setState(() => _pageIndex++);
        return;
      }
      if (_chapterIndex < _book!.chapters.length - 1) {
        _jumpToChapter(_chapterIndex + 1, page: 0);
      }
      return;
    }
    if (_chapterIndex < _book!.chapters.length - 1) {
      _jumpToChapter(_chapterIndex + 1);
    }
  }

  void _goPrev() {
    if (_book == null) return;
    final fmt = _book!.format;
    if (fmt == 'txt' && _mode == EbookReadMode.paginated) {
      if (_pageIndex > 0) {
        setState(() => _pageIndex--);
        return;
      }
      if (_chapterIndex > 0) {
        _jumpToChapter(_chapterIndex - 1);
      }
      return;
    }
    if (_chapterIndex > 0) {
      _jumpToChapter(_chapterIndex - 1);
    }
  }

  void _jumpToChapter(int i, {int page = 0}) {
    if (_book == null) return;
    final clamped = i.clamp(0, _book!.chapters.length - 1);
    setState(() {
      _chapterIndex = clamped;
      _pageIndex = page;
    });
    if (_mode == EbookReadMode.scroll) {
      final controller = _contentScrollController;
      if (!controller.hasClients) return;
      final key = _chapterKeys[clamped];
      if (key?.currentContext != null) {
        // 目标项已构建：直接对齐
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 300),
          alignment: 0.0,
        );
        return;
      }
      // 懒加载列表：目标项尚未构建，先用（缓存高度估算的）偏移跳转，
      // 触发其构建后在下一帧精确对齐。避免一次性构建全部内容导致卡死。
      final offset = _estimateOffset(clamped);
      controller.jumpTo(offset.clamp(0, controller.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!controller.hasClients) return;
        final k = _chapterKeys[clamped];
        if (k?.currentContext != null) {
          final size = k!.currentContext!.size;
          if (size != null) _itemHeights[clamped] = size.height;
          Scrollable.ensureVisible(
            k.currentContext!,
            duration: const Duration(milliseconds: 200),
            alignment: 0.0,
          );
        }
      });
    }
  }

  /// 按章节索引估算其在滚动列表中的纵向偏移（未构建项用平均高度近似）。
  double _estimateOffset(int index) {
    double h = 0;
    for (var k = 0; k < index; k++) {
      h += _itemHeights[k] ?? _avgItemHeight;
    }
    h += index * 24.0; // 各项之间的垂直间距近似
    return h;
  }

  void _first() => _jumpToChapter(0);
  void _last() =>
      _jumpToChapter((_book?.chapters.length ?? 1) - 1);

  // ===== txt 分页（TextPainter 测量）=====

  List<String> _paginateText(String text, double maxW, double maxH) {
    if (text.isEmpty) return [''];
    final tp = TextPainter(
      text: TextSpan(text: text, style: _textStyle()),
      textDirection: TextDirection.ltr,
      textAlign: _justify ? TextAlign.justify : TextAlign.left,
    )..layout(maxWidth: maxW);
    final totalH = tp.height;
    if (totalH <= maxH) return [text];
    final pages = <String>[];
    var prev = 0;
    var y = maxH;
    while (prev < text.length && y <= totalH + maxH) {
      final pos = tp.getPositionForOffset(Offset(0, y)).offset;
      var end = pos <= prev ? prev + 1 : pos;
      if (end > text.length) end = text.length;
      pages.add(text.substring(prev, end));
      prev = end;
      y += maxH;
    }
    if (pages.isEmpty) pages.add(text);
    return pages;
  }

  TextSpan _buildHighlightedSpan(String text) {
    final q = _query.trim();
    if (q.isEmpty) return TextSpan(text: text, style: _textStyle());
    final lower = text.toLowerCase();
    final ql = q.toLowerCase();
    final children = <TextSpan>[];
    var start = 0;
    var idx = lower.indexOf(ql);
    if (idx < 0) return TextSpan(text: text, style: _textStyle());
    while (idx >= 0) {
      if (idx > start) {
        children.add(TextSpan(
          text: text.substring(start, idx),
          style: _textStyle(),
        ));
      }
      children.add(TextSpan(
        text: text.substring(idx, (idx + q.length).clamp(0, text.length)),
        style: _textStyle().copyWith(
          backgroundColor: Colors.yellow.withValues(alpha: 0.5),
        ),
      ));
      start = idx + q.length;
      idx = lower.indexOf(ql, start);
    }
    if (start < text.length) {
      children.add(TextSpan(text: text.substring(start), style: _textStyle()));
    }
    return TextSpan(children: children, style: _textStyle());
  }

  void _resolvePending() {
    if (_pendingCharOffset == null || _pages.isEmpty) return;
    var acc = 0;
    for (var i = 0; i < _pages.length; i++) {
      acc += _pages[i].length;
      if (acc > _pendingCharOffset!) {
        _pageIndex = i;
        break;
      }
    }
    _pendingCharOffset = null;
  }

  // ===== 搜索 =====

  void _runSearch(String q) {
    final query = q.trim();
    _query = query;
    _results = [];
    if (query.isEmpty || _book == null || _book!.format == 'pdf') {
      setState(() {});
      return;
    }
    final lower = query.toLowerCase();
    for (var i = 0; i < _book!.chapters.length; i++) {
      final t = _book!.chapters[i].text ?? '';
      if (t.isEmpty) continue;
      var idx = t.toLowerCase().indexOf(lower);
      while (idx >= 0) {
        final start = (idx - 20).clamp(0, t.length);
        final end = (idx + query.length + 20).clamp(0, t.length);
        _results.add(_SearchResult(
          chapterIndex: i,
          charOffset: idx,
          snippet: t.substring(start, end),
        ));
        idx = t.toLowerCase().indexOf(lower, idx + query.length);
      }
    }
    setState(() {});
  }

  void _gotoResult(_SearchResult r) {
    _jumpToChapter(r.chapterIndex);
    if (_book!.format == 'txt' && _mode == EbookReadMode.paginated) {
      _pendingCharOffset = r.charOffset;
    }
  }

  // ===== 窗口 / 全屏 =====

  Future<void> _toggleFullscreen() async {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        _showTop = false;
        _showBottom = false;
      }
    });
    await windowManager.setFullScreen(_isFullscreen);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullscreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullscreen = false);
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  void _onHover(PointerHoverEvent event) {
    if (!_isFullscreen) return;
    final h = MediaQuery.of(context).size.height;
    final dy = event.localPosition.dy;
    final topZone = dy < 90;
    final bottomZone = dy > h - 120;
    if (_showTop != topZone || _showBottom != bottomZone) {
      setState(() {
        _showTop = topZone;
        _showBottom = bottomZone;
      });
    }
    _hideTimer?.cancel();
    if (topZone || bottomZone) {
      _hideTimer = Timer(const Duration(seconds: 3), _hideAll);
    }
  }

  void _hideAll() {
    if (mounted) {
      setState(() {
        _showTop = false;
        _showBottom = false;
      });
    }
  }

  void _toggleUiOverlay() {
    if (!_isFullscreen) return;
    setState(() {
      _showTop = !_showTop;
      _showBottom = !_showBottom;
    });
    _hideTimer?.cancel();
    if (_showBottom || _showTop) {
      _hideTimer = Timer(const Duration(seconds: 3), _hideAll);
    }
  }

  void _close() {
    if (_isFullscreen) windowManager.setFullScreen(false);
    Navigator.of(context).pop();
  }

  // ===== 键盘 =====

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        if (_isFullscreen) {
          _toggleFullscreen();
        } else {
          _close();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _first();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _last();
        return KeyEventResult.handled;
    }
    if (_mode == EbookReadMode.scroll) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.space:
        _goNext();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.pageUp:
        _goPrev();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ===== pdf 页面图片 =====



  Widget _pdfImage(int pageNumber, double width) {
    final doc = _book!.pdfDoc as PdfDocument;
    // pdfrx 的 PdfPageView 按给定宽度渲染整页（自动处理 dpr 与内部位图缓存），
    // 外层 InteractiveViewer 提供缩放/平移；无需手动 render 字节。
    return InteractiveViewer(
      child: SizedBox(
        width: width,
        child: PdfPageView(
          document: doc,
          pageNumber: pageNumber,
        ),
      ),
    );
  }

  // ===== 构建 =====

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        backgroundColor: _bgColor,
        body: MouseRegion(
          onHover: _onHover,
          child: Row(
            children: [
              Expanded(child: _buildReaderArea(cs)),
              if (_showToc && !_isFullscreen) ...[
                _ResizeHandle(
                  onDrag: (dx) {
                    final next = (_tocWidth - dx).clamp(160.0, 420.0);
                    if (next != _tocWidth) setState(() => _tocWidth = next);
                  },
                  onDragEnd: () {
                    SettingsService.saveEbookShowToc(_showToc);
                    SettingsService.saveEbookTocWidth(_tocWidth);
                  },
                ),
                _buildTocPanel(cs),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReaderArea(ColorScheme cs) {
    if (_isFullscreen) {
      return Stack(
        children: [
          Positioned.fill(child: _buildContentArea(cs)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showTop ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showTop,
                child: _buildTopOverlay(cs),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showBottom ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showBottom,
                child: _buildControlBar(cs, overlay: true),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        _buildTopBar(cs),
        Expanded(child: _buildContentArea(cs)),
        _buildControlBar(cs),
      ],
    );
  }

  Widget _buildContentArea(ColorScheme cs) {
    if (_loadingBook) {
      return Container(
        color: _bgColor,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Container(
        color: _bgColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 40, color: Colors.red.shade400),
                const SizedBox(height: 12),
                Text(
                  _loadError!,
                  style: TextStyle(color: _fgColor, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _close, child: Text(Strings.t('closeReader'))),
              ],
            ),
          ),
        ),
      );
    }
    if (_book == null) return Container(color: _bgColor);
    late final Widget content;
    switch (_book!.format) {
      case 'txt':
        content = _mode == EbookReadMode.paginated
            ? _buildTxtPaginated(cs)
            : _buildTxtScroll(cs);
      case 'md':
      case 'epub':
        content = _mode == EbookReadMode.paginated
            ? _buildRichPaginated(cs)
            : _buildRichScroll(cs);
      case 'pdf':
        content = _mode == EbookReadMode.paginated
            ? _buildPdfPage(cs)
            : _buildPdfScroll(cs);
      default:
        return Container(color: _bgColor);
    }
    // 右键阅读区任意位置直接退出阅读器（与漫画/视频阅读器一致）；文字选中功能由内部 SelectionArea 保留。
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (_) => _close(),
      child: content,
    );
  }

  // ----- TXT 翻页 -----

  Widget _buildTxtPaginated(ColorScheme cs) {
    return LayoutBuilder(builder: (ctx, cons) {
      final w = cons.maxWidth - _pageMargin * 2;
      final h = cons.maxHeight - 24;
      final sig =
          '$_chapterIndex|$_fontSize|$_lineHeight|$_pageMargin|$_justify|$w|$h';
      if (sig != _pageSig) {
        _pageSig = sig;
        final text = _book!.chapters[_chapterIndex].text ?? '';
        _pages = _paginateText(text, w, h);
        if (_pageIndex >= _pages.length) _pageIndex = _pages.length - 1;
        if (_pageIndex < 0) _pageIndex = 0;
        if (_pendingCharOffset != null) _resolvePending();
        WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
      }
      final pageText = _pages.isEmpty
          ? ''
          : _pages[_pageIndex.clamp(0, _pages.length - 1)];
      final span = _buildHighlightedSpan(pageText);
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) {
          final dx = d.localPosition.dx;
          final vw = cons.maxWidth;
          if (dx < vw * 0.18) {
            _goPrev();
          } else if (dx > vw * 0.82) {
            _goNext();
          } else {
            _toggleUiOverlay();
          }
        },
        child: Container(
          color: _bgColor,
          padding: EdgeInsets.symmetric(horizontal: _pageMargin, vertical: 12),
          child: SelectableText.rich(
            span,
            textAlign: _justify ? TextAlign.justify : TextAlign.left,
          ),
        ),
      );
    });
  }

  // ----- TXT 滚动 -----

  Widget _buildTxtScroll(ColorScheme cs) {
    final chapters = _book!.chapters;
    return SelectionArea(
      child: Scrollbar(
        controller: _contentScrollController,
        child: SmoothScroll(
          controller: _contentScrollController,
          builder: (context, controller, physics) => ListView.builder(
            controller: controller,
            physics: physics,
            padding:
                EdgeInsets.symmetric(horizontal: _pageMargin, vertical: 16),
            itemCount: chapters.length,
            itemBuilder: (context, i) => _txtChapterBlock(i),
          ),
        ),
      ),
    );
  }

  Widget _txtChapterBlock(int i) {
    final ch = _book!.chapters[i];
    final key = _chapterKeys[i] ??= GlobalKey();
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ch.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 12),
            child: Text(
              ch.title,
              style: _textStyle(size: _fontSize + 4, weight: FontWeight.bold),
            ),
          ),
        SelectableText(
          ch.text ?? '',
          textAlign: _justify ? TextAlign.justify : TextAlign.left,
          style: _textStyle(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ----- MD / EPUB 翻页（整章滚动）-----

  Widget _buildRichPaginated(ColorScheme cs) {
    final ch = _book!.chapters[_chapterIndex];
    return LayoutBuilder(builder: (ctx, cons) {
      final vw = cons.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) {
          final dx = d.localPosition.dx;
          if (dx < vw * 0.18) {
            _goPrev();
          } else if (dx > vw * 0.82) {
            _goNext();
          } else {
            _toggleUiOverlay();
          }
        },
        child: Container(
          color: _bgColor,
          child: SelectionArea(
            child: Scrollbar(
              controller: _contentScrollController,
              child: SmoothScroll(
                controller: _contentScrollController,
                builder: (context, controller, physics) =>
                    SingleChildScrollView(
                  controller: controller,
                  physics: physics,
                  padding: EdgeInsets.symmetric(
                    horizontal: _pageMargin,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ch.title.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            ch.title,
                            style: _textStyle(
                              size: _fontSize + 4,
                              weight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Html(
                        data: ch.html ?? '',
                        style: _htmlStyle(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  // ----- MD / EPUB 滚动 -----

  Widget _buildRichScroll(ColorScheme cs) {
    final chapters = _book!.chapters;
    return SelectionArea(
      child: Scrollbar(
        controller: _contentScrollController,
        child: SmoothScroll(
          controller: _contentScrollController,
          builder: (context, controller, physics) => ListView.builder(
            controller: controller,
            physics: physics,
            padding:
                EdgeInsets.symmetric(horizontal: _pageMargin, vertical: 16),
            itemCount: chapters.length,
            itemBuilder: (context, i) => _richChapterBlock(i),
          ),
        ),
      ),
    );
  }

  Widget _richChapterBlock(int i) {
    final ch = _book!.chapters[i];
    final key = _chapterKeys[i] ??= GlobalKey();
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ch.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 12),
            child: Text(
              ch.title,
              style: _textStyle(size: _fontSize + 4, weight: FontWeight.bold),
            ),
          ),
        Html(
          data: ch.html ?? '',
          style: _htmlStyle(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ----- PDF 翻页 / 滚动 -----

  Widget _buildPdfPage(ColorScheme cs) {
    final pageNum = _book!.chapters[_chapterIndex].pdfPage!;
    return LayoutBuilder(builder: (ctx, cons) {
      final vw = cons.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) {
          final dx = d.localPosition.dx;
          if (dx < vw * 0.18) {
            _goPrev();
          } else if (dx > vw * 0.82) {
            _goNext();
          } else {
            _toggleUiOverlay();
          }
        },
        child: Container(
          color: _bgColor,
          child: Center(child: _pdfImage(pageNum, vw)),
        ),
      );
    });
  }

  Widget _buildPdfScroll(ColorScheme cs) {
    final chapters = _book!.chapters;
    return Scrollbar(
      controller: _contentScrollController,
      child: SmoothScroll(
        controller: _contentScrollController,
        builder: (context, controller, physics) => ListView.builder(
          controller: controller,
          physics: physics,
          padding: const EdgeInsets.all(8),
          itemCount: chapters.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(child: _pdfImage(chapters[i].pdfPage!, 600)),
          ),
        ),
      ),
    );
  }

  // ===== 顶栏 / 浮层 =====

  Widget _buildTopBar(ColorScheme cs) {
    final current = _book;
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Container(
                height: 32,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Icon(Icons.menu_book, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        current == null
                            ? widget.title
                            : '${widget.title}  ·  ${current.name}  ·  ${current.chapters[_chapterIndex].title}',
                        style: TextStyle(fontSize: 13, color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildWindowControls(cs, iconColor: cs.onSurface),
        ],
      ),
    );
  }

  Widget _buildTopOverlay(ColorScheme cs) {
    final current = _book;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              current == null
                  ? widget.title
                  : '${widget.title}  ·  ${current.name}  ·  ${current.chapters[_chapterIndex].title}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _buildWindowControls(cs, iconColor: Colors.white),
        ],
      ),
    );
  }

  Widget _buildWindowControls(ColorScheme cs, {required Color iconColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.horizontal_rule),
          color: iconColor,
          iconSize: 18,
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: Strings.t('minimize'),
          onPressed: () => windowManager.minimize(),
        ),
        IconButton(
          icon: Icon(_isMaximized ? Icons.crop_square : Icons.crop_16_9),
          color: iconColor,
          iconSize: 18,
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: Strings.t('maximize'),
          onPressed: _toggleMaximize,
        ),
        IconButton(
          icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
          color: iconColor,
          iconSize: 18,
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: _isFullscreen ? Strings.t('exitFullscreen') : Strings.t('fullscreen'),
          onPressed: _toggleFullscreen,
        ),
        IconButton(
          icon: const Icon(Icons.close),
          color: Colors.redAccent,
          iconSize: 18,
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: Strings.t('closeReader'),
          onPressed: _close,
        ),
      ],
    );
  }

  // ===== 底部控制条 =====

  Widget _buildControlBar(ColorScheme cs, {bool overlay = false}) {
    final Color iconColor = overlay ? Colors.white : cs.onSurface;
    return Container(
      decoration: BoxDecoration(
        color: overlay ? Colors.black.withValues(alpha: 0.82) : cs.surface,
        border: overlay
            ? null
            : Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            iconSize: 20,
            minimumSize: const Size(32, 32),
            padding: const EdgeInsets.all(4),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.first_page),
              color: iconColor,
              tooltip: Strings.t('home'),
              onPressed: _first,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              color: iconColor,
              tooltip: Strings.t('prevChapter'),
              onPressed: _goPrev,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              color: iconColor,
              tooltip: Strings.t('nextChapter'),
              onPressed: _goNext,
            ),
            IconButton(
              icon: const Icon(Icons.last_page),
              color: iconColor,
              tooltip: Strings.t('end'),
              onPressed: _last,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _positionLabel(),
                style: TextStyle(color: iconColor, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _modeButton(iconColor),
            IconButton(
              icon: const Icon(Icons.text_format),
              color: iconColor,
              tooltip: Strings.t('fontSettings'),
              onPressed: _showSettingsDialog,
            ),
            IconButton(
              icon: Icon(_showToc ? Icons.view_sidebar : Icons.view_sidebar_outlined),
              color: iconColor,
              tooltip: Strings.t('toc'),
              onPressed: () {
                setState(() => _showToc = !_showToc);
                SettingsService.saveEbookShowToc(_showToc);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _positionLabel() {
    final total = _book?.chapters.length ?? 0;
    if (_book?.format == 'txt' && _mode == EbookReadMode.paginated) {
      final pagePart = _pages.isEmpty ? '' : '  ·  ${_pageIndex + 1}/${_pages.length}';
      return '${Strings.tn('chapterXOfY', {'cur': '${_chapterIndex + 1}', 'total': '$total'})}$pagePart';
    }
    if (_book?.format == 'pdf') {
      return Strings.tn('pageXOfY', {'cur': '${_chapterIndex + 1}', 'total': '$total'});
    }
    return Strings.tn('chapterXOfY', {'cur': '${_chapterIndex + 1}', 'total': '$total'});
  }

  Widget _modeButton(Color iconColor) {
    final icon = _mode == EbookReadMode.paginated
        ? Icons.view_agenda
        : Icons.article;
    return PopupMenuButton<EbookReadMode>(
      tooltip: Strings.t('readingMode'),
      icon: Icon(icon, color: iconColor),
      initialValue: _mode,
      onSelected: (m) {
        setState(() {
          _mode = m;
          _pageSig = '';
          _pages = [];
          _pageIndex = 0;
        });
        SettingsService.saveEbookReadMode(m);
      },
      itemBuilder: (ctx) => [
        _modeItem(EbookReadMode.paginated, Icons.view_agenda, Strings.t('modePaginated')),
        _modeItem(EbookReadMode.scroll, Icons.article, Strings.t('modeScroll')),
      ],
    );
  }

  PopupMenuItem<EbookReadMode> _modeItem(
    EbookReadMode m,
    IconData icon,
    String label,
  ) =>
      PopupMenuItem<EbookReadMode>(
        value: m,
        child: Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Text(label),
            if (m == _mode) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check, size: 14),
            ],
          ],
        ),
      );

  // ===== 设置对话框 =====

  Future<void> _showSettingsDialog() async {
    final cs = Theme.of(context).colorScheme;
    double fontSize = _fontSize;
    double lineHeight = _lineHeight;
    double margin = _pageMargin;
    bool justify = _justify;
    String fontFamily = _fontFamily;
    EbookTheme theme = _theme;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              title: Text(Strings.t('fontSettings')),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(Strings.t('theme'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      SegmentedButton<EbookTheme>(
                        segments: [
                          ButtonSegment(value: EbookTheme.light, label: Text(Strings.t('themeLight'))),
                          ButtonSegment(value: EbookTheme.dark, label: Text(Strings.t('themeDark'))),
                          ButtonSegment(value: EbookTheme.sepia, label: Text(Strings.t('themeSepia'))),
                        ],
                        selected: {theme},
                        onSelectionChanged: (s) => setD(() => theme = s.first),
                      ),
                      const SizedBox(height: 12),
                      Text(Strings.t('fontFamily'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'system', label: Text('系统')),
                          ButtonSegment(value: 'serif', label: Text('衬线')),
                          ButtonSegment(value: 'mono', label: Text('等宽')),
                        ],
                        selected: {fontFamily},
                        onSelectionChanged: (s) => setD(() => fontFamily = s.first),
                      ),
                      const SizedBox(height: 16),
                      _sliderRow(Strings.t('fontSize'), fontSize, 10, 40, (v) => setD(() => fontSize = v), cs),
                      _sliderRow(Strings.t('lineHeight'), lineHeight, 1.0, 3.0, (v) => setD(() => lineHeight = v), cs),
                      _sliderRow(Strings.t('pageMargin'), margin, 0, 80, (v) => setD(() => margin = v), cs),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(Strings.t('justifyText')),
                        value: justify,
                        onChanged: (v) => setD(() => justify = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(Strings.t('cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _fontSize = fontSize;
                      _lineHeight = lineHeight;
                      _pageMargin = margin;
                      _justify = justify;
                      _fontFamily = fontFamily;
                      _theme = theme;
                      _pageSig = '';
                      _pages = [];
                      _pageIndex = 0;
                    });
                    SettingsService.saveEbookFontSize(fontSize);
                    SettingsService.saveEbookLineHeight(lineHeight);
                    SettingsService.saveEbookPageMargin(margin);
                    SettingsService.saveEbookJustify(justify);
                    SettingsService.saveEbookFontFamily(fontFamily);
                    SettingsService.saveEbookTheme(theme);
                    Navigator.pop(dialogContext);
                  },
                  child: Text(Strings.t('ok')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    ColorScheme cs,
  ) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) * 2).round(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(value.toStringAsFixed(1), textAlign: TextAlign.right),
        ),
      ],
    );
  }

  // ===== 目录 / 书切换 / 搜索 面板 =====

  Widget _buildTocPanel(ColorScheme cs) {
    final book = _book;
    return Container(
      width: _tocWidth,
      color: cs.surfaceContainerHigh,
      child: Column(
        children: [
          // 书籍文件夹树（始终显示，与视频/漫画阅读器对称；不依赖当前书是否载入完成）
          _panelHeader(
            cs,
            Icons.folder_open,
            Strings.t('bookList'),
            '${widget.playlist.entries.length}',
          ),
          Expanded(flex: 1, child: _bookTree(cs)),
          Divider(height: 1, color: cs.outlineVariant),
          // 当前书的目录(TOC)
          _panelHeader(
            cs,
            Icons.menu_book,
            Strings.t('toc'),
            book == null ? '' : '${book.chapters.length}',
          ),
          if (book != null && book.format != 'pdf')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: TextField(
                onChanged: _runSearch,
                decoration: InputDecoration(
                  hintText: Strings.t('searchHint'),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
            ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            flex: 2,
            child: book == null
                ? const SizedBox.shrink()
                : (book.format == 'pdf' || _query.isEmpty)
                    ? _chapterList(cs)
                    : _resultList(cs),
          ),
        ],
      ),
    );
  }

  /// 右侧面板的区块标题（图标 + 文案 + 计数）。
  Widget _panelHeader(
    ColorScheme cs,
    IconData icon,
    String title,
    String count,
  ) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(fontSize: 13, color: cs.onSurface),
          ),
          const Spacer(),
          Text(
            count,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 渲染项目内书籍的文件夹树（多书时）。点击文件叶切换到该书。
  Widget _bookTree(ColorScheme cs) {
    final tree = widget.playlist.tree;
    if (tree.isEmpty) return const SizedBox.shrink();
    return Scrollbar(
      controller: _treeScrollController,
      thumbVisibility: true,
      child: SmoothScroll(
        controller: _treeScrollController,
        builder: (context, controller, physics) => ListView(
          controller: controller,
          physics: physics,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            for (final r in tree) _treeNode(r, cs, 0),
          ],
        ),
      ),
    );
  }

  /// 递归渲染文件夹树节点（含展开/收起）。
  Widget _treeNode(EbookFolderNode node, ColorScheme cs, int depth) {
    final hasKids = node.children.isNotEmpty || node.files.isNotEmpty;
    final expanded = _expandedNodes.contains(node.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasKids
              ? () => setState(() {
                    if (expanded) {
                      _expandedNodes.remove(node.path);
                    } else {
                      _expandedNodes.add(node.path);
                    }
                  })
              : null,
          child: Container(
            padding: EdgeInsets.only(
              left: 8.0 + depth * 14,
              right: 8,
              top: 4,
              bottom: 4,
            ),
            child: Row(
              children: [
                if (hasKids)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 4),
                Icon(
                  expanded ? Icons.folder_open : Icons.folder,
                  size: 16,
                  color: expanded ? cs.primary : Colors.amber.shade400,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(fontSize: 12, color: cs.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasKids && expanded)
          ...[
            for (final c in node.children) _treeNode(c, cs, depth + 1),
            for (final f in node.files) _fileLeaf(f, cs, depth + 1),
          ],
      ],
    );
  }

  /// 树中的电子书文件叶（点击切换到该书；当前书高亮）。
  Widget _fileLeaf(EbookFileEntry f, ColorScheme cs, int depth) {
    final idx = widget.playlist.entries.indexOf(f.path);
    final isCurrent = idx >= 0 && idx == _bookIndex;
    return InkWell(
      onTap: idx >= 0 ? () => _switchBook(idx) : null,
      child: Container(
        decoration: isCurrent
            ? BoxDecoration(
                border: Border(left: BorderSide(color: cs.primary, width: 3)),
                color: cs.primary.withValues(alpha: 0.16),
              )
            : null,
        padding: EdgeInsets.only(
          left: 8.0 + depth * 14 + 14,
          right: 8,
          top: 6,
          bottom: 6,
        ),
        child: Row(
          children: [
            Icon(
              _formatIcon(f.path),
              size: 14,
              color: isCurrent ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                f.name,
                style: TextStyle(
                  fontSize: 12,
                  color: isCurrent ? cs.primary : cs.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _formatIcon(String path) {
    final ext = p.extension(path).toLowerCase().replaceAll('.', '');
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'epub':
        return Icons.auto_stories;
      case 'md':
        return Icons.article;
      default:
        return Icons.description;
    }
  }

  Widget _chapterList(ColorScheme cs) {
    final book = _book!;
    return Scrollbar(
      controller: _tocScrollController,
      thumbVisibility: true,
      child: SmoothScroll(
        controller: _tocScrollController,
        builder: (context, controller, physics) => ListView.builder(
          controller: controller,
          physics: physics,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: book.chapters.length,
          itemBuilder: (context, i) {
            final isCurrent = i == _chapterIndex;
            return InkWell(
              onTap: () => _jumpToChapter(i),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: isCurrent
                    ? BoxDecoration(
                        border: Border(
                          left: BorderSide(color: cs.primary, width: 3),
                        ),
                        color: cs.primary.withValues(alpha: 0.16),
                      )
                    : null,
                child: Text(
                  book.chapters[i].title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isCurrent ? cs.primary : cs.onSurface,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _resultList(ColorScheme cs) {
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            Strings.t('noSearchResults'),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ),
      );
    }
    return Scrollbar(
      controller: _tocScrollController,
      thumbVisibility: true,
      child: SmoothScroll(
        controller: _tocScrollController,
        builder: (context, controller, physics) => ListView.builder(
          controller: controller,
          physics: physics,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: _results.length,
          itemBuilder: (context, i) {
            final r = _results[i];
            return InkWell(
              onTap: () => _gotoResult(r),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _book!.chapters[r.chapterIndex].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SearchResult {
  final int chapterIndex;
  final int charOffset;
  final String snippet;
  _SearchResult({
    required this.chapterIndex,
    required this.charOffset,
    required this.snippet,
  });
}

/// 阅读区与目录面板之间的可拖拽分隔条。
class _ResizeHandle extends StatelessWidget {
  final void Function(double dx) onDrag;
  final VoidCallback? onDragEnd;

  const _ResizeHandle({required this.onDrag, this.onDragEnd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: (d) => onDrag(d.delta.dx),
      onPanEnd: (_) => onDragEnd?.call(),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: SizedBox(
          width: 5,
          child: Center(child: Container(width: 1, color: cs.outlineVariant)),
        ),
      ),
    );
  }
}
