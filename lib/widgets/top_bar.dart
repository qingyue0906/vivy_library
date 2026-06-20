import 'package:flutter/material.dart';
import '../providers/library_state.dart';

class TopBar extends StatelessWidget {
  final LibraryState state;

  final TextEditingController searchController;

  const TopBar({super.key, required this.state, required this.searchController});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: Colors.deepPurple.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // App 名称
          const Text(
            'Vivy Library',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),

          // 搜索框,占满剩余空间
          Expanded(child: _buildSearchField()),
          const SizedBox(width: 12),

          // 排序字段下拉
          _buildSortFieldDropdown(),
          const SizedBox(width: 6),

          // 升序/降序切换按钮
          _buildSortOrderButton(),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: searchController, // 新增这一行
      decoration: InputDecoration(
        hintText: '搜索标题、描述、标签...',
        prefixIcon: const Icon(Icons.search, size: 18),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        suffixIcon: state.searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  state.setSearchQuery('');
                  searchController.clear(); // 同步清空 TextField 显示的文字
                },
              )
            : null,
      ),
      onChanged: state.setSearchQuery,
    );
  }

  Widget _buildSortFieldDropdown() {
    return DropdownButton<SortField>(
      value: state.sortField,
      isDense: true,
      underline: const SizedBox.shrink(), // 去掉默认下划线
      items: const [
        DropdownMenuItem(value: SortField.name, child: Text('名称')),
        DropdownMenuItem(value: SortField.size, child: Text('大小')),
        DropdownMenuItem(value: SortField.date, child: Text('日期')),
      ],
      onChanged: (field) {
        if (field != null) state.setSortField(field);
      },
    );
  }

  Widget _buildSortOrderButton() {
    final isAsc = state.sortOrder == SortOrder.ascending;
    return IconButton(
      tooltip: isAsc ? '当前:升序' : '当前:降序',
      icon: Icon(
        isAsc ? Icons.arrow_upward : Icons.arrow_downward,
        size: 18,
      ),
      onPressed: state.toggleSortOrder,
    );
  }
}