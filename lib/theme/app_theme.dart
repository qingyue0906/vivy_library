import 'package:flutter/material.dart';
import 'app_animations.dart';

/// 默认强调色：沿用原 VS Code 蓝，保证升级后观感熟悉。
const Color kDefaultAccent = Color(0xFF007ACC);

/// 精选强调色板（设置页取色用，无需引入第三方取色器依赖）。
const List<Color> kAccentPresets = [
  Color(0xFF007ACC), // VS Code 蓝
  Color(0xFF2F81F7), // 亮蓝
  Color(0xFF6E56CF), // 紫
  Color(0xFF9C27B0), // 品红紫
  Color(0xFFE5326E), // 玫红
  Color(0xFFEF5350), // 红
  Color(0xFFF57C00), // 橙
  Color(0xFFF9A825), // 琥珀
  Color(0xFF2E7D32), // 绿
  Color(0xFF00897B), // 青绿
  Color(0xFF0097A7), // 青
  Color(0xFF546E7A), // 蓝灰
];

/// 全局外观设置（单一真源）。驱动强调色、圆角、密度、字号、动效、毛玻璃。
class AppearanceSettings {
  /// 主题强调色（种子色）。
  final Color accent;

  /// 圆角缩放系数（0.0 = 直角，1.0 = 默认，1.6 = 更圆润）。
  final double radiusScale;

  /// 全局字号缩放（0.85 ~ 1.30，1.0 = 默认）。通过 MediaQuery.textScaler 生效。
  final double fontScale;

  /// 界面密度（-2 紧凑 ~ 2 宽松，0 = 默认）。映射到 VisualDensity。
  final double density;

  /// 动效强度档位。
  final MotionLevel motionLevel;

  /// 是否启用毛玻璃（面板/标题栏 BackdropFilter 磨砂）。
  final bool glass;

  /// 毛玻璃模糊强度（sigma，0 ~ 30）。
  final double glassBlur;

  const AppearanceSettings({
    this.accent = kDefaultAccent,
    this.radiusScale = 1.0,
    this.fontScale = 1.0,
    this.density = 0.0,
    this.motionLevel = MotionLevel.normal,
    this.glass = false,
    this.glassBlur = 18.0,
  });

  AppearanceSettings copyWith({
    Color? accent,
    double? radiusScale,
    double? fontScale,
    double? density,
    MotionLevel? motionLevel,
    bool? glass,
    double? glassBlur,
  }) {
    return AppearanceSettings(
      accent: accent ?? this.accent,
      radiusScale: radiusScale ?? this.radiusScale,
      fontScale: fontScale ?? this.fontScale,
      density: density ?? this.density,
      motionLevel: motionLevel ?? this.motionLevel,
      glass: glass ?? this.glass,
      glassBlur: glassBlur ?? this.glassBlur,
    );
  }
}

/// 圆角/毛玻璃等度量令牌。组件统一从 `Theme.of(context).extension<VivyMetrics>()` 取值，
/// 从而实现"圆角缩放/毛玻璃"一键生效。
@immutable
class VivyMetrics extends ThemeExtension<VivyMetrics> {
  final double radiusSmall;
  final double radius;
  final double radiusLarge;
  final double radiusPill;
  final bool glass;
  final double glassBlur;

  const VivyMetrics({
    required this.radiusSmall,
    required this.radius,
    required this.radiusLarge,
    required this.radiusPill,
    required this.glass,
    required this.glassBlur,
  });

  /// 由圆角缩放系数生成一组度量。
  factory VivyMetrics.fromScale(
    double scale, {
    required bool glass,
    required double glassBlur,
  }) {
    return VivyMetrics(
      radiusSmall: (8 * scale).clamp(0, 40),
      radius: (12 * scale).clamp(0, 48),
      radiusLarge: (18 * scale).clamp(0, 60),
      radiusPill: 999,
      glass: glass,
      glassBlur: glassBlur,
    );
  }

  BorderRadius get brSmall => BorderRadius.circular(radiusSmall);
  BorderRadius get br => BorderRadius.circular(radius);
  BorderRadius get brLarge => BorderRadius.circular(radiusLarge);
  BorderRadius get brPill => BorderRadius.circular(radiusPill);

  @override
  VivyMetrics copyWith({
    double? radiusSmall,
    double? radius,
    double? radiusLarge,
    double? radiusPill,
    bool? glass,
    double? glassBlur,
  }) {
    return VivyMetrics(
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radius: radius ?? this.radius,
      radiusLarge: radiusLarge ?? this.radiusLarge,
      radiusPill: radiusPill ?? this.radiusPill,
      glass: glass ?? this.glass,
      glassBlur: glassBlur ?? this.glassBlur,
    );
  }

  @override
  VivyMetrics lerp(ThemeExtension<VivyMetrics>? other, double t) {
    if (other is! VivyMetrics) return this;
    return VivyMetrics(
      radiusSmall: _lerpD(radiusSmall, other.radiusSmall, t),
      radius: _lerpD(radius, other.radius, t),
      radiusLarge: _lerpD(radiusLarge, other.radiusLarge, t),
      radiusPill: _lerpD(radiusPill, other.radiusPill, t),
      glass: t < 0.5 ? glass : other.glass,
      glassBlur: _lerpD(glassBlur, other.glassBlur, t),
    );
  }

  static double _lerpD(double a, double b, double t) => a + (b - a) * t;

  /// 便捷读取（组件里 `context.metrics`）。
  static VivyMetrics of(BuildContext context) =>
      Theme.of(context).extension<VivyMetrics>() ??
      VivyMetrics.fromScale(1.0, glass: false, glassBlur: 18);
}

/// 语义色令牌。替换各组件散落的 `Colors.amber.shade400` / `Colors.blue.shade400` 等硬编码。
@immutable
class VivyColors extends ThemeExtension<VivyColors> {
  final Color star; // 收藏/标星
  final Color rating; // 分级/评分
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  // 媒体类型色（用于卡片类型徽章）。
  final Color typeVideo;
  final Color typeAudio;
  final Color typeComic;
  final Color typeEbook;
  final Color typeExe;
  final Color typeFolder;
  final Color typeOther;

  const VivyColors({
    required this.star,
    required this.rating,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.typeVideo,
    required this.typeAudio,
    required this.typeComic,
    required this.typeEbook,
    required this.typeExe,
    required this.typeFolder,
    required this.typeOther,
  });

  factory VivyColors.forBrightness(Brightness b) {
    final dark = b == Brightness.dark;
    return VivyColors(
      star: const Color(0xFFFFC53D),
      rating: dark ? const Color(0xFFFFB74D) : const Color(0xFFF57C00),
      success: const Color(0xFF3FB950),
      warning: const Color(0xFFF0A020),
      danger: const Color(0xFFF04438),
      info: const Color(0xFF3B82F6),
      typeVideo: const Color(0xFF5B8DEF),
      typeAudio: const Color(0xFF20C997),
      typeComic: const Color(0xFFFF922B),
      typeEbook: const Color(0xFF9775FA),
      typeExe: const Color(0xFF868E96),
      typeFolder: const Color(0xFFFFC53D),
      typeOther: const Color(0xFF748FFC),
    );
  }

  /// 按类型名（大小写不敏感）返回类型色。
  Color forType(String? type) {
    switch ((type ?? '').toLowerCase()) {
      case 'video':
      case 'movie':
        return typeVideo;
      case 'audio':
      case 'music':
        return typeAudio;
      case 'comic':
      case 'manga':
        return typeComic;
      case 'ebook':
      case 'book':
        return typeEbook;
      case 'exe':
      case 'game':
      case 'app':
        return typeExe;
      case 'folder':
        return typeFolder;
      default:
        return typeOther;
    }
  }

  @override
  VivyColors copyWith({
    Color? star,
    Color? rating,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? typeVideo,
    Color? typeAudio,
    Color? typeComic,
    Color? typeEbook,
    Color? typeExe,
    Color? typeFolder,
    Color? typeOther,
  }) {
    return VivyColors(
      star: star ?? this.star,
      rating: rating ?? this.rating,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      typeVideo: typeVideo ?? this.typeVideo,
      typeAudio: typeAudio ?? this.typeAudio,
      typeComic: typeComic ?? this.typeComic,
      typeEbook: typeEbook ?? this.typeEbook,
      typeExe: typeExe ?? this.typeExe,
      typeFolder: typeFolder ?? this.typeFolder,
      typeOther: typeOther ?? this.typeOther,
    );
  }

  @override
  VivyColors lerp(ThemeExtension<VivyColors>? other, double t) {
    if (other is! VivyColors) return this;
    return VivyColors(
      star: Color.lerp(star, other.star, t)!,
      rating: Color.lerp(rating, other.rating, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      typeVideo: Color.lerp(typeVideo, other.typeVideo, t)!,
      typeAudio: Color.lerp(typeAudio, other.typeAudio, t)!,
      typeComic: Color.lerp(typeComic, other.typeComic, t)!,
      typeEbook: Color.lerp(typeEbook, other.typeEbook, t)!,
      typeExe: Color.lerp(typeExe, other.typeExe, t)!,
      typeFolder: Color.lerp(typeFolder, other.typeFolder, t)!,
      typeOther: Color.lerp(typeOther, other.typeOther, t)!,
    );
  }

  static VivyColors of(BuildContext context) =>
      Theme.of(context).extension<VivyColors>() ??
      VivyColors.forBrightness(Theme.of(context).brightness);
}

/// 便捷读取扩展。
extension VivyThemeContext on BuildContext {
  VivyMetrics get metrics => VivyMetrics.of(this);
  VivyColors get vivy => VivyColors.of(this);
  ColorScheme get scheme => Theme.of(this).colorScheme;
}

/// 主题构建入口：根据亮/暗与外观设置生成 [ThemeData]。
ThemeData buildAppTheme({
  required Brightness brightness,
  required AppearanceSettings appearance,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: appearance.accent,
    brightness: brightness,
  );

  final metrics = VivyMetrics.fromScale(
    appearance.radiusScale,
    glass: appearance.glass,
    glassBlur: appearance.glassBlur,
  );
  final vcolors = VivyColors.forBrightness(brightness);

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    visualDensity: VisualDensity(
      horizontal: appearance.density.clamp(-2, 2),
      vertical: appearance.density.clamp(-2, 2),
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    dividerColor: scheme.outlineVariant.withValues(alpha: 0.6),
    splashFactory: InkSparkle.splashFactory,
    extensions: [metrics, vcolors],
    cardTheme: base.cardTheme.copyWith(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: metrics.br),
      clipBehavior: Clip.antiAlias,
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      decoration: BoxDecoration(
        color: scheme.inverseSurface.withValues(alpha: 0.92),
        borderRadius: metrics.brSmall,
      ),
      textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: metrics.brSmall,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: metrics.brSmall,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: metrics.brSmall,
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: metrics.brSmall),
    ),
  );
}
