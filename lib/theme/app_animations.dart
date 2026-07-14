import 'package:flutter/material.dart';

/// 全局动效强度档位。由设置页控制，`AppMotion.level` 为单一真源。
enum MotionLevel {
  /// 关闭：所有动画时长归零（等价"减弱动效"最强档，无障碍友好）。
  off,

  /// 减弱：动画更快、位移更小。
  reduced,

  /// 标准：默认档位。
  normal,

  /// 增强：动画更从容，位移/缩放更明显，更有"高级感"。
  expressive,
}

/// 统一的动效令牌（时长、曲线、位移幅度）。
///
/// 设计目标：全应用只从这里取动画参数，配合 [MotionLevel] 做全局缩放，
/// 从而实现"动效强度/减弱动效"一键生效，且不侵入各组件的具体数值。
class AppMotion {
  AppMotion._();

  /// 当前动效档位（单一真源）。在 `main()` 预载设置后写入。
  static MotionLevel level = MotionLevel.normal;

  /// 是否启用动画（关闭档时为 false，组件可据此跳过 Hero/转场等）。
  static bool get enabled => level != MotionLevel.off;

  /// 时长缩放系数。
  static double get scale {
    switch (level) {
      case MotionLevel.off:
        return 0.0;
      case MotionLevel.reduced:
        return 0.6;
      case MotionLevel.normal:
        return 1.0;
      case MotionLevel.expressive:
        return 1.3;
    }
  }

  /// 位移/缩放等"幅度"缩放系数（关闭档仍给一点点，避免完全无反馈时显得卡死；
  /// 实际时长为 0 时不会有可见位移）。
  static double get amplitude {
    switch (level) {
      case MotionLevel.off:
        return 0.0;
      case MotionLevel.reduced:
        return 0.6;
      case MotionLevel.normal:
        return 1.0;
      case MotionLevel.expressive:
        return 1.25;
    }
  }

  // --- 基准时长（未缩放）---
  static const Duration _fast = Duration(milliseconds: 140);
  static const Duration _normal = Duration(milliseconds: 240);
  static const Duration _slow = Duration(milliseconds: 380);

  /// 缩放后的时长，供组件直接使用。
  static Duration get durFast => _scaled(_fast);
  static Duration get durNormal => _scaled(_normal);
  static Duration get durSlow => _scaled(_slow);

  static Duration _scaled(Duration base) =>
      Duration(milliseconds: (base.inMilliseconds * scale).round());

  /// 任意基准时长的缩放版本。
  static Duration scaled(Duration base) => _scaled(base);

  // --- 曲线 ---
  /// 强调曲线：进入/展开，减速收尾，最有质感。
  static const Curve emphasized = Curves.easeOutCubic;

  /// 标准曲线：状态变化、hover。
  static const Curve standard = Curves.easeInOutCubic;

  /// 退出曲线：加速离场。
  static const Curve accelerate = Curves.easeInCubic;
}

extension MotionLevelLabel on MotionLevel {
  /// 存储用稳定字符串键。
  String get key => name;

  static MotionLevel fromKey(String? key) => MotionLevel.values.firstWhere(
        (e) => e.name == key,
        orElse: () => MotionLevel.normal,
      );
}
