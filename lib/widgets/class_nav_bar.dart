import 'package:flutter/material.dart';
import '../providers/library_state.dart';
import '../services/translations.dart';
import 'compact_level.dart';
import 'smooth_scroll.dart';

class ClassNavBar extends StatelessWidget {
  final LibraryState state;

  const ClassNavBar({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final options = state.classNavOptions;
    final cs = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(maxHeight: 60 * c),
      padding: EdgeInsets.fromLTRB(8 * c, 6 * c, 8 * c, 2 * c),
      color: Colors.transparent,
      width: double.infinity,
      child: SmoothScroll(
        scrollSpeed: 0.5,
        builder: (context, controller, physics) => SingleChildScrollView(
          controller: controller,
          physics: physics,
          child: Align(
            alignment: Alignment.topLeft,
            child: Wrap(
              alignment: WrapAlignment.start,
              spacing: 4 * c,
              runSpacing: 4 * c,
              children: options
                  .map((entry) => _buildChip(entry.key, entry.value, cs, c))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, int count, ColorScheme cs, double c) {
    final isSelected = state.selectedClass == label;
    final displayLabel = switch (label) {
      LibraryState.kAllClass => Strings.t('allClass'),
      LibraryState.kUnclassified => Strings.t('unclassified'),
      _ => label,
    };
    final chipBg = isSelected
        ? cs.primary
        : (cs.brightness == Brightness.light ? Colors.white : cs.surfaceContainer);

    return InkWell(
      onTap: () => state.setSelectedClass(label),
      borderRadius: BorderRadius.circular(3 * c),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8 * c, vertical: 3 * c),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(3 * c),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: 0.5,
          ),
        ),
        child: Text(
          '$displayLabel ($count)',
          style: TextStyle(
            fontSize: 10 * c,
            color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
