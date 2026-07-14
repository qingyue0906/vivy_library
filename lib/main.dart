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
import 'theme/app_animations.dart';
import 'theme/app_theme.dart';
import 'utils/app_quit.dart';
import 'widgets/shell_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // pdfrx 在任何 pdfrx 控件/引擎 API 使用前初始化 PDFium native assets（Windows 需开发者模式）。
  await pdfrxFlutterInitialize();


  fvp.registerWith();

  await AppDataService.migrateIfNeeded();

  final savedTheme = await SettingsService.loadThemeMode();
  final savedAppearance = await SettingsService.loadAppearanceSettings();
  // 动效档位是全局静态单一真源，需在构建任何界面前写入。
  AppMotion.level = savedAppearance.motionLevel;

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
    child: VivyApp(
      initialThemeMode: savedTheme,
      initialAppearance: savedAppearance,
      scriptService: scriptService,
    ),
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
  final AppearanceSettings initialAppearance;
  final ScriptService scriptService;

  const VivyApp({
    super.key,
    required this.initialThemeMode,
    required this.initialAppearance,
    required this.scriptService,
  });

  @override
  State<VivyApp> createState() => _VivyAppState();
}

class _VivyAppState extends State<VivyApp> {
  late ThemeMode _themeMode;
  late AppearanceSettings _appearance;
  late GridSettings _gridSettings;
  BackgroundSettings _backgroundSettings = const BackgroundSettings();
  // ignore: unused_field - triggers rebuild on locale change
  late AppLocale _locale;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
    _appearance = widget.initialAppearance;
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

  void _onAppearanceChanged(AppearanceSettings settings) {
    // 动效档位是全局静态单一真源，随外观一并更新。
    AppMotion.level = settings.motionLevel;
    setState(() => _appearance = settings);
    SettingsService.saveAppearanceSettings(settings);
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vivy Library',
      theme: buildAppTheme(
        brightness: Brightness.light,
        appearance: _appearance,
      ),
      darkTheme: buildAppTheme(
        brightness: Brightness.dark,
        appearance: _appearance,
      ),
      themeMode: _themeMode,
      // 全局字号缩放：零侵入地作用于所有文本，无需逐处改 fontSize。
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(_appearance.fontScale),
          ),
          child: child!,
        );
      },
      home: ShellPage(
        scriptService: widget.scriptService,
        onThemeChanged: _onThemeChanged,
        onGridSettingsChanged: _onGridSettingsChanged,
        gridSettings: _gridSettings,
        backgroundSettings: _backgroundSettings,
        onBackgroundChanged: _onBackgroundChanged,
        onLocaleChanged: _onLocaleChanged,
        appearance: _appearance,
        onAppearanceChanged: _onAppearanceChanged,
      ),
    );
  }
}
