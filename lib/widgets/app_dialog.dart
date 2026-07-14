import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// 统一的对话框展示：在 Material 默认基础上加入"淡入 + 轻微上滑"过渡，
/// 配合 DialogTheme 的圆角与背景，呈现现代柔和的弹出观感。轻开销：仅一个
/// FadeTransition + SlideTransition，时长 240ms。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  return Navigator.of(context).push<T>(
    RawDialogRoute<T>(
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: barrierColor ?? Colors.black54,
      transitionDuration: MotionDurations.medium,
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: MotionCurves.decelerate,
          reverseCurve: MotionCurves.accelerate,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}
