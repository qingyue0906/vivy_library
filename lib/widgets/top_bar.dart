import 'package:flutter/material.dart';
import '../providers/library_state.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import 'compact_level.dart';

class TopBar extends StatelessWidget {
  final LibraryState state;
  final TextEditingController searchController;
  final VoidCallback onSettingsTap;
  final VoidCallback? onGridDisplayTap;
  final GridSettings gridSettings;
  final void Function(GridDisplayMode mode)? onDisplayModeChanged;
  final double backgroundOpacity;

  const TopBar({
    super.key,
    required this.state,
    required this.searchController,
    required this.onSettingsTap,
    this.onGridDisplayTap,
    required this.gridSettings,
    this.onDisplayModeChanged,
    this.backgroundOpacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 40 * c,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: backgroundOpacity),
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8 * c),
      child: Row(
        children: [
          _ToolButton(
            icon: Icons.settings_outlined,
            tooltip: Strings.t('settingsTooltip'),
            onTap: onSettingsTap,
            c: c,
          ),
          SizedBox(width: 4 * c),
          // 面包屑（可横向滚动，逐级可点回）。
          Expanded(child: _Breadcrumb(state: state, c: c)),
          SizedBox(width: 8 * c),
          // 搜索框
          SizedBox(
            width: 240 * c,
            child: _SearchField(
              state: state,
              controller: searchController,
              c: c,
            ),
          ),
          SizedBox(width: 8 * c),
          if (onDisplayModeChanged != null)
            _ViewModeSwitch(
              current: gridSettings.displayMode,
              onChanged: onDisplayModeChanged!,
              c: c,
            ),
          SizedBox(width: 6 * c),
          _buildSortFieldDropdown(context, c),
          SizedBox(width: 2 * c),
          _buildSortOrderButton(context, c),
          SizedBox(width: 2 * c),
          _ToolButton(
            icon: Icons.refresh,
            tooltip: Strings.t('refreshTooltip'),
            onTap: () => state.rescan(),
            c: c,
          ),
          if (onGridDisplayTap != null) ...[
            SizedBox(width: 2 * c),
            _ToolButton(
              icon: Icons.tune,
              tooltip: Strings.t('gridDisplaySettings'),
              onTap: onGridDisplayTap!,
              c: c,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSortFieldDropdown(BuildContext context, double c) {
    final cs = Theme.of(context).colorScheme;
    final metrics = context.metrics;
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
        offset: Offset(0, 30 * c),
        color: cs.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: metrics.brSmall,
          side: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
        constraints: BoxConstraints(minWidth: 120 * c, maxWidth: 180 * c),
        itemBuilder: (_) => [
          for (final e in labels.entries)
            PopupMenuItem<String>(
              value: e.key.name,
              height: 34 * c,
              child: Row(
                children: [
                  Icon(
                    e.key == state.sortField
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 15 * c,
                    color: e.key == state.sortField
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
                  SizedBox(width: 8 * c),
                  Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 12 * c,
                      color: e.key == state.sortField ? cs.primary : cs.onSurface,
                      fontWeight: e.key == state.sortField
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          const PopupMenuDivider(height: 1),
          PopupMenuItem<String>(
            height: 34 * c,
            padding: EdgeInsets.zero,
            child: StatefulBuilder(
              builder: (ctx, setMenuState) => Row(
                children: [
                  SizedBox(width: 12 * c),
                  Icon(Icons.workspaces_outline,
                      size: 15 * c, color: cs.onSurfaceVariant),
                  SizedBox(width: 8 * c),
                  Text(Strings.t('grouping'),
                      style: TextStyle(fontSize: 12 * c, color: cs.onSurface)),
                  const Spacer(),
                  SizedBox(
                    height: 22 * c,
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
                  SizedBox(width: 10 * c),
                ],
              ),
            ),
          ),
        ],
        child: Container(
          height: 28 * c,
          padding: EdgeInsets.symmetric(horizontal: 10 * c),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: metrics.brSmall,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sort, size: 15 * c, color: cs.onSurfaceVariant),
              SizedBox(width: 5 * c),
              Text(
                labels[state.sortField] ?? '',
                style: TextStyle(fontSize: 12 * c, color: cs.onSurface),
              ),
              Icon(Icons.arrow_drop_down, size: 16 * c, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortOrderButton(BuildContext context, double c) {
    final isAsc = state.sortOrder == SortOrder.ascending;
    return _ToolButton(
      icon: isAsc ? Icons.arrow_upward : Icons.arrow_downward,
      tooltip: isAsc ? Strings.t('sortAsc') : Strings.t('sortDesc'),
      onTap: state.toggleSortOrder,
      c: c,
    );
  }
}

/// 统一样式的工具栏图标按钮：hover 圆角高亮。
class _ToolButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double c;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.c,
  });

  @override
  State<_ToolButton> createState() => _ToolButtonState();
}

class _ToolButtonState extends State<_ToolButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final metrics = context.metrics;
    final c = widget.c;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppMotion.durFast,
            width: 28 * c,
            height: 28 * c,
            decoration: BoxDecoration(
              color: _hover
                  ? cs.onSurface.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: metrics.brSmall,
            ),
            child: Icon(widget.icon, size: 16 * c, color: cs.onSurface),
          ),
        ),
      ),
    );
  }
}

/// 焦点感知的圆角搜索框：聚焦时描边强调色 + 焦点环。
class _SearchField extends StatefulWidget {
  final LibraryState state;
  final TextEditingController controller;
  final double c;

  const _SearchField({
    required this.state,
    required this.controller,
    required this.c,
  });

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final metrics = context.metrics;
    final c = widget.c;
    final state = widget.state;
    return AnimatedContainer(
      duration: AppMotion.durFast,
      curve: AppMotion.standard,
      height: 28 * c,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: _focused ? 0.7 : 0.45),
        borderRadius: metrics.brPill,
        border: Border.all(
          color: _focused ? cs.primary : Colors.transparent,
          width: 1.4,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.22),
                  blurRadius: 8,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          SizedBox(width: 10 * c),
          Icon(Icons.search,
              size: 15 * c,
              color: _focused ? cs.primary : cs.onSurfaceVariant),
          SizedBox(width: 6 * c),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              style: TextStyle(color: cs.onSurface, fontSize: 12 * c),
              cursorColor: cs.primary,
              decoration: InputDecoration(
                isDense: true,
                isCollapsed: true,
                border: InputBorder.none,
                hintText: Strings.t('searchHint'),
                hintStyle:
                    TextStyle(color: cs.onSurfaceVariant, fontSize: 12 * c),
              ),
              onChanged: state.setSearchQuery,
            ),
          ),
          if (state.searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                state.setSearchQuery('');
                widget.controller.clear();
              },
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8 * c),
                child: Icon(Icons.close,
                    size: 14 * c, color: cs.onSurfaceVariant),
              ),
            )
          else
            SizedBox(width: 10 * c),
        ],
      ),
    );
  }
}

/// 视图模式切换：紧凑的分段控件（松散网格 / 紧凑网格 / 列表 / 封面 / 自适应）。
class _ViewModeSwitch extends StatelessWidget {
  final GridDisplayMode current;
  final void Function(GridDisplayMode) onChanged;
  final double c;

  const _ViewModeSwitch({
    required this.current,
    required this.onChanged,
    required this.c,
  });

  static const _modes = <GridDisplayMode, (IconData, String)>{
    GridDisplayMode.loose: (Icons.grid_view_rounded, 'loose'),
    GridDisplayMode.compact: (Icons.apps_rounded, 'compact'),
    GridDisplayMode.list: (Icons.view_list_rounded, 'list'),
    GridDisplayMode.cover: (Icons.view_agenda_outlined, 'cover'),
    GridDisplayMode.adaptive: (Icons.auto_awesome_mosaic_outlined, 'adaptive'),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final metrics = context.metrics;
    return Container(
      height: 28 * c,
      padding: EdgeInsets.all(2 * c),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: metrics.brPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in _modes.entries)
            _ViewModeButton(
              icon: e.value.$1,
              selected: current == e.key,
              onTap: () => onChanged(e.key),
              c: c,
            ),
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final double c;

  const _ViewModeButton({
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.durFast,
        curve: AppMotion.standard,
        width: 26 * c,
        height: 24 * c,
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(
          icon,
          size: 15 * c,
          color: selected ? cs.onPrimary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 分类面包屑：根 › 子 › 孙，逐级可点回。
class _Breadcrumb extends StatelessWidget {
  final LibraryState state;
  final double c;

  const _Breadcrumb({required this.state, required this.c});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final root = state.currentRootPath.replaceAll('\\', '/');
    final selected = state.selectedCategoryPath?.replaceAll('\\', '/');

    // 组装层级：始终以"全部"开头。
    final crumbs = <_CrumbData>[
      _CrumbData(label: Strings.t('allItems'), path: null, isAll: true),
    ];
    if (selected != null && selected.isNotEmpty) {
      final rootName = root.split('/').where((s) => s.isNotEmpty).isNotEmpty
          ? root.split('/').lastWhere((s) => s.isNotEmpty)
          : root;
      if (selected == root) {
        crumbs.add(_CrumbData(label: rootName, path: root, isAll: false));
      } else if (selected.startsWith('$root/')) {
        final rel = selected.substring(root.length + 1);
        final parts = rel.split('/').where((s) => s.isNotEmpty).toList();
        crumbs.add(_CrumbData(label: rootName, path: root, isAll: false));
        var acc = root;
        for (final p in parts) {
          acc = '$acc/$p';
          crumbs.add(_CrumbData(label: p, path: acc, isAll: false));
        }
      } else {
        // 路径不在当前根下（异常情况）：直接显示末段。
        final name = selected.split('/').lastWhere((s) => s.isNotEmpty,
            orElse: () => selected);
        crumbs.add(_CrumbData(label: name, path: selected, isAll: false));
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: [
          for (var i = 0; i < crumbs.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 1 * c),
                child: Icon(Icons.chevron_right,
                    size: 15 * c, color: cs.onSurfaceVariant),
              ),
            _CrumbChip(
              data: crumbs[i],
              isLast: i == crumbs.length - 1,
              onTap: () => state.setSelectedCategory(crumbs[i].path),
              c: c,
            ),
          ],
        ],
      ),
    );
  }
}

class _CrumbData {
  final String label;
  final String? path;
  final bool isAll;
  _CrumbData({required this.label, required this.path, required this.isAll});
}

class _CrumbChip extends StatefulWidget {
  final _CrumbData data;
  final bool isLast;
  final VoidCallback onTap;
  final double c;

  const _CrumbChip({
    required this.data,
    required this.isLast,
    required this.onTap,
    required this.c,
  });

  @override
  State<_CrumbChip> createState() => _CrumbChipState();
}

class _CrumbChipState extends State<_CrumbChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final metrics = context.metrics;
    final c = widget.c;
    final last = widget.isLast;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.durFast,
          padding: EdgeInsets.symmetric(horizontal: 8 * c, vertical: 4 * c),
          decoration: BoxDecoration(
            color: last
                ? cs.primaryContainer.withValues(alpha: 0.55)
                : (_hover
                    ? cs.onSurface.withValues(alpha: 0.06)
                    : Colors.transparent),
            borderRadius: metrics.brSmall,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.data.isAll)
                Padding(
                  padding: EdgeInsets.only(right: 4 * c),
                  child: Icon(Icons.apps_rounded,
                      size: 13 * c,
                      color: last ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                ),
              Text(
                widget.data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12 * c,
                  fontWeight: last ? FontWeight.w600 : FontWeight.w400,
                  color: last ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
