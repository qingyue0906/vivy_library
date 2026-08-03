import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart' as md;

/// 为 Edge 保存的网页（html + *_files 资源目录）提供本地 HTTP 服务。
///
/// Edge 保存的页面带 `crossorigin` 样式表与 `.js.下载`/无扩展名 `client`
/// 脚本：直接以 file:// 打开时，Chromium 会因 CORS 拒绝全部 CSS、按 MIME
/// 拒绝脚本，导致排版崩溃。这里用回环 HTTP 服务器同源提供文件，并对
/// Edge 的特殊命名做 MIME 修正，使页面按原站排版渲染。
///
/// 同时承担 markdown 类型的渲染：`.md`/`.markdown` 请求在服务端经
/// markdown 包（GitHub Flavored）转为 HTML 后以 text/html 返回，
/// 内置浏览器即可直接展示；文档内相对路径图片经同一服务器根解析。
class EdgeHtmlServer {
  EdgeHtmlServer._(this._root, this._server);

  final String _root;
  final HttpServer _server;

  /// 启动服务器，根目录为 [root]。使用临时端口，多个查看器互不冲突。
  static Future<EdgeHtmlServer> start(String root) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final service = EdgeHtmlServer._(root, server);
    server.listen(service._handle);
    return service;
  }

  /// 当前监听端口（临时端口，启动后生效）。
  int get port => _server.port;

  /// 生成访问指定文件的 URL（文件名已做百分号编码）。
  /// [theme] 仅对 markdown 文件生效：'dark'/'light' 决定渲染配色。
  String urlFor(String fileName, {String? theme}) {
    final url = 'http://127.0.0.1:$port/${Uri.encodeComponent(fileName)}';
    return theme == null ? url : '$url?theme=$theme';
  }

  Future<void> stop() => _server.close(force: true);

  void _handle(HttpRequest request) {
    try {
      final target = _resolve(request.uri.path);
      if (target == null) {
        _respond(request, HttpStatus.notFound, 'Not Found', 'text/plain');
        return;
      }
      final file = File(target);
      if (!file.existsSync()) {
        _respond(request, HttpStatus.notFound, 'Not Found', 'text/plain');
        return;
      }
      if (_isMarkdown(target)) {
        // markdown 由服务端转为 HTML 渲染，配色随主题参数切换
        final theme = request.uri.queryParameters['theme'] ?? 'dark';
        _respond(
          request,
          HttpStatus.ok,
          _renderMarkdown(file, theme),
          'text/html; charset=utf-8',
        );
        return;
      }
      _respond(
        request,
        HttpStatus.ok,
        file.readAsBytesSync(),
        _mimeFor(target),
      );
    } catch (_) {
      _respond(request, HttpStatus.internalServerError, 'Error', 'text/plain');
    }
  }

  /// 把 URL 路径安全地映射到根目录下的真实文件，拒绝路径穿越。
  String? _resolve(String urlPath) {
    final segments = urlPath
        .split('/')
        .where((s) => s.isNotEmpty)
        .map((s) => Uri.decodeComponent(s))
        .toList();
    if (segments.isEmpty) return null;
    if (segments.any((s) => s == '..' || s.contains('\\') || s.contains('/'))) {
      return null;
    }
    final sep = Platform.pathSeparator;
    final joined = _root.endsWith(sep)
        ? _root + segments.join(sep)
        : _root + sep + segments.join(sep);
    final resolved = File(joined).absolute.path;
    final rootAbs = Directory(_root).absolute.path;
    final rn = resolved.replaceAll('\\', '/').toLowerCase();
    final rnRoot = rootAbs.replaceAll('\\', '/').toLowerCase();
    if (!rn.startsWith(rnRoot.endsWith('/') ? rnRoot : '$rnRoot/')) {
      return null;
    }
    return resolved;
  }

  void _respond(
    HttpRequest request,
    int status,
    Object body,
    String contentType,
  ) {
    final bytes = body is List<int> ? body : utf8.encode(body as String);
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.parse(contentType)
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..add(bytes);
    request.response.close();
  }

  /// MIME 判定：修正 Edge 保存时改名导致的类型错误。
  String _mimeFor(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final lower = name.toLowerCase();
    if (lower == 'client') return 'application/javascript; charset=utf-8';
    if (lower.endsWith('.js.下载') ||
        lower.endsWith('.js.download') ||
        lower.endsWith('.js')) {
      return 'application/javascript; charset=utf-8';
    }
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return 'text/html; charset=utf-8';
    }
    if (lower.endsWith('.css')) return 'text/css; charset=utf-8';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.ico')) return 'image/x-icon';
    if (lower.endsWith('.woff2')) return 'font/woff2';
    if (lower.endsWith('.woff')) return 'font/woff';
    if (lower.endsWith('.ttf')) return 'font/ttf';
    if (lower.endsWith('.otf')) return 'font/otf';
    if (lower.endsWith('.json')) return 'application/json; charset=utf-8';
    if (lower.endsWith('.txt') || lower.endsWith('.md')) {
      return 'text/plain; charset=utf-8';
    }
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    return 'application/octet-stream';
  }

  static bool _isMarkdown(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  /// 把 markdown 文件转成带内嵌样式（跟随浅色/暗色主题）的 HTML 页面。
  String _renderMarkdown(File file, String theme) {
    var text = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final body = md.markdownToHtml(text,
        extensionSet: md.ExtensionSet.gitHubFlavored);
    final dark = theme != 'light';
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root {
  --bg: ${dark ? '#1e1e1e' : '#ffffff'};
  --fg: ${dark ? '#d4d4d4' : '#24292f'};
  --muted: ${dark ? '#9d9d9d' : '#57606a'};
  --border: ${dark ? '#3c3c3c' : '#d0d7de'};
  --code-bg: ${dark ? '#2d2d2d' : '#f6f8fa'};
  --accent: ${dark ? '#4fa0ff' : '#0969da'};
  --quote-bg: ${dark ? '#262626' : '#f6f8fa'};
}
* { box-sizing: border-box; }
html { scrollbar-color: var(--border) var(--bg); }
body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font-family: "Segoe UI", "Microsoft YaHei UI", "PingFang SC", sans-serif;
  font-size: 15px;
  line-height: 1.7;
}
#content { max-width: 860px; margin: 0 auto; padding: 24px 32px 48px; }
h1, h2, h3, h4, h5, h6 {
  line-height: 1.35;
  margin: 1.4em 0 0.6em;
  font-weight: 600;
}
h1, h2 { border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
h1 { font-size: 1.7em; } h2 { font-size: 1.4em; }
h3 { font-size: 1.2em; } h4 { font-size: 1.05em; }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
p, ul, ol, blockquote, pre, table { margin: 0.8em 0; }
ul, ol { padding-left: 1.6em; }
li { margin: 0.25em 0; }
code {
  background: var(--code-bg);
  padding: 0.15em 0.4em;
  border-radius: 4px;
  font-family: Consolas, "Courier New", monospace;
  font-size: 0.9em;
}
pre {
  background: var(--code-bg);
  padding: 12px 14px;
  border-radius: 6px;
  overflow-x: auto;
  border: 1px solid var(--border);
}
pre code { background: none; padding: 0; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid var(--border); padding: 6px 12px; text-align: left; }
th { background: var(--code-bg); font-weight: 600; }
blockquote {
  margin-left: 0;
  padding: 4px 14px;
  border-left: 3px solid var(--accent);
  background: var(--quote-bg);
  color: var(--muted);
  border-radius: 0 4px 4px 0;
}
img { max-width: 100%; }
hr { border: none; border-top: 1px solid var(--border); margin: 1.6em 0; }
</style>
</head>
<body>
<div id="content">
$body
</div>
</body>
</html>''';
  }
}
