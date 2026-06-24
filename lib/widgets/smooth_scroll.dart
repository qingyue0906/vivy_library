import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Desktop smooth scrolling wrapper.
///
/// Wraps any scrollable built by [builder] and converts mouse-wheel deltas into
/// smooth [ScrollController.animateTo] animations. It does **not** change the
/// scrollable's physics, so scrollbar thumb drag and track page-up/down keep
/// working normally.
class SmoothScroll extends StatefulWidget {
  /// Builder that receives the internally created [ScrollController] and the
  /// physics that should be used (defaults to [ClampingScrollPhysics]).
  final Widget Function(
    BuildContext context,
    ScrollController controller,
    ScrollPhysics physics,
  ) builder;

  /// Optional external controller. If omitted, a controller is created and
  /// disposed internally.
  final ScrollController? controller;

  /// Multiplier applied to each wheel delta.
  final double scrollSpeed;

  /// Duration of the smooth scroll animation.
  final Duration duration;

  /// Curve of the smooth scroll animation.
  final Curve curve;

  /// Physics passed to the scrollable. Keep a normal physics so that the
  /// scrollbar thumb and track gestures are not disabled.
  final ScrollPhysics mobilePhysics;

  const SmoothScroll({
    super.key,
    required this.builder,
    this.controller,
    this.scrollSpeed = 2, // 步进/速度倍率
    this.duration = const Duration(milliseconds: 300), // 平滑动画时间
    this.curve = Curves.easeOutCubic,
    this.mobilePhysics = const ClampingScrollPhysics(),
  });

  @override
  State<SmoothScroll> createState() => _SmoothScrollState();
}

class _SmoothScrollState extends State<SmoothScroll> {
  late final ScrollController _controller;

  /// Running target position accumulated from consecutive wheel events.
  double? _futurePosition;

  /// The most recently started animation, used to know when we can clear the
  /// accumulated target.
  Future<void>? _animation;

  /// Direction of the last wheel event (`true` = scrolling down).
  bool _lastDeltaDown = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ScrollController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_controller.hasClients) return;

    final delta = event.scrollDelta.dy;
    if (delta == 0) return;

    final position = _controller.position;
    final min = position.minScrollExtent;
    final max = position.maxScrollExtent;
    if (min == max) return; // nothing to scroll

    final goingDown = delta > 0;
    if (_futurePosition == null || goingDown != _lastDeltaDown) {
      // Start accumulating from the current position, or reset when the user
      // reverses scroll direction.
      _futurePosition = position.pixels;
    }
    _lastDeltaDown = goingDown;

    _futurePosition =
        (_futurePosition! + delta * widget.scrollSpeed).clamp(min, max).toDouble();

    // Register first with the pointer signal resolver so that the underlying
    // Scrollable/RawScrollbar default wheel handling is skipped.
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      _handlePointerScroll,
    );

    _animateTo(_futurePosition!);
  }

  /// Callback invoked by the [PointerSignalResolver] when our overlay wins.
  void _handlePointerScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      event.respond(allowPlatformDefault: false);
    }
  }

  Future<void> _animateTo(double target) async {
    if (!_controller.hasClients) return;

    final animation = _controller.animateTo(
      target,
      duration: widget.duration,
      curve: widget.curve,
    );
    _animation = animation;

    try {
      await animation;
    } catch (_) {
      // Animation was interrupted by a newer wheel event - that's fine.
    }

    if (_animation == animation && mounted) {
      _futurePosition = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The actual scrollable uses normal physics.
        widget.builder(context, _controller, widget.mobilePhysics),
        // A transparent overlay that intercepts wheel events before they reach
        // the scrollable, while letting pointer down/up pass through for
        // scrollbar track clicks, thumb drags, and content drags.
        Positioned.fill(
          child: Listener(
            onPointerSignal: _onPointerSignal,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}
