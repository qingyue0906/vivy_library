import 'package:flutter/material.dart';
import '../providers/library_state.dart';
import 'category_panel.dart';
import 'detail_panel.dart';
import 'grid_area.dart';
import 'top_bar.dart';
import 'edit_dialog.dart';
import '../services/library_root_service.dart';
import '../services/settings_service.dart';
import 'library_root_selector.dart';
import 'settings_page.dart';
import 'dart:io';

class ShellPage extends StatefulWidget {
  final void Function(ThemeMode mode) onThemeChanged;
  final void Function(GridSettings settings) onGridSettingsChanged;
  final GridSettings gridSettings;

  const ShellPage({
    super.key,
    required this.onThemeChanged,
    required this.onGridSettingsChanged,
    required this.gridSettings,
  });

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  final ValueNotifier<double> _leftPanelWidth = ValueNotifier(200);
  final ValueNotifier<double> _rightPanelWidth = ValueNotifier(280);
  static const double _minPanelWidth = 120;
  static const double _maxPanelWidth = 400;

  final ValueNotifier<double> _filePanelHeight = ValueNotifier(165);
  static const double _minFilePanelHeight = 80;
  static const double _maxFilePanelHeight = 400;

  final LibraryState _state = LibraryState();

  final TextEditingController _searchController = TextEditingController();

  final LibraryRootService _rootService = LibraryRootService();

  @override
  void initState() {
    super.initState();
    _initLibrary();
    _state.init();
    _initLayout();
  }

  Future<void> _initLibrary() async {
    final lastPath = await _rootService.getCurrentRootPath();
    if (lastPath != null && Directory(lastPath).existsSync()) {
      await _state.scan(lastPath);
    } else {
      _state.markNoLibrarySelected();
    }
  }

  Future<void> _initLayout() async {
    final layout = await SettingsService.loadLayout();
    _leftPanelWidth.value = layout.leftPanelWidth;
    _rightPanelWidth.value = layout.rightPanelWidth;
    _filePanelHeight.value = layout.filePanelHeight;
  }

  Future<void> _onRootSelected(String path) async {
    await _rootService.setCurrentRootPath(path);
    await _state.scan(path);
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          onThemeChanged: widget.onThemeChanged,
          onGridSettingsChanged: widget.onGridSettingsChanged,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _leftPanelWidth.dispose();
    _rightPanelWidth.dispose();
    _filePanelHeight.dispose();
    _state.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        if (_state.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (_state.error != null) {
          return Scaffold(
            body: Center(
              child: Text('扫描失败: ${_state.error}',
                  style: const TextStyle(color: Colors.red)),
            ),
          );
        }
        if (_state.currentRootPath.isEmpty) {
          return Scaffold(
            body: Column(
              children: [
                Container(
                  height: 56,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: LibraryRootSelector(
                    currentPath: '',
                    onRootSelected: _onRootSelected,
                  ),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      '请先选择一个资源库目录',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          body: Column(
            children: [
              TopBar(
                state: _state,
                searchController: _searchController,
                onSettingsTap: _openSettings,
              ),
              Expanded(child: _buildMainArea()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainArea() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        ValueListenableBuilder<double>(
          valueListenable: _leftPanelWidth,
          builder: (context, width, _) {
            return SizedBox(
              width: width,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: cs.surfaceContainerLow,
                    child: LibraryRootSelector(
                      currentPath: _state.currentRootPath,
                      onRootSelected: _onRootSelected,
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant),
                  Expanded(
                    child: CategoryPanel(
                      categories: _state.categories,
                      selectedCategory: _state.selectedCategory,
                      onCategorySelected: _state.setSelectedCategory,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        _buildDragHandle(onDrag: _resizeLeftPanel, onDragEnd: _saveLayout),
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: _filePanelHeight,
            builder: (context, fileHeight, _) {
              return GridArea(
                items: _state.filteredAndSortedItems,
                state: _state,
                filePanelHeight: fileHeight,
                onFilePanelResize: _resizeFilePanel,
                onFilePanelResizeEnd: _saveLayout,
                onEditRequest: (targets, isBatch) {
                  showDialog(
                    context: context,
                    builder: (_) => EditDialog(
                      targets: targets,
                      isBatch: isBatch,
                      state: _state,
                    ),
                  );
                },
                gridSettings: widget.gridSettings,
              );
            },
          ),
        ),
        _buildDragHandle(onDrag: _resizeRightPanel, onDragEnd: _saveLayout),
        ValueListenableBuilder<double>(
          valueListenable: _rightPanelWidth,
          builder: (context, width, _) {
            return SizedBox(
              width: width,
              child: DetailPanel(item: _state.selectedItem),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDragHandle({
    required void Function(double) onDrag,
    VoidCallback? onDragEnd,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (details) => onDrag(details.delta.dx),
        onPanEnd: (_) => onDragEnd?.call(),
        child: Container(
          width: 6,
          color: Colors.transparent,
        ),
      ),
    );
  }

  void _resizeLeftPanel(double dx) {
    _leftPanelWidth.value =
        (_leftPanelWidth.value + dx).clamp(_minPanelWidth, _maxPanelWidth);
  }

  void _resizeRightPanel(double dx) {
    _rightPanelWidth.value =
        (_rightPanelWidth.value - dx).clamp(_minPanelWidth, _maxPanelWidth);
  }

  void _resizeFilePanel(double dy) {
    _filePanelHeight.value =
        (_filePanelHeight.value - dy).clamp(_minFilePanelHeight, _maxFilePanelHeight);
  }

  void _saveLayout() {
    SettingsService.saveLayout(LayoutState(
      leftPanelWidth: _leftPanelWidth.value,
      rightPanelWidth: _rightPanelWidth.value,
      filePanelHeight: _filePanelHeight.value,
    ));
  }
}
