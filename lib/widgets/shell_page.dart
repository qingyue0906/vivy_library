import 'package:flutter/material.dart';
import '../providers/library_state.dart';
import 'category_panel.dart';
import 'detail_panel.dart';
import 'grid_area.dart';
import 'top_bar.dart';
import 'edit_dialog.dart';

const String kLibraryRoot = r'E:\Test\vivy_library';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  double _leftPanelWidth = 200;
  double _rightPanelWidth = 280;
  static const double _minPanelWidth = 120;
  static const double _maxPanelWidth = 400;

  double _filePanelHeight = 165;
  static const double _minFilePanelHeight = 80;
  static const double _maxFilePanelHeight = 400;

  // LibraryState 替代了之前分散的 _scanFuture、_selectedCategory、_selectedItem
  final LibraryState _state = LibraryState();

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _state.scan(kLibraryRoot);
  }

  @override
  void dispose() {
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
        SizedBox(
          width: _leftPanelWidth,
          child: CategoryPanel(
            categories: _state.categories,
            selectedCategory: _state.selectedCategory,
            onCategorySelected: _state.setSelectedCategory,
          ),
        ),
        _buildDragHandle(onDrag: _resizeLeftPanel),
        Expanded(
          child: GridArea(
            items: _state.filteredAndSortedItems,
            state: _state,
            filePanelHeight: _filePanelHeight,      // 新增
            onFilePanelResize: _resizeFilePanel,    // 新增
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
          ),
        ),
        _buildDragHandle(onDrag: _resizeRightPanel),
        SizedBox(
          width: _rightPanelWidth,
          child: DetailPanel(item: _state.selectedItem),
        ),
      ],
    );
  }

  Widget _buildDragHandle({required void Function(double) onDrag}) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (details) => onDrag(details.delta.dx),
        child: Container(
          width: 6,
          color: Colors.transparent,
          child: Center(child: Container(width: 1, color: Colors.black26)),
        ),
      ),
    );
  }

  void _resizeLeftPanel(double dx) {
    setState(() {
      _leftPanelWidth =
          (_leftPanelWidth + dx).clamp(_minPanelWidth, _maxPanelWidth);
    });
  }

  void _resizeRightPanel(double dx) {
    setState(() {
      _rightPanelWidth =
          (_rightPanelWidth - dx).clamp(_minPanelWidth, _maxPanelWidth);
    });
  }

  void _resizeFilePanel(double dy) {
    setState(() {
      // 网格的分隔条在文件面板上方,往上拖(dy 为负)应该让面板变高,
      // 所以这里是减去 dy,跟右侧面板"往左拖变宽"的算法是同一个道理
      _filePanelHeight =
          (_filePanelHeight - dy).clamp(_minFilePanelHeight, _maxFilePanelHeight);
    });
  }
}