import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../services/translations.dart';

/// 播放器独立设置界面（与主程序设置无关）。覆盖在播放器之上，
/// 顶部为可拖拽标题栏（含返回按钮），右上角可放置窗口控制控件。
class PlayerSettingsPage extends StatelessWidget {
  final bool showMilliseconds;
  final ValueChanged<bool> onMillisecondsChanged;
  final bool useExternalAudio;
  final ValueChanged<bool> onExternalAudioChanged;
  final VoidCallback onBack;
  final Widget? trailing;

  const PlayerSettingsPage({
    super.key,
    required this.showMilliseconds,
    required this.onMillisecondsChanged,
    this.useExternalAudio = true,
    this.onExternalAudioChanged = _noop,
    required this.onBack,
    this.trailing,
  });

  static void _noop(bool _) {}

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          Container(
            height: 32,
            color: cs.surfaceContainerHigh,
            child: Row(
              children: [
                Expanded(
                  child: DragToMoveArea(
                    child: Container(
                      height: 32,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 12),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: onBack,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(Icons.arrow_back,
                                  size: 16, color: cs.onSurfaceVariant),
                            ),
                          ),
                          Icon(Icons.play_circle_outline,
                              size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Text(
                            Strings.t('playerSettings'),
                            style: TextStyle(fontSize: 13, color: cs.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildSwitchRow(
                  cs,
                  title: Strings.t('showMilliseconds'),
                  desc: Strings.t('showMillisecondsDesc'),
                  value: showMilliseconds,
                  onChanged: onMillisecondsChanged,
                ),
                const SizedBox(height: 16),
                _buildSwitchRow(
                  cs,
                  title: Strings.t('useExternalAudio'),
                  desc: Strings.t('useExternalAudioDesc'),
                  value: useExternalAudio,
                  onChanged: onExternalAudioChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(
    ColorScheme cs, {
    required String title,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(desc,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        Transform.scale(
          scale: 0.85,
          child: Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}
