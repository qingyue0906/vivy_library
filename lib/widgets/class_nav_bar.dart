import 'package:flutter/material.dart';
import '../providers/library_state.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import '../theme/design_tokens.dart';
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
    final tokens = AppDesignTokens.of(context);

    return GestureDetector(
      onSecondaryTapUp: (details) => _showSourceMenu(context, details.globalPosition),
      child: Container(
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
                  .map((entry) => _buildChip(entry.key, entry.value, cs, c, tokens))
                  .toList(),
            ),
          ),
        ),
      ),
    ),
    );
  }

  void _showSourceMenu(BuildContext context, Offset globalPos) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1),
      items: [
        for (final source in ClassSource.values)
          PopupMenuItem(
            value: source.name,
            height: 28,
            child: Row(children: [
              if (state.classSource == source) ...[
                Icon(Icons.check, size: 14, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
              ],
              Text(_sourceLabel(source), style: const TextStyle(fontSize: 12)),
            ]),
          ),
      ],
    ).then((value) {
      if (value == null) return;
      final source = ClassSource.values.firstWhere((s) => s.name == value);
      state.setClassSource(source);
    });
  }

  String _sourceLabel(ClassSource source) {
    switch (source) {
      case ClassSource.creator: return Strings.t('classSourceCreator');
      case ClassSource.type: return Strings.t('classSourceType');
      case ClassSource.contentrating: return Strings.t('classSourceContentrating');
      case ClassSource.rating: return Strings.t('classSourceRating');
      case ClassSource.class_: return Strings.t('classSourceClass');
      case ClassSource.tags: return Strings.t('classSourceTags');
    }
  }

  Widget _buildChip(String label, int count, ColorScheme cs, double c, AppDesignTokens tokens) {
    final isSelected = state.selectedClass == label;
    final displayLabel = switch (label) {
      LibraryState.kAllClass => Strings.t('allClass'),
      LibraryState.kUnclassified => Strings.t('unclassified'),
      _ => label,
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => state.setSelectedClass(label),
        child: AnimatedContainer(
          duration: tokens.duration(MotionDurations.fast),
          curve: MotionCurves.standard,
          padding: EdgeInsets.symmetric(horizontal: 12 * c, vertical: 5 * c),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primary
                : (cs.brightness == Brightness.light
                    ? Colors.white.withValues(alpha: 0.8)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(20 * c),
            border: Border.all(
              color: isSelected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.3),
                      blurRadius: 6 * c,
                    ),
                  ]
                : const [],
          ),
          child: Text(
            '$displayLabel ($count)',
            style: TextStyle(
              fontSize: 11 * c,
              color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
