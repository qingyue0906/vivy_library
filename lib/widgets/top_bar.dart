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
      height: 32,
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.settings, size: 14, color: cs.onSurface),
            tooltip: '设置',
            onPressed: onSettingsTap,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          const SizedBox(width: 8),
          Expanded(child: _buildSearchField(context)),
          const SizedBox(width: 6),
          _buildSortFieldDropdown(),
          const SizedBox(width: 2),
          _buildSortOrderButton(),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 22,
      child: TextField(
        controller: searchController,
        style: TextStyle(color: cs.onSurface, fontSize: 11),
        decoration: InputDecoration(
          hintText: '搜索...',
          hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
          prefixIcon: Icon(Icons.search, size: 12, color: cs.onSurfaceVariant),
          isDense: true,
          filled: true,
          fillColor: cs.brightness == Brightness.light ? Colors.white : cs.surfaceContainer,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: cs.outlineVariant, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: cs.outlineVariant, width: 1),
          ),
          suffixIcon: state.searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 12, color: cs.onSurfaceVariant),
                  onPressed: () {
                    state.setSearchQuery('');
                    searchController.clear();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                )
              : null,
        ),
        onChanged: state.setSearchQuery,
      ),
    );
  }

  Widget _buildSortFieldDropdown() {
    return SizedBox(
      height: 22,
      child: DropdownButton<SortField>(
        value: state.sortField,
        isDense: true,
        underline: const SizedBox.shrink(),
        style: const TextStyle(fontSize: 11),
        items: const [
          DropdownMenuItem(value: SortField.name, child: Text('名称', style: TextStyle(fontSize: 11))),
          DropdownMenuItem(value: SortField.size, child: Text('大小', style: TextStyle(fontSize: 11))),
          DropdownMenuItem(value: SortField.date, child: Text('日期', style: TextStyle(fontSize: 11))),
        ],
        onChanged: (field) {
          if (field != null) state.setSortField(field);
        },
      ),
    );
  }

  Widget _buildSortOrderButton() {
    final isAsc = state.sortOrder == SortOrder.ascending;
    return IconButton(
      tooltip: isAsc ? '当前:升序' : '当前:降序',
      icon: Icon(
        isAsc ? Icons.arrow_upward : Icons.arrow_downward,
        size: 12,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      onPressed: state.toggleSortOrder,
    );
  }
}
