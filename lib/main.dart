import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'services/settings_service.dart';
import 'widgets/shell_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    final saved = await SettingsService.loadWindowState();
    await windowManager.setPosition(Offset(saved.dx, saved.dy));
    await windowManager.setSize(Size(saved.width, saved.height));
    await windowManager.setPreventClose(true);

    windowManager.addListener(_WindowStateListener());
  }

  runApp(const VivyApp());
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

class VivyApp extends StatelessWidget {
  const VivyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vivy Library',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ShellPage(),
    );
  }
}
