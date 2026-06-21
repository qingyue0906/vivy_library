import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class GifImage extends StatefulWidget {
  final File file;
  final GifDisplayMode gifMode;
  final int? cacheWidth;
  final BoxFit fit;
  final WidgetBuilder? errorBuilder;
  final Color? placeholderColor;

  const GifImage({
    super.key,
    required this.file,
    required this.gifMode,
    this.cacheWidth,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.placeholderColor,
  });

  @override
  State<GifImage> createState() => _GifImageState();
}

class _GifImageState extends State<GifImage> {
  static final Map<String, Uint8List> _firstFrameCache = {};

  bool _isHovering = false;
  Uint8List? _firstFrame;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.gifMode != GifDisplayMode.unlimited) {
      _loadFirstFrame();
    } else {
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(GifImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _firstFrame = null;
      _loading = true;
      _hasError = false;
      if (widget.gifMode != GifDisplayMode.unlimited) {
        _loadFirstFrame();
      } else {
        _loading = false;
      }
    }
  }

  Future<void> _loadFirstFrame() async {
    final path = widget.file.path;
    final cached = _firstFrameCache[path];
    if (cached != null) {
      if (mounted) setState(() { _firstFrame = cached; _loading = false; });
      return;
    }
    try {
      final bytes = await widget.file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: widget.cacheWidth,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      codec.dispose();
      frame.image.dispose();
      if (byteData == null) {
        if (mounted) setState(() { _hasError = true; _loading = false; });
        return;
      }
      final data = byteData.buffer.asUint8List();
      _firstFrameCache[path] = data;
      if (mounted) setState(() { _firstFrame = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _hasError = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.gifMode == GifDisplayMode.unlimited) {
      return _buildAnimatedImage();
    }

    if (_hasError && widget.errorBuilder != null) {
      return widget.errorBuilder!(context);
    }

    if (_loading) {
      return Container(
        color: widget.placeholderColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }

    if (widget.gifMode == GifDisplayMode.static) {
      return _buildStaticImage();
    }

    // hover mode
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: _isHovering ? _buildAnimatedImage() : _buildStaticImage(),
    );
  }

  Widget _buildAnimatedImage() {
    return Image.file(
      widget.file,
      cacheWidth: widget.cacheWidth,
      fit: widget.fit,
      errorBuilder: (_, __, ___) =>
          widget.errorBuilder?.call(context) ?? const SizedBox.shrink(),
    );
  }

  Widget _buildStaticImage() {
    if (_firstFrame == null) {
      return Container(
        color: widget.placeholderColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }
    return Image.memory(
      _firstFrame!,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          widget.errorBuilder?.call(context) ?? const SizedBox.shrink(),
    );
  }
}
