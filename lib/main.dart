import 'package:flutter/material.dart';
import 'widgets/shell_page.dart';

void main() {
  runApp(const VivyApp());
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