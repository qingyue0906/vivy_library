import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/library_state.dart';
import '../models/library_item.dart';
import '../widgets/video_player_page.dart';
import '../services/video_playlist_service.dart';
import '../widgets/audio_player_page.dart';
import '../services/audio_playlist_service.dart';
import '../widgets/comic_reader_page.dart';
import '../services/comic_playlist_service.dart';
import '../widgets/ebook_reader_page.dart';
import '../services/ebook_playlist_service.dart';
import 'category_panel.dart';
import 'detail_panel.dart';
import 'grid_area.dart';
import 'top_bar.dart';
import 'grid_display_settings_panel.dart';
import 'edit_dialog.dart';
import 'create_item_dialog.dart';
import '../services/library_root_service.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import 'library_root_selector.dart';
import 'settings_page.dart';
import 'dart:io';
import 'compact_level.dart';
import '../services/script_service.dart';
import '../utils/app_quit.dart';

class ShellPage extends StatefulWidget {
  final ScriptService scriptService;
  final void Function(ThemeMode mode) onThemeChanged;
  final void Function(Color? color) onAccentChanged;
  final void Function(GridSettings settings) onGridSettingsChanged;
  final GridSettings gridSettings;
  final BackgroundSettings backgroundSettings;
  final void Function(BackgroundSettings settings) onBackgroundChanged;
  final void Function(AppLocale locale) onLocaleChanged;

  const ShellPage({
    super.key,
    required this.scriptService,
    required this.onThemeChanged,
    required this.onAccentChanged,
    required this.onGridSettingsChanged,
    required this.gridSettings,
    required this.backgroundSettings,
    required this.onBackgroundChanged,
    required this.onLocaleChanged,
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
  bool _createDialogShowing = false;

  /// 最近一次"正常窗口"的尺寸与位置（最大化期间不更新，用于退出全屏/重启后恢复）。
  WindowState _lastNormal = const WindowState(dx: 10, dy: 10, width: 1280, height: 720);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    SettingsService.loadWindowState().then((s) {
      _lastNormal = s.copyWith(isMaximized: false);
      // 启动时若上次为全屏，使内存状态与实际窗口一致
      if (s.isMaximized) {
        setState(() => _isMaximized = true);
        // 以正常窗口打开后，首帧再切换为全屏，绕过 window_manager 在启动期
        // maximize 会被原生 runner 的 ShowWindow(SW_SHOWNORMAL) 还原的问题。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 60), () {
            if (mounted) windowManager.maximize();
          });
        });
      }
    });
    _initLibrary();
    _state.init();
    _initLayout();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureWindowOnScreen());
  }

  /// 启动后检查窗口是否在可见屏幕范围内。
  /// 防止换显示器后（如 4K→1080p）窗口位置在屏幕外导致看不见。
  Future<void> _ensureWindowOnScreen() async {
    try {
      // 全屏（最大化）时不 reposition，避免 setPosition 使窗口退回窗口化
      if (await windowManager.isMaximized()) return;
      if (!mounted) return;
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
          scriptService: widget.scriptService,
          onThemeChanged: widget.onThemeChanged,
          onAccentChanged: widget.onAccentChanged,
          onGridSettingsChanged: widget.onGridSettingsChanged,
          backgroundSettings: widget.backgroundSettings,
          onBackgroundChanged: widget.onBackgroundChanged,
          onLocaleChanged: widget.onLocaleChanged,
          onSearchScopeChanged: _state.setSearchScope,
          searchScope: _state.searchScope,
        ),
      ),
    );
  }

  void _openGridDisplaySettings() {
    showDialog(
      context: context,
      builder: (_) => GridDisplaySettingsPanel(
        initial: widget.gridSettings,
        onChanged: widget.onGridSettingsChanged,
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
    // 仅记录全屏标志，保留上一次正常窗口尺寸（不写入全屏尺寸）
    SettingsService.saveWindowState(_lastNormal.copyWith(isMaximized: true));
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
    // 退出全屏后回到上次正常尺寸，更新并保存
    _updateLastNormal().then((_) => SettingsService.saveWindowState(_lastNormal));
  }

  @override
  void onWindowResize() {
    if (!_isMaximized) _updateLastNormal();
  }

  @override
  void onWindowMove() {
    if (!_isMaximized) _updateLastNormal();
  }

  /// 记录当前（非全屏）窗口尺寸到内存，供退出全屏/重启后恢复。
  Future<void> _updateLastNormal() async {
    if (_isMaximized) return;
    final pos = await windowManager.getPosition();
    final size = await windowManager.getSize();
    _lastNormal = WindowState(
      dx: pos.dx,
      dy: pos.dy,
      width: size.width,
      height: size.height,
    );
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
                ListenableBuilder(
                  listenable: _state,
                  builder: (context, _) {
                    if (_state.copyProgress < 0) return const SizedBox.shrink();
                    final cs = Theme.of(context).colorScheme;
                    return Container(
                      height: 24,
                      color: cs.surfaceContainerHigh,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 160,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: LinearProgressIndicator(value: _state.copyProgress >= 1.0 ? null : _state.copyProgress),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _state.copyStatus,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: _state.copyProgress >= 1.0 ? Colors.green : cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
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
        child: Text(Strings.tn('scanFailed', {'error': '${_state.error}'}),
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
          Expanded(
            child: Center(
              child: Text(
                Strings.t('selectLibraryFirst'),
                style: const TextStyle(color: Colors.grey, fontSize: 13),
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
          onGridDisplayTap: _openGridDisplaySettings,
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
                subDirs: _state.filteredSubDirs,
                files: _state.filteredDirectFiles,
                state: _state,
                scriptService: widget.scriptService,
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
                onCreateItem: () {
                  if (_createDialogShowing) return;
                  _createDialogShowing = true;
                  _state.setModalDropActive(true);
                  showDialog(
                    context: context,
                    builder: (_) => CreateItemDialog(
                      state: _state,
                      defaultParentPath: _state.selectedCategoryPath,
                    ),
                  ).whenComplete(() {
                    _createDialogShowing = false;
                    _state.setModalDropActive(false);
                  });
                },
                onFileDrop: (paths) {
                  if (_createDialogShowing) return;
                  _createDialogShowing = true;
                  _state.setModalDropActive(true);
                  final first = paths.first.replaceAll('\\', '/').split('/').last;
                  final title = first.contains('.') ? first.substring(0, first.lastIndexOf('.')) : first;
                  showDialog(
                    context: context,
                    builder: (_) => CreateItemDialog(
                      state: _state,
                      defaultParentPath: _state.selectedCategoryPath,
                      prefilledTitle: title,
                      prefilledImportPaths: paths,
                    ),
                  ).whenComplete(() {
                    _createDialogShowing = false;
                    _state.setModalDropActive(false);
                  });
                },
                onOpenVideoPlayer: _openVideoPlayer,
                onOpenAudioPlayer: _openAudioPlayer,
                onOpenComicReader: _openComicReader,
                onOpenEbookReader: _openEbookReader,
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
                effectiveInfo: _state.selectedItem != null
                    ? _state.effectiveInfo(_state.selectedItem!)
                    : null,
                folder: _state.selectedFolder,
                file: _state.selectedFile,
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
                      SnackBar(
                        content: Text(Strings.t('targetNotFound')),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                onSearchByQuery: (query) {
                  _state.setSearchQuery(query);
                  _searchController.text = query;
                  _searchController.selection = TextSelection.collapsed(offset: query.length);
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

  /// 打开内置视频播放器：递归扫描项目内所有视频构建播放列表，
  /// [startPath] 指定从哪个视频开始播放（底部面板双击视频文件时传入）。
  Future<void> _openVideoPlayer(LibraryItem item, {String? startPath}) async {
    final playlist = await VideoPlaylistService.build(item);
    final playlistWidth = await SettingsService.loadPlayerPlaylistWidth();
    // 预加载播放列表/毫秒开关以填充同步缓存，避免播放器首帧按默认闪现后跳变。
    await SettingsService.loadPlayerShowPlaylist();
    await SettingsService.loadPlayerShowMilliseconds();
    if (!mounted) return;
    if (playlist.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Strings.t('noVideoFiles')),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }
    final startIndex = startPath != null
        ? playlist.entries.indexWhere((e) => e.path == startPath)
        : 0;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VideoPlayerPage(
          playlist: playlist,
          initialIndex: startIndex < 0 ? 0 : startIndex,
          title: item.info.title,
          initialPlaylistWidth: playlistWidth,
        ),
      ),
    );
  }

  /// 打开内置音频播放器：递归扫描项目内所有音频构建播放列表，
  /// [startPath] 指定从哪个音频开始播放（底部面板双击音频文件时传入）。
  Future<void> _openAudioPlayer(LibraryItem item, {String? startPath}) async {
    final playlist = await AudioPlaylistService.build(item);
    final playlistWidth = await SettingsService.loadAudioPlaylistWidth();
    // 预加载音频偏好以填充同步缓存，避免首帧按默认闪现后跳变。
    await SettingsService.loadAudioShowPlaylist();
    await SettingsService.loadAudioShowLyrics();
    if (!mounted) return;
    if (playlist.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Strings.t('noAudioFiles')),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }
    final startIndex = startPath != null
        ? playlist.entries.indexWhere((e) => e.path == startPath)
        : 0;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AudioPlayerPage(
          playlist: playlist,
          initialIndex: startIndex < 0 ? 0 : startIndex,
          title: item.info.title,
          initialPlaylistWidth: playlistWidth,
        ),
      ),
    );
  }

  /// 打开内置图片/漫画阅读器：递归扫描项目内所有图片与 zip/cbz 构建阅读列表，
  /// [startPath] 指定从哪张图片/压缩包开始阅读（底部面板双击图片/压缩包时传入）。
  Future<void> _openComicReader(LibraryItem item, {String? startPath}) async {
    final playlist = await ComicPlaylistService.build(item);
    final thumbWidth = await SettingsService.loadReaderThumbnailWidth();
    if (!mounted) return;
    if (playlist.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Strings.t('noComicFiles')),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }
    var startIndex = 0;
    if (startPath != null) {
      final norm = startPath.replaceAll('\\', '/').toLowerCase();
      startIndex = playlist.entries.indexWhere((e) {
        if (e.isArchived) {
          return e.archivePath != null &&
              e.archivePath!.replaceAll('\\', '/').toLowerCase() == norm;
        }
        return e.sourcePath != null &&
            e.sourcePath!.replaceAll('\\', '/').toLowerCase() == norm;
      });
      if (startIndex < 0) startIndex = 0;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ComicReaderPage(
          playlist: playlist,
          initialIndex: startIndex,
          title: item.info.title,
          initialThumbnailWidth: thumbWidth,
        ),
      ),
    );
  }

  /// 打开内置电子书阅读器：递归扫描项目内所有 txt/epub/pdf/md 构建书列表，
  /// [startPath] 指定从哪本书开始阅读（底部面板双击电子书文件时传入）。
  Future<void> _openEbookReader(LibraryItem item, {String? startPath}) async {
    final playlist = await EbookPlaylistService.build(item);
    // 预加载阅读设置以填充同步缓存，避免首帧按默认值闪现后跳变。
    await SettingsService.loadEbookReadMode();
    await SettingsService.loadEbookFontSize();
    await SettingsService.loadEbookLineHeight();
    await SettingsService.loadEbookFontFamily();
    await SettingsService.loadEbookTheme();
    await SettingsService.loadEbookPageMargin();
    await SettingsService.loadEbookJustify();
    await SettingsService.loadEbookShowToc();
    await SettingsService.loadEbookTocWidth();
    if (!mounted) return;
    if (playlist.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Strings.t('noEbookFiles')),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }
    var startIndex = 0;
    if (startPath != null) {
      final norm = startPath.replaceAll('\\', '/').toLowerCase();
      startIndex = playlist.entries
          .indexWhere((e) => e.replaceAll('\\', '/').toLowerCase() == norm);
      if (startIndex < 0) startIndex = 0;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => EbookReaderPage(
          playlist: playlist,
          initialIndex: startIndex,
          title: item.info.title,
        ),
      ),
    );
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
