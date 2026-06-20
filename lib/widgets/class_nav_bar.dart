import 'package:flutter/material.dart';
import '../providers/library_state.dart';

/// 顶部 class 导航栏:漂浮在网格区域上方的标签条,自动换行,最多约三行,
/// 超出时可纵向滚动。颜色融入网格背景,不做独立分栏的视觉处理。
class ClassNavBar extends StatelessWidget {
  final LibraryState state;

  const ClassNavBar({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final options = state.classNavOptions;

    return Container(
      constraints: const BoxConstraints(maxHeight: 84),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      color: Colors.transparent,
      width: double.infinity, // 撑满父级宽度,确保 Wrap 是从最左边开始排列
      child: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft, // 显式声明整体内容靠左上角对齐
          child: Wrap(
            alignment: WrapAlignment.start, // 每一行内部也靠左排列
            spacing: 6,
            runSpacing: 6,
            children: options
                .map((entry) => _buildChip(entry.key, entry.value))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, int count) {
    final isSelected = state.selectedClass == label;

    return InkWell(
      onTap: () => state.setSelectedClass(label),
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0078D4)
              : const Color(0xFFE0E0E0).withOpacity(0.6), // 半透明,更融入背景
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 11.5,
            color: isSelected ? Colors.white : const Color(0xFF333333),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}