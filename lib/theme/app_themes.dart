import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// 构建"现代桌面融合风"亮色主题：Fluent 层次质感 + Material 3 表现力。
ThemeData buildLightTheme({
  required AppAccent accent,
  required RadiusScale radiusScale,
  required bool motionEnabled,
}) {
  final cs = ColorScheme.fromSeed(
    seedColor: accent.seed,
    brightness: Brightness.light,
  );
  final t = AppDesignTokens.fromScale(radiusScale, motionEnabled: motionEnabled);
  return _buildTheme(cs, t, Brightness.light);
}

/// 构建暗色主题。
ThemeData buildDarkTheme({
  required AppAccent accent,
  required RadiusScale radiusScale,
  required bool motionEnabled,
}) {
  final cs = ColorScheme.fromSeed(
    seedColor: accent.seed,
    brightness: Brightness.dark,
  );
  final t = AppDesignTokens.fromScale(radiusScale, motionEnabled: motionEnabled);
  return _buildTheme(cs, t, Brightness.dark);
}

ThemeData _buildTheme(ColorScheme cs, AppDesignTokens t, Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    // 桌面端以 hover 为主要反馈，去除点击涟漪以贴近原生桌面观感。
    splashFactory: NoSplash.splashFactory,
    hoverColor: cs.primary.withValues(alpha: 0.08),
    focusColor: cs.primary.withValues(alpha: 0.12),
    highlightColor: Colors.transparent,
    extensions: [t],
    // ---- 卡片 ----
    cardTheme: CardThemeData(
      color: cs.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.cardRadius),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),
    // ---- AppBar ----
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 16,
    ),
    // ---- 输入框 / 搜索框 ----
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      hoverColor: cs.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: cs.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: cs.error, width: 2),
      ),
      hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
    ),
    // ---- Chip ----
    chipTheme: ChipThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      selectedColor: cs.primaryContainer,
      checkmarkColor: cs.onPrimaryContainer,
      labelStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.chipRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    // ---- 对话框 ----
    dialogTheme: DialogThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.dialogRadius),
      ),
      titleTextStyle: TextStyle(
        color: cs.onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5),
    ),
    // ---- FAB ----
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 2,
      highlightElevation: 4,
      hoverElevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.buttonRadius + 2),
      ),
    ),
    // ---- 分隔线 ----
    dividerTheme: DividerThemeData(
      color: cs.outlineVariant.withValues(alpha: 0.6),
      thickness: 1,
      space: 1,
    ),
    // ---- 滚动条：细圆角，hover 加粗 ----
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.hovered) ? 10.0 : 6.0,
      ),
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.dragged)) {
          return cs.primary.withValues(alpha: 0.6);
        }
        if (s.contains(WidgetState.hovered)) {
          return cs.outline.withValues(alpha: 0.5);
        }
        return cs.outline.withValues(alpha: 0.3);
      }),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    // ---- ListTile ----
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.buttonRadius),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    ),
    // ---- SnackBar ----
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: cs.inverseSurface,
      contentTextStyle: TextStyle(color: cs.onInverseSurface, fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.buttonRadius),
      ),
      elevation: 3,
    ),
    // ---- TabBar ----
    tabBarTheme: TabBarThemeData(
      labelColor: cs.primary,
      unselectedLabelColor: cs.onSurfaceVariant,
      indicatorColor: cs.primary,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 13),
      dividerColor: cs.outlineVariant.withValues(alpha: 0.5),
      overlayColor: WidgetStateProperty.all(cs.primary.withValues(alpha: 0.08)),
    ),
    // ---- Tooltip ----
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(t.buttonRadius),
      ),
      textStyle: TextStyle(color: cs.onInverseSurface, fontSize: 12),
      waitDuration: const Duration(milliseconds: 500),
    ),
    // ---- 菜单 ----
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
        elevation: const WidgetStatePropertyAll(3),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius + 2),
          ),
        ),
      ),
    ),
    menuBarTheme: MenuBarThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(cs.surfaceContainerLow),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
        elevation: const WidgetStatePropertyAll(3),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius + 2),
          ),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cs.surfaceContainerHigh,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.buttonRadius + 2),
      ),
    ),
    // ---- 进度指示器 ----
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: cs.primary,
      linearTrackColor: cs.surfaceContainerHighest,
      circularTrackColor: cs.surfaceContainerHighest,
      linearMinHeight: 4,
    ),
    // ---- Slider ----
    sliderTheme: SliderThemeData(
      activeTrackColor: cs.primary,
      inactiveTrackColor: cs.surfaceContainerHighest,
      thumbColor: cs.primary,
      overlayColor: cs.primary.withValues(alpha: 0.12),
      trackHeight: 4,
      valueIndicatorColor: cs.primary,
    ),
    // ---- Switch ----
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return cs.onPrimary;
        return cs.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return cs.primary;
        return cs.surfaceContainerHighest;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    // ---- Radio ----
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return cs.primary;
        return cs.onSurfaceVariant;
      }),
    ),
    // ---- NavigationBar ----
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cs.surfaceContainer,
      indicatorColor: cs.primaryContainer,
      labelTextStyle: WidgetStateProperty.all(
        TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? cs.onPrimaryContainer
              : cs.onSurfaceVariant,
        ),
      ),
    ),
    // ---- 按钮 ----
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: cs.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.primary,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: cs.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
      ),
    ),
    // ---- ExpansionTile ----
    expansionTileTheme: ExpansionTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.cardRadius),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.cardRadius),
      ),
      iconColor: cs.onSurfaceVariant,
    ),
  );
}
