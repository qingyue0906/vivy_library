import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'services/settings_service.dart';
import 'utils/app_quit.dart';
import 'widgets/shell_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final savedTheme = await SettingsService.loadThemeMode();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    final saved = await SettingsService.loadWindowState();
    // 阈值验证：防止持久化了异常值（如最小化时 GetWindowRect 返回的 -32000，
    // 或被强杀时保存的极端值），导致下次启动窗口在屏幕外不可见。
    final dx = (saved.dx < -100 || saved.dx > 10000) ? 10.0 : saved.dx;
    final dy = (saved.dy < -100 || saved.dy > 10000) ? 10.0 : saved.dy;
    final w = (saved.width < 200 || saved.width > 10000) ? 1280.0 : saved.width;
    final h = (saved.height < 200 || saved.height > 10000) ? 720.0 : saved.height;
    await windowManager.setPosition(Offset(dx, dy));
    await windowManager.setSize(Size(w, h));
    await windowManager.setPreventClose(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    windowManager.addListener(_WindowStateListener());
  }

  runApp(VivyApp(initialThemeMode: savedTheme));
}

class _WindowStateListener with WindowListener {
  @override
  void onWindowClose() async {
    await quitApp();
  }
}

class VivyApp extends StatefulWidget {
  final ThemeMode initialThemeMode;

  const VivyApp({super.key, required this.initialThemeMode});

  @override
  State<VivyApp> createState() => _VivyAppState();
}

class _VivyAppState extends State<VivyApp> {
  late ThemeMode _themeMode;
  late GridSettings _gridSettings;
  BackgroundSettings _backgroundSettings = const BackgroundSettings();

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
    _gridSettings = const GridSettings();
    _loadGridSettings();
    _loadBackgroundSettings();
  }

  Future<void> _loadGridSettings() async {
    final gs = await SettingsService.loadGridSettings();
    setState(() => _gridSettings = gs);
  }

  Future<void> _loadBackgroundSettings() async {
    final bg = await SettingsService.loadBackgroundSettings();
    setState(() => _backgroundSettings = bg);
  }

  void _onThemeChanged(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  void _onGridSettingsChanged(GridSettings settings) {
    setState(() => _gridSettings = settings);
  }

  void _onBackgroundChanged(BackgroundSettings settings) {
    setState(() => _backgroundSettings = settings);
  }

  // VS Code 暗色配色
  static const _vscodeDarkSurface = Color(0xFF1E1E1E);
  static const _vscodeDarkSidebar = Color(0xFF252526);
  static const _vscodeDarkInactiveTab = Color(0xFF2D2D2D);
  static const _vscodeDarkActivityBar = Color(0xFF333333);
  static const _vscodeDarkBorder = Color(0xFF3C3C3C);
  static const _vscodeDarkText = Color(0xFFCCCCCC);
  static const _vscodeBlue = Color(0xFF007ACC);
  static const _vscodeSelection = Color(0xFF264F78);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vivy Library',
      scrollBehavior: const _GutterScrollBehavior(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        scrollbarTheme: ScrollbarThemeData(
          thumbVisibility: const WidgetStatePropertyAll(true),
          trackVisibility: const WidgetStatePropertyAll(true),
          thickness: const WidgetStatePropertyAll(8),
          radius: const Radius.circular(4),
          thumbColor: WidgetStateProperty.resolveWith((states) {
            final cs = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
            return cs.onSurface.withValues(alpha: 0.45);
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            final cs = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
            return cs.onSurface.withValues(alpha: 0.1);
          }),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: _vscodeBlue,
          surface: _vscodeDarkSurface,
          onSurface: _vscodeDarkText,
          surfaceContainerLow: _vscodeDarkSidebar,
          surfaceContainer: _vscodeDarkInactiveTab,
          surfaceContainerHigh: _vscodeDarkActivityBar,
          surfaceContainerHighest: _vscodeDarkBorder,
          primaryContainer: _vscodeSelection,
          onPrimaryContainer: _vscodeDarkText,
          secondaryContainer: _vscodeDarkActivityBar,
          outline: _vscodeDarkBorder,
          outlineVariant: _vscodeDarkBorder,
        ),
        scaffoldBackgroundColor: _vscodeDarkSurface,
        scrollbarTheme: ScrollbarThemeData(
          thumbVisibility: const WidgetStatePropertyAll(true),
          trackVisibility: const WidgetStatePropertyAll(true),
          thickness: const WidgetStatePropertyAll(8),
          radius: const Radius.circular(4),
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              _vscodeDarkText.withValues(alpha: 0.45)),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              _vscodeDarkText.withValues(alpha: 0.1)),
        ),
      ),
      themeMode: _themeMode,
      home: ShellPage(
        onThemeChanged: _onThemeChanged,
        onGridSettingsChanged: _onGridSettingsChanged,
        gridSettings: _gridSettings,
        backgroundSettings: _backgroundSettings,
        onBackgroundChanged: _onBackgroundChanged,
      ),
    );
  }
}

/// 自定义滚动行为：在所有可滚动区域右侧留出滚动条宽度的 gutter，
/// 让常态显示的滚动条不遮挡内容（内容向左偏移一个滚动条宽度）。
class _GutterScrollBehavior extends MaterialScrollBehavior {
  const _GutterScrollBehavior();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    return Scrollbar(
      controller: details.controller,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: child,
      ),
    );
  }
}
