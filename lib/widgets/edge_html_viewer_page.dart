import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../services/edge_html_server.dart';
import '../services/translations.dart';
import 'compact_level.dart';

/// 内置网页浏览器：以本地 HTTP 服务同源打开 Edge 保存的网页，
/// 解决 file:// 直开时 CSS 被 CORS 拦截、`.js.下载` 脚本不执行的问题。
///
/// 顶栏提供 后退/前进/刷新、html 文件下拉切换、系统浏览器打开、关闭；
/// 同一 item 内有多个 html 时通过下拉框切换。
class EdgeHtmlViewerPage extends StatefulWidget {
  final String title; // 项目标题（显示在顶栏）
  final String rootPath; // 项目文件夹路径（HTTP 服务的根目录）
  final List<String> htmlFiles; // 项目内 html 文件的绝对路径（已排序）
  final int initialIndex; // 初始打开的 html 下标

  const EdgeHtmlViewerPage({
    super.key,
    required this.title,
    required this.rootPath,
    required this.htmlFiles,
    this.initialIndex = 0,
  });

  @override
  State<EdgeHtmlViewerPage> createState() => _EdgeHtmlViewerPageState();
}

class _EdgeHtmlViewerPageState extends State<EdgeHtmlViewerPage> {
  final WebviewController _controller = WebviewController();
  EdgeHtmlServer? _server;
  late int _index;
  bool _initialized = false;
  bool _loading = true;
  bool _initFailed = false;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _index = widget.htmlFiles.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.htmlFiles.length - 1);
    _init();
  }

  @override
  void dispose() {
    _controller.dispose();
    _server?.stop();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final server = await EdgeHtmlServer.start(widget.rootPath);
      if (!mounted) {
        server.stop();
        return;
      }
      _server = server;
      await _controller.initialize();
      await _controller.setDefaultContextMenusEnabled(true);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      _controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() => _loading = state == LoadingState.loading);
      });
      _controller.historyChanged.listen((h) {
        if (!mounted) return;
        setState(() {
          _canGoBack = h.canGoBack;
          _canGoForward = h.canGoForward;
        });
      });
      if (!mounted) return;
      setState(() => _initialized = true);
      if (widget.htmlFiles.isNotEmpty) {
        await _loadAt(_index);
      }
    } catch (_) {
      if (mounted) setState(() => _initFailed = true);
    }
  }

  String _baseName(String path) =>
      path.split(RegExp(r'[\\/]')).last;

  Future<void> _loadAt(int index) async {
    final name = _baseName(widget.htmlFiles[index]);
    await _controller.loadUrl(_server!.urlFor(name));
    if (mounted) setState(() => _index = index);
  }

  void _openInSystemBrowser() {
    if (widget.htmlFiles.isEmpty) return;
    Process.run('cmd', ['/c', 'start', '', widget.htmlFiles[_index]]);
  }

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          _buildToolbar(context, c, cs),
          if (_loading)
            LinearProgressIndicator(
              minHeight: 2,
              color: cs.primary,
              backgroundColor: Colors.transparent,
            ),
          Expanded(child: _buildBody(context, c, cs)),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, double c, ColorScheme cs) {
    return Container(
      height: 36 * c,
      padding: EdgeInsets.symmetric(horizontal: 8 * c),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          _toolbarIconButton(
            c: c,
            cs: cs,
            icon: Icons.close,
            tooltip: Strings.t('closePanel'),
            onTap: () => Navigator.of(context).pop(),
            color: Colors.red.shade400,
          ),
          SizedBox(width: 6 * c),
          _toolbarIconButton(
            c: c,
            cs: cs,
            icon: Icons.arrow_back,
            tooltip: Strings.t('browserBack'),
            enabled: _initialized && _canGoBack,
            onTap: () => _controller.goBack(),
          ),
          _toolbarIconButton(
            c: c,
            cs: cs,
            icon: Icons.arrow_forward,
            tooltip: Strings.t('browserForward'),
            enabled: _initialized && _canGoForward,
            onTap: () => _controller.goForward(),
          ),
          _toolbarIconButton(
            c: c,
            cs: cs,
            icon: Icons.refresh,
            tooltip: Strings.t('browserReload'),
            enabled: _initialized,
            onTap: () => _controller.reload(),
          ),
          SizedBox(width: 10 * c),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12 * c, color: cs.onSurface),
            ),
          ),
          if (widget.htmlFiles.length > 1)
            _buildHtmlDropdown(context, c, cs),
          SizedBox(width: 6 * c),
          _toolbarIconButton(
            c: c,
            cs: cs,
            icon: Icons.open_in_new,
            tooltip: Strings.t('openInSystemBrowser'),
            enabled: _initialized,
            onTap: _openInSystemBrowser,
          ),
        ],
      ),
    );
  }

  Widget _buildHtmlDropdown(BuildContext context, double c, ColorScheme cs) {
    return Container(
      constraints: BoxConstraints(maxWidth: 260 * c),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6 * c),
      ),
      padding: EdgeInsets.symmetric(horizontal: 6 * c),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _index,
          isDense: true,
          dropdownColor: cs.surfaceContainerHigh,
          style: TextStyle(fontSize: 11 * c, color: cs.onSurface),
          icon: Icon(Icons.expand_more, size: 16 * c, color: cs.onSurfaceVariant),
          items: [
            for (var i = 0; i < widget.htmlFiles.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(
                  _baseName(widget.htmlFiles[i]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _initialized
              ? (i) {
                  if (i != null && i != _index) _loadAt(i);
                }
              : null,
        ),
      ),
    );
  }

  Widget _toolbarIconButton({
    required double c,
    required ColorScheme cs,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool enabled = true,
    Color? color,
  }) {
    final iconColor = enabled
        ? (color ?? cs.onSurfaceVariant)
        : cs.onSurfaceVariant.withValues(alpha: 0.3);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(6 * c),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(6 * c),
          hoverColor: cs.onSurface.withValues(alpha: 0.08),
          child: Padding(
            padding: EdgeInsets.all(5 * c),
            child: Icon(icon, size: 15 * c, color: iconColor),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, double c, ColorScheme cs) {
    if (_initFailed) {
      return Center(
        child: Text(
          Strings.t('browserInitFailed'),
          style: TextStyle(fontSize: 12 * c, color: cs.onSurfaceVariant),
        ),
      );
    }
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.htmlFiles.isEmpty) {
      return Center(
        child: Text(
          Strings.t('noHtmlFiles'),
          style: TextStyle(fontSize: 12 * c, color: cs.onSurfaceVariant),
        ),
      );
    }
    return Webview(_controller);
  }
}
