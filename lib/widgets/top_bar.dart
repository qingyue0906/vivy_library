import 'package:flutter/material.dart';
import '../providers/library_state.dart';
import 'compact_level.dart';

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
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 32 * c,
      color: cs.surfaceContainerLow,
      padding: EdgeInsets.symmetric(horizontal: 8 * c),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.settings, size: 14 * c, color: cs.onSurface),
            tooltip: '设置',
            onPressed: onSettingsTap,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 24 * c, minHeight: 24 * c),
          ),
          SizedBox(width: 8 * c),
          Expanded(child: _buildSearchField(context, c)),
          SizedBox(width: 6 * c),
          _buildSortFieldDropdown(context, c),
          SizedBox(width: 2 * c),
          _buildSortOrderButton(c),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 22 * c,
      child: TextField(
        controller: searchController,
        style: TextStyle(color: cs.onSurface, fontSize: 11 * c),
        decoration: InputDecoration(
          hintText: '搜索...',
          hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 11 * c),
          prefixIcon: Icon(Icons.search, size: 12 * c, color: cs.onSurfaceVariant),
          isDense: true,
          filled: true,
          fillColor: cs.brightness == Brightness.light ? Colors.white : cs.surfaceContainer,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 6 * c, vertical: 2 * c),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4 * c),
            borderSide: BorderSide(color: cs.outlineVariant, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4 * c),
            borderSide: BorderSide(color: cs.outlineVariant, width: 1),
          ),
          suffixIcon: state.searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 12 * c, color: cs.onSurfaceVariant),
                  onPressed: () {
                    state.setSearchQuery('');
                    searchController.clear();
                  },
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 18 * c, minHeight: 18 * c),
                )
              : null,
        ),
        onChanged: state.setSearchQuery,
      ),
    );
  }

  Widget _buildSortFieldDropdown(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    final labels = {
      SortField.name: '名称',
      SortField.size: '大小',
      SortField.date: '日期',
    };
    return SizedBox(
      height: 22 * c,
      child: PopupMenuButton<SortField>(
        initialValue: state.sortField,
        onSelected: (field) => state.setSortField(field),
        offset: const Offset(0, 24),
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
        itemBuilder: (_) => labels.entries.map((e) {
          final selected = e.key == state.sortField;
          return PopupMenuItem<SortField>(
            value: e.key,
            height: 22 * c,
            child: Text(
              e.value,
              style: TextStyle(
                fontSize: 10 * c,
                color: selected ? cs.primary : cs.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4 * c),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labels[state.sortField] ?? '',
                style: TextStyle(fontSize: 10 * c, color: cs.onSurface),
              ),
              Icon(Icons.arrow_drop_down, size: 14 * c, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortOrderButton(double c) {
    final isAsc = state.sortOrder == SortOrder.ascending;
    return IconButton(
      tooltip: isAsc ? '当前:升序' : '当前:降序',
      icon: Icon(
        isAsc ? Icons.arrow_upward : Icons.arrow_downward,
        size: 12 * c,
      ),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: 22 * c, minHeight: 22 * c),
      onPressed: state.toggleSortOrder,
    );
  }
}
