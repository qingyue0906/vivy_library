import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
import 'package:window_manager/window_manager.dart';

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

class _EdgeHtmlViewerPageState extends State<EdgeHtmlViewerPage>
    with WindowListener {
  final WebviewController _controller = WebviewController();
  EdgeHtmlServer? _server;
  late int _index;
  bool _initialized = false;
  bool _loading = true;
  bool _initFailed = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isMaximized = false;

  /// 网页内容区长按右键（超过该时长）快捷退出页面。
  /// 短按右键保留给浏览器原生右键菜单，不做拦截。
  static const Duration _exitLongPressDelay = Duration(milliseconds: 500);
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _isMaximized = v);
    });
    _index = widget.htmlFiles.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.htmlFiles.length - 1);
    _init();
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    windowManager.removeListener(this);
    _controller.dispose();
    _server?.stop();
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  /// 网页内容区右键按下时启动长按计时；短按右键不拦截，
  /// 保持 WebView2 原生右键菜单可用。
  void _onWebPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    if (event.buttons != kSecondaryMouseButton) return;
    _exitTimer?.cancel();
    _exitTimer = Timer(_exitLongPressDelay, () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _cancelExitTimer() {
    _exitTimer?.cancel();
    _exitTimer = null;
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
    final path = widget.htmlFiles[index];
    final lower = path.toLowerCase();
    // mhtml 为单文件自包含格式，file:// 直开即可由 WebView2 原生渲染
    // （与 Edge 双击打开同一机制，资源全部内嵌，无需 HTTP 服务）；
    // html 系列仍走本地同源服务以规避 CORS 与 MIME 问题；
    // markdown 由服务端转 HTML，附主题参数以跟随应用浅色/暗色主题。
    final isMhtml = lower.endsWith('.mhtml') || lower.endsWith('.mht');
    final isMd = lower.endsWith('.md') || lower.endsWith('.markdown');
    final theme = Theme.of(context).brightness == Brightness.dark
        ? 'dark'
        : 'light';
    final url = isMhtml
        ? Uri.file(path).toString()
        : _server!.urlFor(
            _baseName(path),
            theme: isMd ? theme : null,
          );
    await _controller.loadUrl(url);
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
          Expanded(
            child: Listener(
              onPointerDown: _onWebPointerDown,
              onPointerUp: (_) => _cancelExitTimer(),
              onPointerCancel: (_) => _cancelExitTimer(),
              child: _buildBody(context, c, cs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, double c, ColorScheme cs) {
    return Container(
      height: 36 * c,
      // 仅左侧留内边距，让最小化/最大化/关闭贴到最右边缘（窗口控制惯例）
      padding: EdgeInsets.only(left: 8 * c),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      // 两层结构（与主界面标题栏一致）：底层全幅拖拽层负责空白处的
      // 拖动与双击最大化；上层透明交互层中按钮/下拉框吸收事件，不进
      // 拖拽竞技场，避免 DragToMoveArea 自带 onDoubleTap 的 300ms
      // 竞技场持有导致点击延迟。
      child: Stack(
        children: [
          Positioned.fill(
            child: DragToMoveArea(
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: Row(
              children: [
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
                // 标题 Text 会吸收指针事件，需显式包 DragToMoveArea
                // 才能从标题处拖动窗口/双击最大化
                Expanded(
                  child: DragToMoveArea(
                    child: Container(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12 * c, color: cs.onSurface),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10 * c),
                _toolbarIconButton(
                  c: c,
                  cs: cs,
                  icon: Icons.horizontal_rule,
                  tooltip: Strings.t('minimize'),
                  padding: 8,
                  iconSize: 16,
                  onTap: () => windowManager.minimize(),
                ),
                SizedBox(width: 4 * c),
                _toolbarIconButton(
                  c: c,
                  cs: cs,
                  icon: _isMaximized ? Icons.crop_square : Icons.crop_16_9,
                  tooltip: Strings.t('maximize'),
                  padding: 8,
                  iconSize: 16,
                  onTap: _toggleMaximize,
                ),
                SizedBox(width: 4 * c),
                _toolbarIconButton(
                  c: c,
                  cs: cs,
                  icon: Icons.close,
                  tooltip: Strings.t('closePanel'),
                  padding: 8,
                  iconSize: 16,
                  onTap: () => Navigator.of(context).pop(),
                  color: Colors.red.shade400,
                ),
                if (widget.htmlFiles.length > 1) ...[
                  SizedBox(width: 6 * c),
                  _buildHtmlDropdown(context, c, cs),
                ],
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
          // 有界宽度内省略长文件名，避免按钮内部 Row 溢出（像素警告）
          isExpanded: true,
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
    double padding = 5,
    double iconSize = 15,
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
            padding: EdgeInsets.all(padding * c),
            child: Icon(icon, size: iconSize * c, color: iconColor),
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
