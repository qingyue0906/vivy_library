import 'package:flutter/material.dart';
import '../services/script_service.dart';
import 'smooth_scroll.dart';

class ScriptResultDialog extends StatelessWidget {
  final ScriptResult result;

  const ScriptResultDialog({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      title: Text('脚本: ${result.scriptName}', style: const TextStyle(fontSize: 14)),
      content: SizedBox(
        width: 500,
        child: SmoothScroll(
          builder: (context, controller, physics) => ListView(
            controller: controller,
            physics: physics,
            shrinkWrap: true,
            children: [
              for (final output in result.outputs) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    output,
                    style: TextStyle(fontSize: 12, color: cs.onSurface, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
