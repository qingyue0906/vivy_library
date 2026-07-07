import 'dart:io';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class GifImage extends StatefulWidget {
  final File file;
  final GifDisplayMode gifMode;
  final int? cacheWidth;
  final BoxFit fit;
  final WidgetBuilder? errorBuilder;

  const GifImage({
    super.key,
    required this.file,
    required this.gifMode,
    this.cacheWidth,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  @override
  State<GifImage> createState() => _GifImageState();
}

class _GifImageState extends State<GifImage> {
  bool _isHovering = false;

  // 真实视口可见性：即使卡片因为 cacheExtent 被提前 build/保活，
  // 只要它没有真正进入可视区域，就不允许播放动图（用 TickerMode 冻结），
  // 避免屏幕外的动图逐帧解码占用 CPU/GPU。
  ScrollPosition? _scrollPosition;
  // 默认先当作"不在屏幕内"，直到第一次真正测量完位置为止，
  // 避免因为 cacheExtent 预构建而在还没确认可见性前就先播放动图。
  bool _onstage = false;

  @override
  void initState() {
    super.initState();
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
  void dispose() {
    _scrollPosition?.removeListener(_recheckOnstage);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 重新挂载/位置变化时，随手确认一次是否在屏幕内（滚动之外的场景，
    // 比如切换分组导致同一路径重新出现在别的位置）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _attachScrollListener());

    final canAnimate = _onstage; // 不在可视区域内一律冻结动图

    if (widget.gifMode == GifDisplayMode.unlimited) {
      return canAnimate ? _buildAnimatedImage() : _buildFrozenImage();
    }

    if (widget.gifMode == GifDisplayMode.static) {
      return _buildFrozenImage();
    }

    // hover mode
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: (_isHovering && canAnimate)
          ? _buildAnimatedImage()
          : _buildFrozenImage(),
    );
  }

  /// 正常播放动图。
  Widget _buildAnimatedImage() {
    return Image.file(
      widget.file,
      cacheWidth: widget.cacheWidth,
      fit: widget.fit,
      errorBuilder: (_, __, ___) =>
          widget.errorBuilder?.call(context) ?? const SizedBox.shrink(),
    );
  }

  /// 用 TickerMode(enabled: false) 冻结动图在首帧。
  ///
  /// 这是纯渲染层开关：Flutter 动图的逐帧推进依赖底层 Ticker，
  /// TickerMode 关闭后子树所有 Ticker 暂停，动图停在首帧。
  /// 零文件 I/O、零解码、零内存开销，对所有格式（gif/webp/后缀不符动图）
  /// 统一生效。静态图本就无动画，TickerMode 无影响，正常渲染。
  Widget _buildFrozenImage() {
    return TickerMode(
      enabled: false,
      child: Image.file(
        widget.file,
        cacheWidth: widget.cacheWidth,
        fit: widget.fit,
        errorBuilder: (_, __, ___) =>
            widget.errorBuilder?.call(context) ?? const SizedBox.shrink(),
      ),
    );
  }
}
