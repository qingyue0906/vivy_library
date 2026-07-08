import 'dart:async';
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

  ScrollPosition? _scrollPosition;
  Timer? _recheckTimer;
  // 默认在屏内立即播放（等同 fe71ad2），避免首帧冻结闪烁；屏幕外动图
  // 由停靠后防抖的 _recheckOnstage 统一冻结，保留 CPU 优化（1d024d7 收益）。
  bool _onstage = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachScrollListener();
      _scheduleRecheck();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachScrollListener();
      _scheduleRecheck();
    });
  }

  void _attachScrollListener() {
    if (!mounted) return;
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _scrollPosition) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = position;
      _scrollPosition?.addListener(_onScroll);
    }
  }

  // 滚动 / 面板拖动时 ScrollPosition 每帧发通知，这里只重置防抖定时器，
  // 不在帧内做任何几何查询——连续拖动期间零重检，等同 fe71ad2 的流畅度。
  // 持续拖动时定时器被反复重置，_recheckOnstage 不会在拖动中执行，故全部动图照常播放。
  void _onScroll() => _scheduleRecheck();

  void _scheduleRecheck() {
    if (!mounted) return;
    _recheckTimer?.cancel();
    _recheckTimer = Timer(const Duration(milliseconds: 150), _recheckOnstage);
  }

  void _recheckOnstage() {
    if (!mounted) return;
    _recheckTimer?.cancel(); // 防重入
    final renderBox = context.findRenderObject() as RenderBox?;
    final scrollable = Scrollable.maybeOf(context);
    final viewportBox =
        scrollable?.context.findRenderObject() as RenderBox?;
    if (renderBox == null ||
        viewportBox == null ||
        !renderBox.attached) {
      return;
    }

    final origin =
        renderBox.localToGlobal(Offset.zero, ancestor: viewportBox);
    final selfRect = origin & renderBox.size;
    final viewportRect = Offset.zero & viewportBox.size;
    final visible = selfRect.overlaps(viewportRect);

    if (visible != _onstage && mounted) {
      setState(() => _onstage = visible);
    }
  }

  @override
  void dispose() {
    _recheckTimer?.cancel();
    _scrollPosition?.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
