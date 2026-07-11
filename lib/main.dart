import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:fvp/mdk.dart' as mdk;
import 'package:pdfrx/pdfrx.dart';
import 'package:window_manager/window_manager.dart';
import 'services/app_data_service.dart';
import 'services/script_service.dart';
import 'services/settings_service.dart';
import 'services/translations.dart';
import 'utils/app_quit.dart';
import 'widgets/shell_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // pdfrx 在任何 pdfrx 控件/引擎 API 使用前初始化 PDFium native assets（Windows 需开发者模式）。
  await pdfrxFlutterInitialize();


  fvp.registerWith();

  await AppDataService.migrateIfNeeded();

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
    windowManager.addListener(_WindowStateListener());

    // 以正常窗口尺寸打开；全屏（最大化）状态改由 ShellPage 在首帧后再切换，
    // 避免 window_manager 在启动时 maximize 被原生 runner 的 ShowWindow(SW_SHOWNORMAL) 还原。
    await windowManager.waitUntilReadyToShow();
    await windowManager.setPosition(Offset(dx, dy));
    await windowManager.setSize(Size(w, h));
    await windowManager.setPreventClose(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.show();
  }

  final scriptService = ScriptService();
  await scriptService.init();
  runApp(ExcludeSemantics(
    child: VivyApp(initialThemeMode: savedTheme, scriptService: scriptService),
  ));

  // fvp 注册时会把 libmdk 日志设为 "all"，解码/打开媒体时产生大量原生→Dart 日志
  // 投递，偶发 "postCObject error"（fvp 源码记为无害死日志）。延迟到 fvp 初始化后
  // 将日志降为 warning，停止日志洪流以消除刷屏，不影响播放/进度/元数据探测。
  Future.delayed(const Duration(milliseconds: 200), () {
    mdk.setGlobalOption('log', 'warning'); // 想完全安静可改 'off'
  });
}

class _WindowStateListener with WindowListener {
  @override
  void onWindowClose() async {
    await quitApp();
  }
}

class VivyApp extends StatefulWidget {
  final ThemeMode initialThemeMode;
  final ScriptService scriptService;

  const VivyApp({super.key, required this.initialThemeMode, required this.scriptService});

  @override
  State<VivyApp> createState() => _VivyAppState();
}

class _VivyAppState extends State<VivyApp> {
  late ThemeMode _themeMode;
  late GridSettings _gridSettings;
  BackgroundSettings _backgroundSettings = const BackgroundSettings();
  // ignore: unused_field - triggers rebuild on locale change
  late AppLocale _locale;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
    _gridSettings = const GridSettings();
    _locale = AppLocale.system;
    _loadGridSettings();
    _loadBackgroundSettings();
    _loadLocale();
  }

  Future<void> _loadGridSettings() async {
    final gs = await SettingsService.loadGridSettings();
    setState(() => _gridSettings = gs);
  }

  Future<void> _loadBackgroundSettings() async {
    final bg = await SettingsService.loadBackgroundSettings();
    setState(() => _backgroundSettings = bg);
  }

  Future<void> _loadLocale() async {
    final locale = await SettingsService.loadLocale();
    Strings.setLocale(locale);
    setState(() => _locale = locale);
  }

  void _onThemeChanged(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  void _onGridSettingsChanged(GridSettings settings) {
    setState(() => _gridSettings = settings);
    // 实时落盘，使新建的快捷面板每次改动立即持久化（不再依赖设置页"应用"）。
    SettingsService.saveGridSettings(settings);
  }

  void _onBackgroundChanged(BackgroundSettings settings) {
    setState(() => _backgroundSettings = settings);
  }

  void _onLocaleChanged(AppLocale locale) {
    Strings.setLocale(locale);
    SettingsService.saveLocale(locale);
    setState(() => _locale = locale);
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
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
      ),
      themeMode: _themeMode,
      home: ShellPage(
        scriptService: widget.scriptService,
        onThemeChanged: _onThemeChanged,
        onGridSettingsChanged: _onGridSettingsChanged,
        gridSettings: _gridSettings,
        backgroundSettings: _backgroundSettings,
        onBackgroundChanged: _onBackgroundChanged,
        onLocaleChanged: _onLocaleChanged,
      ),
    );
  }
}
