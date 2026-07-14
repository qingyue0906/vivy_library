import 'dart:ui';
import 'package:flutter/material.dart';

/// 预设主题强调色。新增选项只需在此追加，设置页与主题构建会自动识别。
enum AppAccent {
  violet,
  blue,
  indigo,
  teal,
  emerald,
  amber,
  rose,
  crimson;

  Color get seed => switch (this) {
        AppAccent.violet => const Color(0xFF7C5CFC),
        AppAccent.blue => const Color(0xFF2F8BFF),
        AppAccent.indigo => const Color(0xFF5B5BD6),
        AppAccent.teal => const Color(0xFF12A594),
        AppAccent.emerald => const Color(0xFF1FA85C),
        AppAccent.amber => const Color(0xFFE89422),
        AppAccent.rose => const Color(0xFFE8547A),
        AppAccent.crimson => const Color(0xFFD63B4E),
      };

  String get label => switch (this) {
        AppAccent.violet => '紫罗兰',
        AppAccent.blue => '海洋蓝',
        AppAccent.indigo => '靛青',
        AppAccent.teal => '青绿',
        AppAccent.emerald => '翠绿',
        AppAccent.amber => '琥珀',
        AppAccent.rose => '玫红',
        AppAccent.crimson => '绯红',
      };
}

/// 圆角档位：紧凑 / 标准 / 宽松。所有圆角由此派生，最终再乘以 compactLevel。
enum RadiusScale {
  compact,
  standard,
  comfortable;

  double get card => switch (this) {
        RadiusScale.compact => 8,
        RadiusScale.standard => 12,
        RadiusScale.comfortable => 16,
      };
  double get button => switch (this) {
        RadiusScale.compact => 6,
        RadiusScale.standard => 8,
        RadiusScale.comfortable => 12,
      };
  double get chip => switch (this) {
        RadiusScale.compact => 5,
        RadiusScale.standard => 8,
        RadiusScale.comfortable => 11,
      };
  double get dialog => switch (this) {
        RadiusScale.compact => 12,
        RadiusScale.standard => 18,
        RadiusScale.comfortable => 24,
      };
  double get input => switch (this) {
        RadiusScale.compact => 6,
        RadiusScale.standard => 9,
        RadiusScale.comfortable => 12,
      };
  double get panel => switch (this) {
        RadiusScale.compact => 4,
        RadiusScale.standard => 6,
        RadiusScale.comfortable => 10,
      };

  String get label => switch (this) {
        RadiusScale.compact => '紧凑',
        RadiusScale.standard => '标准',
        RadiusScale.comfortable => '宽松',
      };
}

/// 标准动效时长。全部落在 120-320ms 区间，保证轻量且丝滑。
class MotionDurations {
  const MotionDurations._();
  static const Duration instant = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration page = Duration(milliseconds: 300);
}

/// 标准动效曲线。基于 Material 3 motion 与 Fluent 自然缓动。
class MotionCurves {
  const MotionCurves._();
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve standard = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Curve decelerate = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Curve accelerate = Cubic(0.3, 0.0, 1.0, 1.0);
  /// 轻微回弹，仅用于徽章/选中指示等小元素，开销极低。
  static const Curve bounce = Cubic(0.34, 1.56, 0.64, 1.0);
}

/// 通过 [ThemeExtension] 注入 [ThemeData] 的设计令牌，
/// 供全应用取用圆角与动效开关。轻量：仅持几个 double + bool。
@immutable
class AppDesignTokens extends ThemeExtension<AppDesignTokens> {
  final double cardRadius;
  final double buttonRadius;
  final double chipRadius;
  final double dialogRadius;
  final double inputRadius;
  final double panelRadius;
  final bool motionEnabled;

  const AppDesignTokens({
    required this.cardRadius,
    required this.buttonRadius,
    required this.chipRadius,
    required this.dialogRadius,
    required this.inputRadius,
    required this.panelRadius,
    required this.motionEnabled,
  });

  factory AppDesignTokens.fromScale(
    RadiusScale scale, {
    required bool motionEnabled,
  }) =>
      AppDesignTokens(
        cardRadius: scale.card,
        buttonRadius: scale.button,
        chipRadius: scale.chip,
        dialogRadius: scale.dialog,
        inputRadius: scale.input,
        panelRadius: scale.panel,
        motionEnabled: motionEnabled,
      );

  static const standard = AppDesignTokens(
    cardRadius: 12,
    buttonRadius: 8,
    chipRadius: 8,
    dialogRadius: 18,
    inputRadius: 9,
    panelRadius: 6,
    motionEnabled: true,
  );

  static AppDesignTokens of(BuildContext context) =>
      Theme.of(context).extension<AppDesignTokens>() ?? standard;

  /// 动效关闭时返回 [Duration.zero]，保证可访问性与性能开关生效。
  Duration duration(Duration d) => motionEnabled ? d : Duration.zero;

  @override
  AppDesignTokens copyWith({
    double? cardRadius,
    double? buttonRadius,
    double? chipRadius,
    double? dialogRadius,
    double? inputRadius,
    double? panelRadius,
    bool? motionEnabled,
  }) =>
      AppDesignTokens(
        cardRadius: cardRadius ?? this.cardRadius,
        buttonRadius: buttonRadius ?? this.buttonRadius,
        chipRadius: chipRadius ?? this.chipRadius,
        dialogRadius: dialogRadius ?? this.dialogRadius,
        inputRadius: inputRadius ?? this.inputRadius,
        panelRadius: panelRadius ?? this.panelRadius,
        motionEnabled: motionEnabled ?? this.motionEnabled,
      );

  @override
  AppDesignTokens lerp(AppDesignTokens? other, double t) {
    if (other == null) return this;
    return AppDesignTokens(
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t)!,
      buttonRadius: lerpDouble(buttonRadius, other.buttonRadius, t)!,
      chipRadius: lerpDouble(chipRadius, other.chipRadius, t)!,
      dialogRadius: lerpDouble(dialogRadius, other.dialogRadius, t)!,
      inputRadius: lerpDouble(inputRadius, other.inputRadius, t)!,
      panelRadius: lerpDouble(panelRadius, other.panelRadius, t)!,
      motionEnabled: t < 0.5 ? motionEnabled : other.motionEnabled,
    );
  }
}
