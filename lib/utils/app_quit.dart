import 'dart:io';
import 'package:window_manager/window_manager.dart';
import '../services/settings_service.dart';

/// 统一的应用退出函数。
///
/// 1. 最小化时不保存当前位置（Windows 最小化窗口 GetWindowRect 返回 -32000，
///    会污染持久化状态导致下次启动窗口在屏幕外）。
/// 2. 用 exit(0) 立即终止进程，替代 windowManager.destroy()（后者只
///    PostQuitMessage(0)，要等消息循环退出，表现为"卡住过一会才关"）。
Future<void> quitApp() async {
  if (!await windowManager.isMinimized()) {
    final pos = await windowManager.getPosition();
    final size = await windowManager.getSize();
    await SettingsService.saveWindowState(WindowState(
      dx: pos.dx,
      dy: pos.dy,
      width: size.width,
      height: size.height,
    ));
  }
  exit(0);
}
