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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vivy Library',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
          surface: const Color(0xFF1A1E20),
        ).copyWith(
          surfaceContainerLow: const Color(0xFF212628),
          surfaceContainer: const Color(0xFF282D2F),
          surfaceContainerHigh: const Color(0xFF33383A),
          surfaceContainerHighest: const Color(0xFF3E4345),
          primaryContainer: const Color(0xFF1E2740),
          onPrimaryContainer: const Color(0xFFC9CFFF),
        ),
        useMaterial3: true,
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
