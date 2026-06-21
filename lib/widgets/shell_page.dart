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
import 'dart:io';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

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

  // LibraryState 替代了之前分散的 _scanFuture、_selectedCategory、_selectedItem
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

  /// 启动时尝试恢复上次使用的资源库,没有记录则不自动扫描,
  /// 等待用户通过左侧的资源库选择器手动打开一个
  Future<void> _initLibrary() async {
    final lastPath = await _rootService.getCurrentRootPath();
    if (lastPath != null && Directory(lastPath).existsSync()) {
      await _state.scan(lastPath);
    } else {
      // 没有可恢复的资源库,标记加载结束,显示"请选择资源库"的提示界面
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
    await _rootService.setCurrentRootPath(path); // 记住这次选择,下次启动直接用
    await _state.scan(path);
  }

  @override
  void dispose() {
    _leftPanelWidth.dispose();
    _rightPanelWidth.dispose();
    _filePanelHeight.dispose();
    // StatefulWidget 被销毁时释放资源,对应 Python 里 __del__ 或 closeEvent 里的清理。
    // ChangeNotifier 持有监听者列表,不 dispose 会内存泄漏。
    _state.dispose();
    _searchController.dispose(); // controller 也需要手动释放
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder:监听 _state,_state 调用 notifyListeners() 时
    // 自动重新执行 builder 函数重建 UI。
    // 对应 PySide6 里把信号 connect 到一个"刷新整个界面"的槽函数。
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
        // 没有资源库时,只显示顶部资源库选择器,中间引导用户选择
        if (_state.currentRootPath.isEmpty) {
          return Scaffold(
            body: Column(
              children: [
                Container(
                  height: 56,
                  color: Colors.deepPurple.shade100,
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
              TopBar(state: _state, searchController: _searchController),
              Expanded(child: _buildMainArea()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainArea() {
    return Row(
      children: [
        // 左面板：仅尺寸变化时重建
        ValueListenableBuilder<double>(
          valueListenable: _leftPanelWidth,
          builder: (context, width, _) {
            return SizedBox(
              width: width,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.grey.shade50,
                    child: LibraryRootSelector(
                      currentPath: _state.currentRootPath,
                      onRootSelected: _onRootSelected,
                    ),
                  ),
                  const Divider(height: 1),
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
        // 中间网格 + 文件面板：仅文件面板高度变化时重建
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
              );
            },
          ),
        ),
        _buildDragHandle(onDrag: _resizeRightPanel, onDragEnd: _saveLayout),
        // 右面板：仅尺寸变化时重建
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
          child: Center(child: Container(width: 1, color: Colors.black26)),
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