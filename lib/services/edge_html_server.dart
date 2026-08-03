import 'dart:io';

/// 为 Edge 保存的网页（html + *_files 资源目录）提供本地 HTTP 服务。
///
/// Edge 保存的页面带 `crossorigin` 样式表与 `.js.下载`/无扩展名 `client`
/// 脚本：直接以 file:// 打开时，Chromium 会因 CORS 拒绝全部 CSS、按 MIME
/// 拒绝脚本，导致排版崩溃。这里用回环 HTTP 服务器同源提供文件，并对
/// Edge 的特殊命名做 MIME 修正，使页面按原站排版渲染。
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
  String urlFor(String fileName) {
    return 'http://127.0.0.1:$port/${Uri.encodeComponent(fileName)}';
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
    final bytes = body is List<int> ? body : (body as String).codeUnits;
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
}
