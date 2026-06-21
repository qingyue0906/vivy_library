import 'package:flutter/material.dart';
import '../providers/library_state.dart';

class TopBar extends StatelessWidget {
  final LibraryState state;
  final TextEditingController searchController;
  final VoidCallback onSettingsTap;

  const TopBar({
    super.key,
    required this.state,
    required this.searchController,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      color: cs.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.settings, size: 18, color: cs.onPrimaryContainer),
            tooltip: '设置',
            onPressed: onSettingsTap,
          ),
          Text(
            'Vivy Library',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: _buildSearchField(context)),
          const SizedBox(width: 12),
          _buildSortFieldDropdown(),
          const SizedBox(width: 6),
          _buildSortOrderButton(),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: searchController,
      style: TextStyle(color: cs.onSurface, fontSize: 13),
      decoration: InputDecoration(
        hintText: '搜索标题、描述、标签...',
        hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        prefixIcon: Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
        isDense: true,
        filled: true,
        fillColor: cs.brightness == Brightness.light ? Colors.white : cs.surfaceContainerHighest,
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
                  searchController.clear();
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
      underline: const SizedBox.shrink(),
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
