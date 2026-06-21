import 'package:flutter/material.dart';
import '../providers/library_state.dart';

class ClassNavBar extends StatelessWidget {
  final LibraryState state;

  const ClassNavBar({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final options = state.classNavOptions;
    final cs = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxHeight: 60),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      color: Colors.transparent,
      width: double.infinity,
      child: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: Wrap(
            alignment: WrapAlignment.start,
            spacing: 4,
            runSpacing: 4,
            children: options
                .map((entry) => _buildChip(entry.key, entry.value, cs))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, int count, ColorScheme cs) {
    final isSelected = state.selectedClass == label;

    return InkWell(
      onTap: () => state.setSelectedClass(label),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: 0.5,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 10,
            color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
