import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 让桌面端的鼠标滚轮滚动变得平滑，同时保留滚动条 thumb 拖动。
///
/// 实现原理：
/// - 默认给子滚动组件 [NeverScrollableScrollPhysics]，这样 Flutter 不会用滚轮事件
///   直接“跳一格”。
/// - 用 [Listener] 拦截 [PointerScrollEvent]，通过 [ScrollController.animateTo]
///   自己播放平滑动画。
/// - 检测到 [PointerDownEvent] 时切回 [ClampingScrollPhysics]，允许用户拖动内容；
///   [PointerUpEvent] 时再切回桌面物理，保证后续滚轮仍然平滑。
/// - 滚动条 thumb 拖动不依赖 physics 的 drag 手势，因此始终可用。
class SmoothScroll extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    ScrollController controller,
    ScrollPhysics physics,
  ) builder;

  final ScrollPhysics mobilePhysics;
  final Duration duration;
  final Curve curve;
  final double scrollSpeed;

  const SmoothScroll({
    super.key,
    required this.builder,
    this.mobilePhysics = const ClampingScrollPhysics(),
    this.duration = const Duration(milliseconds: 350),
    this.curve = Curves.easeOutQuart,
    this.scrollSpeed = 2.0,
  });

  @override
  State<SmoothScroll> createState() => _SmoothScrollState();
}

class _SmoothScrollState extends State<SmoothScroll> {
  late final ScrollController _controller;

  /// true 表示当前使用桌面物理（屏蔽滚轮默认行为，由本组件自己动画）。
  bool _desktop = true;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ScrollPhysics get _physics =>
      _desktop ? const NeverScrollableScrollPhysics() : widget.mobilePhysics;

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_controller.hasClients) return;

    final delta = event.scrollDelta.dy;
    if (delta == 0) return;

    final target = (_controller.position.pixels + delta * widget.scrollSpeed)
        .clamp(
          _controller.position.minScrollExtent,
          _controller.position.maxScrollExtent,
        )
        .toDouble();
    if (target == _controller.position.pixels) return;

    if (!_desktop) {
      // 刚从触摸/拖动状态回来，先切回桌面物理再动画
      setState(() => _desktop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateTo(target);
      });
    } else {
      _animateTo(target);
    }
  }

  void _animateTo(double target) {
    if (!_controller.hasClients) return;
    _controller.animateTo(
      target,
      duration: widget.duration,
      curve: widget.curve,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_desktop) {
      // 停止当前动画，确保拖动从当前位置开始
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.pixels);
      }
      setState(() => _desktop = false);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_desktop) {
      setState(() => _desktop = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      behavior: HitTestBehavior.translucent,
      child: widget.builder(context, _controller, _physics),
    );
  }
}
