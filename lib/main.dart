import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'services/settings_service.dart';
import 'widgets/shell_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final savedTheme = await SettingsService.loadThemeMode();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    final saved = await SettingsService.loadWindowState();
    await windowManager.setPosition(Offset(saved.dx, saved.dy));
    await windowManager.setSize(Size(saved.width, saved.height));
    await windowManager.setPreventClose(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    windowManager.addListener(_WindowStateListener());
  }

  runApp(VivyApp(initialThemeMode: savedTheme));
}

class _WindowStateListener with WindowListener {
  @override
  void onWindowClose() async {
    final pos = await windowManager.getPosition();
    final size = await windowManager.getSize();
    await SettingsService.saveWindowState(WindowState(
      dx: pos.dx,
      dy: pos.dy,
      width: size.width,
      height: size.height,
    ));
    await windowManager.destroy();
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

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
    _gridSettings = const GridSettings();
    _loadGridSettings();
  }

  Future<void> _loadGridSettings() async {
    final gs = await SettingsService.loadGridSettings();
    setState(() => _gridSettings = gs);
  }

  void _onThemeChanged(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  void _onGridSettingsChanged(GridSettings settings) {
    setState(() => _gridSettings = settings);
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
        onThemeChanged: _onThemeChanged,
        onGridSettingsChanged: _onGridSettingsChanged,
        gridSettings: _gridSettings,
      ),
    );
  }
}
