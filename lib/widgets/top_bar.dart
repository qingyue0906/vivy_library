import 'package:flutter/material.dart';
import '../providers/library_state.dart';
import '../services/translations.dart';
import '../theme/design_tokens.dart';
import 'compact_level.dart';

class TopBar extends StatelessWidget {
  final LibraryState state;
  final TextEditingController searchController;
  final VoidCallback onSettingsTap;
  final VoidCallback? onGridDisplayTap;
  final double backgroundOpacity;

  const TopBar({
    super.key,
    required this.state,
    required this.searchController,
    required this.onSettingsTap,
    this.onGridDisplayTap,
    this.backgroundOpacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 38 * c,
      color: cs.surfaceContainerLow.withValues(alpha: backgroundOpacity),
      padding: EdgeInsets.symmetric(horizontal: 10 * c, vertical: 3 * c),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.settings, size: 16 * c, color: cs.onSurfaceVariant),
            tooltip: Strings.t('settingsTooltip'),
            onPressed: onSettingsTap,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 28 * c, minHeight: 28 * c),
          ),
          SizedBox(width: 8 * c),
          Expanded(child: _buildSearchField(context, c)),
          SizedBox(width: 8 * c),
          _buildSortFieldDropdown(context, c),
          SizedBox(width: 4 * c),
          _buildSortOrderButton(c),
          SizedBox(width: 2 * c),
          _buildRefreshButton(c),
          SizedBox(width: 2 * c),
          _buildGridDisplayButton(c),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    final tokens = AppDesignTokens.of(context);
    return SizedBox(
      height: 28 * c,
      child: TextField(
        controller: searchController,
        style: TextStyle(color: cs.onSurface, fontSize: 12 * c),
        decoration: InputDecoration(
          hintText: Strings.t('searchHint'),
          hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 12 * c),
          prefixIcon: Icon(Icons.search, size: 15 * c, color: cs.onSurfaceVariant),
          prefixIconConstraints: BoxConstraints(minWidth: 30 * c),
          isDense: true,
          filled: true,
          fillColor: cs.brightness == Brightness.light
              ? Colors.white.withValues(alpha: 0.7)
              : cs.surfaceContainerHigh,
          contentPadding: EdgeInsets.symmetric(horizontal: 8 * c, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.inputRadius * c),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.inputRadius * c),
            borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.inputRadius * c),
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
          suffixIcon: state.searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 14 * c, color: cs.onSurfaceVariant),
                  onPressed: () {
                    state.setSearchQuery('');
                    searchController.clear();
                  },
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 24 * c, minHeight: 24 * c),
                )
              : null,
        ),
        onChanged: state.setSearchQuery,
      ),
    );
  }

  Widget _buildSortFieldDropdown(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    final tokens = AppDesignTokens.of(context);
    final labels = {
      SortField.name: Strings.t('sortName'),
      SortField.size: Strings.t('sortSize'),
      SortField.date: Strings.t('sortDate'),
    };
    return SizedBox(
      height: 28 * c,
      child: PopupMenuButton<String>(
        tooltip: Strings.t('sortMethod'),
        initialValue: state.sortField.name,
        onSelected: (val) {
          final f = SortField.values.firstWhere((e) => e.name == val);
          state.setSortField(f);
        },
        offset: const Offset(0, 30),
        constraints: BoxConstraints(minWidth: 70 * c, maxWidth: 140 * c),
        itemBuilder: (_) => [
          for (final e in labels.entries)
            PopupMenuItem<String>(
              value: e.key.name,
              height: 30 * c,
              child: Text(
                e.value,
                style: TextStyle(
                  fontSize: 11.5 * c,
                  color: e.key == state.sortField ? cs.primary : cs.onSurface,
                  fontWeight: e.key == state.sortField ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          PopupMenuDivider(height: 1),
          PopupMenuItem<String>(
            height: 30 * c,
            padding: EdgeInsets.zero,
            child: StatefulBuilder(
              builder: (ctx, setMenuState) => Row(
                children: [
                  const SizedBox(width: 12),
                  Text(Strings.t('grouping'), style: TextStyle(fontSize: 11.5 * c, color: cs.onSurface)),
                  const Spacer(),
                  SizedBox(
                    height: 18 * c,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Switch(
                        value: state.groupingEnabled,
                        onChanged: (v) {
                          state.setGroupingEnabled(v);
                          setMenuState(() {});
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ],
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8 * c, vertical: 2 * c),
          decoration: BoxDecoration(
            color: cs.brightness == Brightness.light
                ? Colors.white.withValues(alpha: 0.7)
                : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(tokens.inputRadius * c),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labels[state.sortField] ?? '',
                style: TextStyle(fontSize: 11.5 * c, color: cs.onSurface),
              ),
              Icon(Icons.arrow_drop_down, size: 16 * c, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortOrderButton(double c) {
    final isAsc = state.sortOrder == SortOrder.ascending;
    return IconButton(
      tooltip: isAsc ? Strings.t('sortAsc') : Strings.t('sortDesc'),
      icon: Icon(
        isAsc ? Icons.arrow_upward : Icons.arrow_downward,
        size: 15 * c,
      ),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: 28 * c, minHeight: 28 * c),
      onPressed: state.toggleSortOrder,
    );
  }

  Widget _buildRefreshButton(double c) {
    return IconButton(
      tooltip: Strings.t('refreshTooltip'),
      icon: Icon(Icons.refresh, size: 16 * c),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: 28 * c, minHeight: 28 * c),
      onPressed: () => state.rescan(),
    );
  }

  Widget _buildGridDisplayButton(double c) {
    if (onGridDisplayTap == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: Strings.t('gridDisplaySettings'),
      icon: Icon(Icons.view_module, size: 16 * c),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: 28 * c, minHeight: 28 * c),
      onPressed: onGridDisplayTap,
    );
  }
}
