import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import 'compact_level.dart';

/// 网格显示快捷面板：显示模式（5 选 1）、每行数目滑块、徽章开关。
/// 每个控件改动即实时回调 [onChanged]（外部负责 setState + 持久化），
/// 因此面板内不持有"应用"按钮，改动即时预览并落盘。
class GridDisplaySettingsPanel extends StatefulWidget {
  final GridSettings initial;
  final ValueChanged<GridSettings> onChanged;

  const GridDisplaySettingsPanel({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<GridDisplaySettingsPanel> createState() =>
      _GridDisplaySettingsPanelState();
}

class _GridDisplaySettingsPanelState extends State<GridDisplaySettingsPanel> {
  late GridSettings _gs;

  static const Map<GridDisplayMode, String> _modes = {
    GridDisplayMode.loose: 'modeLoose',
    GridDisplayMode.compact: 'modeCompact',
    GridDisplayMode.list: 'modeList',
    GridDisplayMode.cover: 'modeCover',
    GridDisplayMode.adaptive: 'modeAdaptive',
  };

  static const Map<GridBadge, String> _badges = {
    GridBadge.star: 'badgeStar',
    GridBadge.type: 'badgeType',
    GridBadge.rating: 'badgeRating',
  };

  @override
  void initState() {
    super.initState();
    _gs = widget.initial;
  }

  void _update(GridSettings next) {
    _gs = next;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(Strings.t('gridDisplaySettings')),
      content: SizedBox(
        width: 320 * c,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Strings.t('displayMode'),
                style: TextStyle(fontSize: 12 * c, color: cs.onSurfaceVariant),
              ),
              SizedBox(height: 6 * c),
              Wrap(
                spacing: 6 * c,
                runSpacing: 6 * c,
                children: [
                  for (final e in _modes.entries)
                    Builder(
                      builder: (context) {
                        final selected = _gs.displayMode == e.key;
                        return ChoiceChip(
                          label: Text(
                            Strings.t(e.value),
                            style: TextStyle(
                              fontSize: 11 * c,
                              color: selected ? cs.onPrimary : cs.onSurface,
                            ),
                          ),
                          selected: selected,
                          selectedColor: cs.primary,
                          onSelected: (_) =>
                              _update(_gs.copyWith(displayMode: e.key)),
                        );
                      },
                    ),
                ],
              ),
              SizedBox(height: 14 * c),
              Text(
                Strings.t('itemsPerRowCount'),
                style: TextStyle(fontSize: 12 * c, color: cs.onSurfaceVariant),
              ),
              SizedBox(height: 2 * c),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 12,
                      divisions: 12,
                      label: _gs.itemsPerRow == 0
                          ? Strings.t('auto')
                          : '${_gs.itemsPerRow}',
                      value: _gs.itemsPerRow.toDouble(),
                      onChanged: (v) =>
                          _update(_gs.copyWith(itemsPerRow: v.round())),
                    ),
                  ),
                  SizedBox(width: 8 * c),
                  SizedBox(
                    width: 44 * c,
                    child: Text(
                      _gs.itemsPerRow == 0
                          ? Strings.t('auto')
                          : '${_gs.itemsPerRow}',
                      style: TextStyle(fontSize: 11 * c),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14 * c),
              Text(
                Strings.t('badgeSettings'),
                style: TextStyle(fontSize: 12 * c, color: cs.onSurfaceVariant),
              ),
              SizedBox(height: 2 * c),
              for (final e in _badges.entries)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 1 * c),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        Strings.t(e.value),
                        style: TextStyle(fontSize: 11 * c),
                      ),
                      Transform.scale(
                        scale: 0.75,
                        child: Switch(
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          value: _gs.badges.isEnabled(e.key),
                          onChanged: (v) => _update(
                            _gs.copyWith(badges: _gs.badges.toggle(e.key, v)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(Strings.t('close')),
        ),
      ],
    );
  }
}
