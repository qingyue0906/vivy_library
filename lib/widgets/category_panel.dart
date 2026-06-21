import 'package:flutter/material.dart';

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
    return Material(
      color: cs.surface,
      child: ListView(
        children: [
          _buildItem(context, label: '全部', value: null),
          Divider(height: 1, color: cs.outlineVariant),
          ...categories.map((cat) => _buildItem(context, label: cat, value: cat)),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, {required String label, required String? value}) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = selectedCategory == value;
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: cs.primaryContainer.withValues(alpha: 0.4),
      selectedColor: cs.primary,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      onTap: () => onCategorySelected(value),
    );
  }
}
