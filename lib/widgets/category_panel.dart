import 'package:flutter/material.dart';
import 'compact_level.dart';

class CategoryPanel extends StatelessWidget {
  final List<String> categories;
  final String? selectedCategory;
  final void Function(String?) onCategorySelected;

  const CategoryPanel({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = CompactLevel.of(context);
    return Material(
      color: cs.surfaceContainerLow,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildItem(context, c, label: '全部', value: null),
          ...categories.map((cat) => _buildItem(context, c, label: cat, value: cat)),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, double c,
      {required String label, required String? value}) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = selectedCategory == value;
    return Container(
      height: 28 * c,
      color: isSelected ? cs.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: () => onCategorySelected(value),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12 * c),
          child: Align(
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12 * c,
                color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
