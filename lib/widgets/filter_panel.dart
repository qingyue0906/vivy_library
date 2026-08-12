import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import '../utils/type_visuals.dart';
import 'compact_level.dart';

/// 内容筛选面板（分级 + 类型白名单，类似 wallpaper engine）。
/// 每个选项是「要显示」的勾选；空白名单 = 该维度什么都不显示。
/// 改动即实时回调 [onChanged]（外部负责 setState + 持久化）。
class FilterPanel extends StatefulWidget {
  final ItemFilter initial;
  final ValueChanged<ItemFilter> onChanged;

  const FilterPanel({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  late ItemFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initial;
  }

  void _update(ItemFilter next) {
    setState(() => _filter = next);
    widget.onChanged(next);
  }

  Set<String> _toggle(Set<String> set, String value, bool selected) {
    final updated = Set<String>.from(set);
    if (selected) {
      updated.add(value);
    } else {
      updated.remove(value);
    }
    return updated;
  }

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    return AlertDialog(
      title: Text(Strings.t('contentFilter')),
      content: SizedBox(
        width: 360 * c,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                Strings.t('ratingSection'),
                onSelectAll: () => _update(ItemFilter(
                  types: _filter.types,
                  ratings: {...ItemFilter.presetRatings, ItemFilter.otherSentinel},
                )),
                onClear: () => _update(ItemFilter(
                  types: _filter.types,
                  ratings: const {},
                )),
              ),
              SizedBox(height: 6 * c),
              Wrap(
                spacing: 6 * c,
                runSpacing: 6 * c,
                children: [
                  for (final r in ItemFilter.presetRatings)
                    _buildChip(
                      label: r,
                      selected: _filter.ratings.contains(r),
                      onTap: (v) => _update(ItemFilter(
                        types: _filter.types,
                        ratings: _toggle(_filter.ratings, r, v),
                      )),
                    ),
                  _buildChip(
                    label: Strings.t('otherOption'),
                    selected: _filter.ratings.contains(ItemFilter.otherSentinel),
                    onTap: (v) => _update(ItemFilter(
                      types: _filter.types,
                      ratings: _toggle(
                          _filter.ratings, ItemFilter.otherSentinel, v),
                    )),
                  ),
                ],
              ),
              SizedBox(height: 14 * c),
              _buildSectionHeader(
                Strings.t('typeSection'),
                onSelectAll: () => _update(ItemFilter(
                  types: {...ItemFilter.presetTypes, ItemFilter.otherSentinel},
                  ratings: _filter.ratings,
                )),
                onClear: () => _update(ItemFilter(
                  types: const {},
                  ratings: _filter.ratings,
                )),
              ),
              SizedBox(height: 6 * c),
              Wrap(
                spacing: 6 * c,
                runSpacing: 6 * c,
                children: [
                  for (final t in ItemFilter.presetTypes)
                    _buildChip(
                      label: t,
                      icon: typeIcon(t),
                      iconColor: typeColor(t),
                      selected: _filter.types.contains(t),
                      onTap: (v) => _update(ItemFilter(
                        types: _toggle(_filter.types, t, v),
                        ratings: _filter.ratings,
                      )),
                    ),
                  _buildChip(
                    label: Strings.t('otherOption'),
                    selected: _filter.types.contains(ItemFilter.otherSentinel),
                    onTap: (v) => _update(ItemFilter(
                      types: _toggle(
                          _filter.types, ItemFilter.otherSentinel, v),
                      ratings: _filter.ratings,
                    )),
                  ),
                ],
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

  Widget _buildSectionHeader(
    String title, {
    required VoidCallback onSelectAll,
    required VoidCallback onClear,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12 * CompactLevel.of(context),
            color: cs.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: onSelectAll,
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: EdgeInsets.symmetric(horizontal: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            Strings.t('selectAll'),
            style: TextStyle(
                fontSize: 11 * CompactLevel.of(context), color: cs.primary),
          ),
        ),
        TextButton(
          onPressed: onClear,
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: EdgeInsets.symmetric(horizontal: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            Strings.t('clearAll'),
            style: TextStyle(
                fontSize: 11 * CompactLevel.of(context), color: cs.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onTap,
    IconData? icon,
    Color? iconColor,
  }) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11 * c,
          color: selected ? cs.onPrimary : cs.onSurface,
        ),
      ),
      avatar: icon == null
          ? null
          : Icon(icon, size: 14 * c, color: selected ? cs.onPrimary : iconColor),
      selected: selected,
      selectedColor: cs.primary,
      checkmarkColor: cs.onPrimary,
      showCheckmark: false,
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant,
        width: 0.5,
      ),
      onSelected: onTap,
    );
  }
}
