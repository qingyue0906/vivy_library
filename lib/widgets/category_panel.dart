import 'package:flutter/material.dart';

class CategoryPanel extends StatelessWidget {
  final List<String> categories;    // 所有分类名列表,由父级传入
  final String? selectedCategory;   // 当前选中的分类,null 表示"全部"
  final void Function(String?) onCategorySelected; // 回调:用户点了某个分类

  const CategoryPanel({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade50,
      child: ListView(
        children: [
          _buildItem(label: '全部', value: null),
          const Divider(height: 1),
          ...categories.map((cat) => _buildItem(label: cat, value: cat)),
        ],
      ),
    );
  }

  Widget _buildItem({required String label, required String? value}) {
    final isSelected = selectedCategory == value;
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: Colors.deepPurple.shade50,
      selectedColor: Colors.deepPurple,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      onTap: () => onCategorySelected(value),
    );
  }
}