// 应用入口的最小 smoke test：确认 VivyApp 能正常构建一帧。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vivy_library/main.dart';
import 'package:vivy_library/services/script_service.dart';

void main() {
  testWidgets('VivyApp builds smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(VivyApp(
      initialThemeMode: ThemeMode.light,
      scriptService: ScriptService(),
    ));
    await tester.pump();
  });
}
