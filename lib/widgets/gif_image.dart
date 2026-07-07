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

  // 真实视口可见性：即使卡片因为 cacheExtent 被提前 build/保活，
  // 只要它没有真正进入可视区域，就不允许播放动图（退化为静态首帧），
  // 避免分组导致布局更稀疏时，缓存窗口内挂载的动图数量意外增多，
  // 从而拖高 CPU/GPU 占用。
  ScrollPosition? _scrollPosition;
  // 默认先当作"不在屏幕内"，直到第一次真正测量完位置为止，
  // 避免因为 cacheExtent 预构建而在还没确认可见性前就先播放一帧动图。
  bool _onstage = false;

  @override
  void initState() {
    super.initState();
    // 无论哪种模式都提前把首帧准备好，这样一旦判定为"不在屏幕内"，
    // 可以立刻退化为静态图，而不用等待额外的异步解码。
    _loadFirstFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attachScrollListener());
  }

  void _attachScrollListener() {
    if (!mounted) return;
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _scrollPosition) {
      _scrollPosition?.removeListener(_recheckOnstage);
      _scrollPosition = position;
      _scrollPosition?.addListener(_recheckOnstage);
    }
    _recheckOnstage();
  }

  void _recheckOnstage() {
    if (!mounted) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    final scrollable = Scrollable.maybeOf(context);
    final viewportBox = scrollable?.context.findRenderObject() as RenderBox?;
    if (renderBox == null || viewportBox == null || !renderBox.attached) return;

    final origin = renderBox.localToGlobal(Offset.zero, ancestor: viewportBox);
    final selfRect = origin & renderBox.size;
    final viewportRect = Offset.zero & viewportBox.size;
    final visible = selfRect.overlaps(viewportRect);

    if (visible != _onstage && mounted) {
      setState(() => _onstage = visible);
    }
  }

  @override
  void didUpdateWidget(GifImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _firstFrame = null;
      _loading = true;
      _hasError = false;
      _loadFirstFrame();
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_recheckOnstage);
    super.dispose();
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
    // 重新挂载/位置变化时，随手确认一次是否在屏幕内（滚动之外的场景，
    // 比如切换分组导致同一路径重新出现在别的位置）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _attachScrollListener());

    if (_hasError && widget.errorBuilder != null) {
      return widget.errorBuilder!(context);
    }

    final canAnimate = _onstage; // 不在可视区域内一律不允许播放动图

    if (widget.gifMode == GifDisplayMode.unlimited) {
      if (!canAnimate) return _buildStaticImage();
      return _buildAnimatedImage();
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
      child: (_isHovering && canAnimate) ? _buildAnimatedImage() : _buildStaticImage(),
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
