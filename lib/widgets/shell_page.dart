import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
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
import 'compact_level.dart';
import '../utils/app_quit.dart';

class ShellPage extends StatefulWidget {
  final void Function(ThemeMode mode) onThemeChanged;
  final void Function(GridSettings settings) onGridSettingsChanged;
  final GridSettings gridSettings;
  final BackgroundSettings backgroundSettings;
  final void Function(BackgroundSettings settings) onBackgroundChanged;

  const ShellPage({
    super.key,
    required this.onThemeChanged,
    required this.onGridSettingsChanged,
    required this.gridSettings,
    required this.backgroundSettings,
    required this.onBackgroundChanged,
  });

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> with WindowListener {
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

  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initLibrary();
    _state.init();
    _initLayout();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureWindowOnScreen());
  }

  /// 启动后检查窗口是否在可见屏幕范围内。
  /// 防止换显示器后（如 4K→1080p）窗口位置在屏幕外导致看不见。
  Future<void> _ensureWindowOnScreen() async {
    try {
      final display = View.of(context).display;
      final screenW = display.size.width / display.devicePixelRatio;
      final screenH = display.size.height / display.devicePixelRatio;
      final pos = await windowManager.getPosition();
      final size = await windowManager.getSize();
      // 窗口与主屏完全无交集 → 移到默认位置
      if (pos.dx >= screenW || pos.dy >= screenH ||
          pos.dx + size.width <= 0 || pos.dy + size.height <= 0) {
        await windowManager.setPosition(const Offset(10, 10));
      }
    } catch (_) {}
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
          libraryRootPath: _state.currentRootPath,
          onThemeChanged: widget.onThemeChanged,
          onGridSettingsChanged: widget.onGridSettingsChanged,
          backgroundSettings: widget.backgroundSettings,
          onBackgroundChanged: widget.onBackgroundChanged,
        ),
      ),
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _leftPanelWidth.dispose();
    _rightPanelWidth.dispose();
    _filePanelHeight.dispose();
    _state.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = widget.backgroundSettings;
    final hasBg = bg.path != null;
    return CompactLevel(
      level: widget.gridSettings.compactLevel,
      child: Scaffold(
        body: Stack(
          children: [
            if (hasBg)
              Positioned.fill(
                child: Image.file(
                  File(bg.path!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Column(
              children: [
                _buildTitleBar(cs),
                Expanded(
                  child: ListenableBuilder(
                    listenable: _state,
                    builder: (context, _) => _buildBody(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(ColorScheme cs) {
    final c = CompactLevel.of(context);
    return Container(
      height: 30 * c,
      color: cs.surfaceContainerHigh,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Container(
                height: 30 * c,
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.only(left: 12 * c),
                child: Row(
                  children: [
                    Icon(Icons.menu_book, size: 14 * c, color: cs.onSurface),
                    SizedBox(width: 6 * c),
                    Text(
                      'Vivy Library',
                      style: TextStyle(
                        fontSize: 12 * c,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _CaptionButton(
            icon: Icons.horizontal_rule,
            onTap: () => windowManager.minimize(),
            compactLevel: c,
          ),
          _CaptionButton(
            icon: _isMaximized ? Icons.crop_square : Icons.crop_16_9,
            onTap: () {
              if (_isMaximized) {
                windowManager.unmaximize();
              } else {
                windowManager.maximize();
              }
            },
            compactLevel: c,
          ),
          _CaptionButton(
            icon: Icons.close,
            onTap: () => quitApp(),
            isClose: true,
            compactLevel: c,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_state.error != null) {
      return Center(
        child: Text('扫描失败: ${_state.error}',
            style: const TextStyle(color: Colors.red)),
      );
    }
    if (_state.currentRootPath.isEmpty) {
      final c = CompactLevel.of(context);
      return Column(
        children: [
          Container(
            height: 32 * c,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            padding: EdgeInsets.symmetric(horizontal: 12 * c),
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 24 * c,
              child: LibraryRootSelector(
                currentPath: '',
                onRootSelected: _onRootSelected,
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                '请先选择一个资源库目录',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        TopBar(
          state: _state,
          searchController: _searchController,
          onSettingsTap: _openSettings,
          backgroundOpacity: widget.backgroundSettings.path != null
              ? widget.backgroundSettings.middleOpacity
              : 1.0,
        ),
        Expanded(child: _buildMainArea()),
      ],
    );
  }

  Widget _buildMainArea() {
    final cs = Theme.of(context).colorScheme;
    final bg = widget.backgroundSettings;
    final hasBg = bg.path != null;
    final leftAlpha = hasBg ? bg.leftOpacity : 1.0;
    final middleAlpha = hasBg ? bg.middleOpacity : 1.0;
    final rightAlpha = hasBg ? bg.rightOpacity : 1.0;
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
                    padding: const EdgeInsets.all(6),
                    color: cs.surfaceContainerLow.withValues(alpha: leftAlpha),
                    child: LibraryRootSelector(
                      currentPath: _state.currentRootPath,
                      onRootSelected: _onRootSelected,
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant),
                  Expanded(
                    child: CategoryPanel(
                      root: _state.categoryRoot,
                      selectedCategoryPath: _state.selectedCategoryPath,
                      onCategorySelected: _state.setSelectedCategory,
                      expandedPaths: _state.expandedPaths,
                      onToggleExpand: _state.toggleExpand,
                      backgroundOpacity: leftAlpha,
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
                subDirs: _state.currentSubDirs,
                files: _state.currentDirectFiles,
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
                onFolderEditRequest: (folder) {
                  showDialog(
                    context: context,
                    builder: (_) => EditDialog(
                      targets: const [],
                      isBatch: false,
                      state: _state,
                      folderTargets: [folder],
                    ),
                  );
                },
                onFolderBatchEditRequest: (folders) {
                  showDialog(
                    context: context,
                    builder: (_) => EditDialog(
                      targets: const [],
                      isBatch: true,
                      state: _state,
                      folderTargets: folders,
                    ),
                  );
                },
                gridSettings: widget.gridSettings,
                middleOpacity: middleAlpha,
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
              child: DetailPanel(
                item: _state.selectedItem,
                folder: _state.selectedFolder,
                backgroundOpacity: rightAlpha,
                onGotoTap: (entry) async {
                  bool ok;
                  if (entry.path != null && entry.path!.isNotEmpty) {
                    if (_state.selectedItem == null) return;
                    ok = await _state.selectByGotoPath(
                        _state.selectedItem!.path, entry.path!);
                  } else {
                    ok = _state.selectByUuid(entry.uuid);
                  }
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('找不到目标项目'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
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
          width: 5,
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

class _CaptionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;
  final double compactLevel;

  const _CaptionButton({
    required this.icon,
    required this.onTap,
    this.isClose = false,
    this.compactLevel = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 46 * compactLevel,
      height: 30 * compactLevel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          color: Colors.transparent,
          child: Center(
            child: Icon(icon, size: 12 * compactLevel, color: isClose ? Colors.red.shade300 : cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
