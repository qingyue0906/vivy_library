import 'package:flutter/material.dart';

class CompactLevel extends InheritedWidget {
  final double level;

  const CompactLevel({
    super.key,
    required this.level,
    required super.child,
  });

  static double of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<CompactLevel>()
            ?.level ??
        1.0;
  }

  @override
  bool updateShouldNotify(CompactLevel oldWidget) =>
      oldWidget.level != level;
}
