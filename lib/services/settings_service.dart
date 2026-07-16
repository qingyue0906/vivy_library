import 'package:flutter/material.dart';
import '../providers/library_state.dart';
import 'app_data_service.dart';
import 'translations.dart';

enum ClassSource { creator, type, contentrating, rating, class_, tags }

class SearchScope {
  static const defaultFields = {'title', 'description', 'creator', 'class', 'tags'};
  static const allFields = {'uuid', 'define', 'title', 'description', 'creator', 'type', 'contentrating', 'rating', 'class', 'tags', 'star'};

  final Set<String> enabled;

  const SearchScope({required this.enabled});

  factory SearchScope.defaults() => const SearchScope(enabled: defaultFields);

  bool isEnabled(String field) => enabled.contains(field);

  SearchScope copyWithEnabled(String field, bool value) {
    final updated = Set<String>.from(enabled);
    if (value) { updated.add(field); } else { updated.remove(field); }
    return SearchScope(enabled: updated);
  }

  Map<String, dynamic> toMap() => {
    for (final f in allFields) f: enabled.contains(f),
  };

  factory SearchScope.fromMap(Map<String, dynamic> map) {
    final enabled = <String>{};
    for (final f in allFields) {
      if (map[f] == true) enabled.add(f);
    }
    if (enabled.isEmpty) return SearchScope.defaults();
    return SearchScope(enabled: enabled);
  }
}

class LayoutState {
  final double leftPanelWidth;
  final double rightPanelWidth;
  final double filePanelHeight;

  const LayoutState({
    required this.leftPanelWidth,
    required this.rightPanelWidth,
    required this.filePanelHeight,
  });

  Map<String, double> toMap() => {
        'leftPanelWidth': leftPanelWidth,
        'rightPanelWidth': rightPanelWidth,
        'filePanelHeight': filePanelHeight,
      };

  factory LayoutState.fromMap(Map<String, double?> map) => LayoutState(
        leftPanelWidth: map['leftPanelWidth'] ?? 200,
        rightPanelWidth: map['rightPanelWidth'] ?? 280,
        filePanelHeight: map['filePanelHeight'] ?? 165,
      );
}

class WindowState {
  final double dx;
  final double dy;
  final double width;
  final double height;
  final bool isMaximized;

  const WindowState({
    required this.dx,
    required this.dy,
    required this.width,
    required this.height,
    this.isMaximized = false,
  });

  Map<String, dynamic> toMap() => {
        'dx': dx,
        'dy': dy,
        'width': width,
        'height': height,
        'maximized': isMaximized,
      };

  factory WindowState.fromMap(Map<String, dynamic> map) => WindowState(
        dx: (map['dx'] as num?)?.toDouble() ?? 10,
        dy: (map['dy'] as num?)?.toDouble() ?? 10,
        width: (map['width'] as num?)?.toDouble() ?? 1280,
        height: (map['height'] as num?)?.toDouble() ?? 720,
        isMaximized: map['maximized'] == true,
      );

  WindowState copyWith({
    double? dx,
    double? dy,
    double? width,
    double? height,
    bool? isMaximized,
  }) =>
      WindowState(
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        width: width ?? this.width,
        height: height ?? this.height,
        isMaximized: isMaximized ?? this.isMaximized,
      );
}

enum GifDisplayMode { unlimited, hover, static }

/// 网格显示模式。
enum GridDisplayMode { loose, compact, list, cover, adaptive }

/// 可切换显示的小图标徽章。新增徽章只需在此枚举加项，并在 [GridBadgeFlags]
/// 与设置面板中补充映射即可扩展（如后续加文件数量/浏览次数）。
enum GridBadge { star, type, rating }

/// 控制各徽章是否显示的开关集合（默认全开）。
class GridBadgeFlags {
  final Set<GridBadge> enabled;

  const GridBadgeFlags({
    this.enabled = const {GridBadge.star, GridBadge.type, GridBadge.rating},
  });

  bool isEnabled(GridBadge b) => enabled.contains(b);

  GridBadgeFlags copyWith({Set<GridBadge>? enabled}) =>
      GridBadgeFlags(enabled: enabled ?? this.enabled);

  GridBadgeFlags toggle(GridBadge b, bool value) {
    final next = Set<GridBadge>.from(enabled);
    if (value) {
      next.add(b);
    } else {
      next.remove(b);
    }
    return GridBadgeFlags(enabled: next);
  }

  Map<String, dynamic> toMap() => {
        for (final b in GridBadge.values) b.name: enabled.contains(b),
      };

  /// [map] 为 null 表示从未保存过徽章配置，回退默认全开；
  /// 非空（即便所有徽章都为 false，即用户明确全关）则如实返回，
  /// 避免"关闭全部徽章"的状态被回退成默认全开而丢失持久化。
  factory GridBadgeFlags.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const GridBadgeFlags();
    final enabled = <GridBadge>{};
    for (final b in GridBadge.values) {
      if (map[b.name] == true) enabled.add(b);
    }
    return GridBadgeFlags(enabled: enabled);
  }
}

/// 漫画阅读器页面布局：单页 / 双页 / 垂直滚动(webtoon)。
enum ComicLayoutMode { single, double, vertical }

/// 漫画阅读方向：从左到右 / 从右到左（对单页与双页生效，垂直模式忽略）。
enum ComicReadDirection { ltr, rtl }

/// 漫画适应模式：适应宽度 / 适应高度 / 适应页面 / 原始大小。
enum ComicFitMode { width, height, page, original }

/// 电子书阅读模式：翻页 / 滚动。
enum EbookReadMode { paginated, scroll }

/// 电子书阅读主题：浅色 / 深色 / 护眼( sepia )。
enum EbookTheme { light, dark, sepia }

class GridSettings {
  final double minCardWidth;
  final double maxCardWidth;
  final String aspectRatio; // "1:1", "4:3", "16:9"
  final int itemsPerRow; // 0 = auto
  final double compactLevel; // 0.5~2.0, 1.0 = current baseline
  final GifDisplayMode cardGifMode;
  final GifDisplayMode fileGifMode;
  final GridDisplayMode displayMode;
  final GridBadgeFlags badges;

  double get aspectRatioValue {
    final parts = aspectRatio.split(':');
    if (parts.length == 2) {
      final w = double.tryParse(parts[0]);
      final h = double.tryParse(parts[1]);
      if (w != null && h != null && h > 0) return w / h;
    }
    return 4 / 3;
  }

  const GridSettings({
    this.minCardWidth = 120,
    this.maxCardWidth = 200,
    this.aspectRatio = '4:3',
    this.itemsPerRow = 0,
    this.compactLevel = 1.0,
    this.cardGifMode = GifDisplayMode.hover,
    this.fileGifMode = GifDisplayMode.hover,
    this.displayMode = GridDisplayMode.loose,
    this.badges = const GridBadgeFlags(),
  });

  GridSettings copyWith({
    double? minCardWidth,
    double? maxCardWidth,
    String? aspectRatio,
    int? itemsPerRow,
    double? compactLevel,
    GifDisplayMode? cardGifMode,
    GifDisplayMode? fileGifMode,
    GridDisplayMode? displayMode,
    GridBadgeFlags? badges,
  }) {
    return GridSettings(
      minCardWidth: minCardWidth ?? this.minCardWidth,
      maxCardWidth: maxCardWidth ?? this.maxCardWidth,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      itemsPerRow: itemsPerRow ?? this.itemsPerRow,
      compactLevel: compactLevel ?? this.compactLevel,
      cardGifMode: cardGifMode ?? this.cardGifMode,
      fileGifMode: fileGifMode ?? this.fileGifMode,
      displayMode: displayMode ?? this.displayMode,
      badges: badges ?? this.badges,
    );
  }

  Map<String, dynamic> toMap() => {
        'minCardWidth': minCardWidth,
        'maxCardWidth': maxCardWidth,
        'aspectRatio': aspectRatio,
        'itemsPerRow': itemsPerRow,
        'compactLevel': compactLevel,
        'cardGifMode': cardGifMode.name,
        'fileGifMode': fileGifMode.name,
        'displayMode': displayMode.name,
        'badges': badges.toMap(),
      };

  factory GridSettings.fromMap(Map<String, dynamic> map) {
    final raw = map['badges'];
    final badges = GridBadgeFlags.fromMap(
      raw is Map ? Map<String, dynamic>.from(raw) : null,
    );
    return GridSettings(
      minCardWidth: (map['minCardWidth'] ?? 120).toDouble(),
      maxCardWidth: (map['maxCardWidth'] ?? 200).toDouble(),
      aspectRatio: map['aspectRatio'] ?? '4:3',
      itemsPerRow: map['itemsPerRow'] ?? 0,
      compactLevel: (map['compactLevel'] ?? 1.0).toDouble(),
      cardGifMode: GifDisplayMode.values.firstWhere(
        (e) => e.name == map['cardGifMode'],
        orElse: () => GifDisplayMode.hover,
      ),
      fileGifMode: GifDisplayMode.values.firstWhere(
        (e) => e.name == map['fileGifMode'],
        orElse: () => GifDisplayMode.hover,
      ),
      displayMode: GridDisplayMode.values.firstWhere(
        (e) => e.name == map['displayMode'],
        orElse: () => GridDisplayMode.loose,
      ),
      badges: badges,
    );
  }
}

class BackgroundSettings {
  final String? path;
  final double leftOpacity;
  final double middleOpacity;
  final double rightOpacity;

  const BackgroundSettings({
    this.path,
    this.leftOpacity = 1.0,
    this.middleOpacity = 1.0,
    this.rightOpacity = 1.0,
  });

  BackgroundSettings copyWith({
    String? path,
    bool clearPath = false,
    double? leftOpacity,
    double? middleOpacity,
    double? rightOpacity,
  }) {
    return BackgroundSettings(
      path: clearPath ? null : (path ?? this.path),
      leftOpacity: leftOpacity ?? this.leftOpacity,
      middleOpacity: middleOpacity ?? this.middleOpacity,
      rightOpacity: rightOpacity ?? this.rightOpacity,
    );
  }

  Map<String, dynamic> toMap() => {
        'path': path,
        'leftOpacity': leftOpacity,
        'middleOpacity': middleOpacity,
        'rightOpacity': rightOpacity,
      };

  factory BackgroundSettings.fromMap(Map<String, dynamic> map) => BackgroundSettings(
        path: map['path'] as String?,
        leftOpacity: (map['leftOpacity'] ?? 1.0).toDouble(),
        middleOpacity: (map['middleOpacity'] ?? 1.0).toDouble(),
        rightOpacity: (map['rightOpacity'] ?? 1.0).toDouble(),
      );
}

class SettingsService {
  static const _sortFieldKey = 'sort_field';
  static const _sortOrderKey = 'sort_order';
  static const _layoutPrefix = 'layout_';
  static const _windowPrefix = 'window_';
  static const _themeKey = 'theme_mode';
  static const _accentColorKey = 'accent_color';
  static const _gridPrefix = 'grid_';
  static const _bgPrefix = 'bg_';
  static const _localeKey = 'app_locale';
  static const _pythonPathKey = 'python_path';

  static Future<(SortField, SortOrder)> loadSortPreferences() async {
    final fieldStr = await AppDataService.getString(_sortFieldKey);
    final orderStr = await AppDataService.getString(_sortOrderKey);
    return (
      SortField.values.firstWhere((e) => e.name == fieldStr, orElse: () => SortField.name),
      SortOrder.values.firstWhere((e) => e.name == orderStr, orElse: () => SortOrder.ascending),
    );
  }

  static Future<void> saveSortPreferences(SortField field, SortOrder order) async {
    await AppDataService.setString(_sortFieldKey, field.name);
    await AppDataService.setString(_sortOrderKey, order.name);
  }

  // --- Layout ---

  static Future<LayoutState> loadLayout() async {
    final data = await AppDataService.loadSettings();
    return LayoutState.fromMap({
      'leftPanelWidth': data['${_layoutPrefix}leftPanelWidth'] as double?,
      'rightPanelWidth': data['${_layoutPrefix}rightPanelWidth'] as double?,
      'filePanelHeight': data['${_layoutPrefix}filePanelHeight'] as double?,
    });
  }

  static Future<void> saveLayout(LayoutState state) async {
    final data = await AppDataService.loadSettings();
    for (final entry in state.toMap().entries) {
      data['$_layoutPrefix${entry.key}'] = entry.value;
    }
    await AppDataService.saveSettings(data);
  }

  // --- Window state ---

  static Future<WindowState> loadWindowState() async {
    final data = await AppDataService.loadSettings();
    return WindowState(
      dx: (data['${_windowPrefix}dx'] as num?)?.toDouble() ?? 10,
      dy: (data['${_windowPrefix}dy'] as num?)?.toDouble() ?? 10,
      width: (data['${_windowPrefix}width'] as num?)?.toDouble() ?? 1280,
      height: (data['${_windowPrefix}height'] as num?)?.toDouble() ?? 720,
      isMaximized: data['${_windowPrefix}maximized'] == true,
    );
  }

  static Future<void> saveWindowState(WindowState state) async {
    final data = await AppDataService.loadSettings();
    for (final entry in state.toMap().entries) {
      data['$_windowPrefix${entry.key}'] = entry.value;
    }
    await AppDataService.saveSettings(data);
  }

  // --- Theme ---

  static Future<ThemeMode> loadThemeMode() async {
    final val = await AppDataService.getString(_themeKey);
    return ThemeMode.values.firstWhere((e) => e.name == val, orElse: () => ThemeMode.system);
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    await AppDataService.setString(_themeKey, mode.name);
  }

  // --- Accent color ---
  // 空字符串表示"默认"（不覆盖，亮色=deepPurple，暗色=VS Code 蓝）。

  static Future<Color?> loadAccentColor() async {
    final val = await AppDataService.getString(_accentColorKey);
    if (val == null || val.isEmpty) return null;
    final intVal = int.tryParse(val);
    return intVal == null ? null : Color(intVal);
  }

  static Future<void> saveAccentColor(Color? color) async {
    await AppDataService.setString(_accentColorKey, color?.toARGB32().toString() ?? '');
  }

  // --- Grid/UI settings ---

  static Future<GridSettings> loadGridSettings() async {
    final data = await AppDataService.loadSettings();
    return GridSettings.fromMap({
      'minCardWidth': data['${_gridPrefix}minCardWidth'],
      'maxCardWidth': data['${_gridPrefix}maxCardWidth'],
      'aspectRatio': data['${_gridPrefix}aspectRatio'],
      'itemsPerRow': data['${_gridPrefix}itemsPerRow'],
      'compactLevel': data['${_gridPrefix}compactLevel'],
      'cardGifMode': data['${_gridPrefix}cardGifMode'],
      'fileGifMode': data['${_gridPrefix}fileGifMode'],
      'displayMode': data['${_gridPrefix}displayMode'],
      'badges': data['${_gridPrefix}badges'],
    });
  }

  static Future<void> saveGridSettings(GridSettings settings) async {
    final data = await AppDataService.loadSettings();
    for (final entry in settings.toMap().entries) {
      data['$_gridPrefix${entry.key}'] = entry.value;
    }
    await AppDataService.saveSettings(data);
  }

  // --- Locale ---

  static Future<AppLocale> loadLocale() async {
    final val = await AppDataService.getString(_localeKey);
    return AppLocale.values.firstWhere((e) => e.name == val, orElse: () => AppLocale.system);
  }

  static Future<void> saveLocale(AppLocale locale) async {
    await AppDataService.setString(_localeKey, locale.name);
  }

  // --- Python path ---

  static Future<String> loadPythonPath() async {
    return (await AppDataService.getString(_pythonPathKey)) ?? '';
  }

  static Future<void> savePythonPath(String path) async {
    await AppDataService.setString(_pythonPathKey, path);
  }

  // --- Search scope ---

  static const _searchScopePrefix = 'searchscope_';

  static Future<SearchScope> loadSearchScope() async {
    final data = await AppDataService.loadSettings();
    final map = <String, dynamic>{};
    for (final f in SearchScope.allFields) {
      map[f] = data['$_searchScopePrefix$f'];
    }
    return SearchScope.fromMap(map);
  }

  static Future<void> saveSearchScope(SearchScope scope) async {
    final data = await AppDataService.loadSettings();
    for (final f in SearchScope.allFields) {
      data['$_searchScopePrefix$f'] = scope.isEnabled(f);
    }
    await AppDataService.saveSettings(data);
  }

  // --- Class source ---

  static const _classSourceKey = 'class_source';

  static Future<ClassSource> loadClassSource() async {
    final val = await AppDataService.getString(_classSourceKey);
    return ClassSource.values.firstWhere((e) => e.name == val, orElse: () => ClassSource.class_);
  }

  static Future<void> saveClassSource(ClassSource source) async {
    await AppDataService.setString(_classSourceKey, source.name);
  }

  // --- Player settings ---

  static const _playerShowMsKey = 'player_show_milliseconds';
  static bool _cachedShowMilliseconds = false;
  static bool loadPlayerShowMillisecondsSync() => _cachedShowMilliseconds;

  static Future<bool> loadPlayerShowMilliseconds() async {
    _cachedShowMilliseconds =
        (await AppDataService.getString(_playerShowMsKey)) == 'true';
    return _cachedShowMilliseconds;
  }

  static Future<void> savePlayerShowMilliseconds(bool v) async {
    _cachedShowMilliseconds = v;
    await AppDataService.setString(_playerShowMsKey, v.toString());
  }

  // --- Player playlist panel ---

  static const _playerShowPlaylistKey = 'player_show_playlist';
  static const _playerPlaylistWidthKey = 'player_playlist_width';
  static bool _cachedShowPlaylist = true;
  static bool loadPlayerShowPlaylistSync() => _cachedShowPlaylist;

  static Future<bool> loadPlayerShowPlaylist() async {
    // 默认显示播放列表
    final val = await AppDataService.getString(_playerShowPlaylistKey);
    _cachedShowPlaylist = val == null || val == 'true';
    return _cachedShowPlaylist;
  }

  static Future<void> savePlayerShowPlaylist(bool v) async {
    _cachedShowPlaylist = v;
    await AppDataService.setString(_playerShowPlaylistKey, v.toString());
  }

  static double _cachedPlaylistWidth = 340.0;

  static double loadPlayerPlaylistWidthSync() => _cachedPlaylistWidth;

  static Future<double> loadPlayerPlaylistWidth() async {
    final val = await AppDataService.getString(_playerPlaylistWidthKey);
    final w = double.tryParse(val ?? '');
    _cachedPlaylistWidth = w != null ? w.clamp(220.0, 640.0) : 340.0;
    return _cachedPlaylistWidth;
  }

  static Future<void> savePlayerPlaylistWidth(double w) async {
    _cachedPlaylistWidth = w;
    await AppDataService.setString(_playerPlaylistWidthKey, w.toString());
  }

  // --- Player hardware/software decode ---

  static const _playerHwdecKey = 'player_hwdec';

  /// 默认启用硬件解码。
  static Future<bool> loadPlayerHardwareDecode() async {
    final val = await AppDataService.getString(_playerHwdecKey);
    return val == null || val == 'true';
  }

  static Future<void> savePlayerHardwareDecode(bool v) async {
    await AppDataService.setString(_playerHwdecKey, v.toString());
  }

  // --- Player volume ---

  static const _playerVolumeKey = 'player_volume';
  static const _playerMutedKey = 'player_muted';

  /// 默认音量为 100。
  static Future<double> loadPlayerVolume() async {
    final val = await AppDataService.getString(_playerVolumeKey);
    final v = double.tryParse(val ?? '');
    return v != null ? v.clamp(0, 100) : 100;
  }

  static Future<void> savePlayerVolume(double v) async {
    await AppDataService.setString(_playerVolumeKey, v.toString());
  }

  static Future<bool> loadPlayerMuted() async {
    return (await AppDataService.getString(_playerMutedKey)) == 'true';
  }

  static Future<void> savePlayerMuted(bool v) async {
    await AppDataService.setString(_playerMutedKey, v.toString());
  }

  // --- Audio player settings ---

  // 复用视频播放器的音量与静音持久化（音频与视频共用同一套音量偏好）。
  static Future<double> loadAudioVolume() => loadPlayerVolume();
  static Future<void> saveAudioVolume(double v) => savePlayerVolume(v);
  static Future<bool> loadAudioMuted() => loadPlayerMuted();
  static Future<void> saveAudioMuted(bool v) => savePlayerMuted(v);

  // 播放列表面板显隐与宽度（默认显示）。
  static const _audioShowPlaylistKey = 'audio_show_playlist';
  static const _audioPlaylistWidthKey = 'audio_playlist_width';
  static bool _cachedAudioShowPlaylist = true;
  static double _cachedAudioPlaylistWidth = 340.0;

  static bool loadAudioShowPlaylistSync() => _cachedAudioShowPlaylist;
  static double loadAudioPlaylistWidthSync() => _cachedAudioPlaylistWidth;

  static Future<bool> loadAudioShowPlaylist() async {
    final val = await AppDataService.getString(_audioShowPlaylistKey);
    _cachedAudioShowPlaylist = val == null || val == 'true';
    return _cachedAudioShowPlaylist;
  }

  static Future<void> saveAudioShowPlaylist(bool v) async {
    _cachedAudioShowPlaylist = v;
    await AppDataService.setString(_audioShowPlaylistKey, v.toString());
  }

  static Future<double> loadAudioPlaylistWidth() async {
    final val = await AppDataService.getString(_audioPlaylistWidthKey);
    final w = double.tryParse(val ?? '');
    _cachedAudioPlaylistWidth = w != null ? w.clamp(220.0, 640.0) : 340.0;
    return _cachedAudioPlaylistWidth;
  }

  static Future<void> saveAudioPlaylistWidth(double w) async {
    _cachedAudioPlaylistWidth = w;
    await AppDataService.setString(_audioPlaylistWidthKey, w.toString());
  }

  // 播放模式：0=顺序(off) 1=列表循环(all) 2=单曲循环(one) 3=随机(shuffle)。
  static const _audioRepeatKey = 'audio_repeat_mode';
  static const int _defaultAudioRepeat = 1; // 默认列表循环

  static Future<int> loadAudioRepeatMode() async {
    final val = await AppDataService.getString(_audioRepeatKey);
    final v = int.tryParse(val ?? '');
    return v != null ? v.clamp(0, 3) : _defaultAudioRepeat;
  }

  static Future<void> saveAudioRepeatMode(int v) async {
    await AppDataService.setString(_audioRepeatKey, v.toString());
  }

  // 播放倍速（0.5~2.0）。
  static const _audioSpeedKey = 'audio_speed';
  static const double _defaultAudioSpeed = 1.0;

  static Future<double> loadAudioSpeed() async {
    final val = await AppDataService.getString(_audioSpeedKey);
    final v = double.tryParse(val ?? '');
    return v != null ? v.clamp(0.5, 2.0) : _defaultAudioSpeed;
  }

  static Future<void> saveAudioSpeed(double v) async {
    await AppDataService.setString(_audioSpeedKey, v.toString());
  }

  // 是否显示歌词面板（默认显示）。
  static const _audioShowLyricsKey = 'audio_show_lyrics';
  static bool _cachedAudioShowLyrics = true;

  static bool loadAudioShowLyricsSync() => _cachedAudioShowLyrics;

  static Future<bool> loadAudioShowLyrics() async {
    final val = await AppDataService.getString(_audioShowLyricsKey);
    _cachedAudioShowLyrics = val == null || val == 'true';
    return _cachedAudioShowLyrics;
  }

  static Future<void> saveAudioShowLyrics(bool v) async {
    _cachedAudioShowLyrics = v;
    await AppDataService.setString(_audioShowLyricsKey, v.toString());
  }

  // --- Comic reader settings ---

  static const _readerLayoutKey = 'reader_layout_mode';
  static const _readerDirectionKey = 'reader_direction';
  static const _readerFitKey = 'reader_fit_mode';
  static const _readerShowThumbsKey = 'reader_show_thumbnails';
  static const _readerShowPageNumKey = 'reader_show_page_number';
  static const _readerThumbWidthKey = 'reader_thumbnail_width';

  static ComicLayoutMode _cachedReaderLayout = ComicLayoutMode.single;
  static ComicReadDirection _cachedReaderDirection = ComicReadDirection.rtl;
  static ComicFitMode _cachedReaderFit = ComicFitMode.height;
  static bool _cachedReaderShowThumbs = true;
  static bool _cachedReaderShowPageNum = true;
  static double _cachedReaderThumbWidth = 200.0;

  static ComicLayoutMode loadReaderLayoutModeSync() => _cachedReaderLayout;
  static ComicReadDirection loadReaderDirectionSync() => _cachedReaderDirection;
  static ComicFitMode loadReaderFitModeSync() => _cachedReaderFit;
  static bool loadReaderShowThumbnailsSync() => _cachedReaderShowThumbs;
  static bool loadReaderShowPageNumberSync() => _cachedReaderShowPageNum;
  static double loadReaderThumbnailWidthSync() => _cachedReaderThumbWidth;

  static Future<ComicLayoutMode> loadReaderLayoutMode() async {
    final val = await AppDataService.getString(_readerLayoutKey);
    _cachedReaderLayout = ComicLayoutMode.values.firstWhere(
      (e) => e.name == val,
      orElse: () => ComicLayoutMode.single,
    );
    return _cachedReaderLayout;
  }

  static Future<void> saveReaderLayoutMode(ComicLayoutMode m) async {
    _cachedReaderLayout = m;
    await AppDataService.setString(_readerLayoutKey, m.name);
  }

  static Future<ComicReadDirection> loadReaderDirection() async {
    final val = await AppDataService.getString(_readerDirectionKey);
    _cachedReaderDirection = ComicReadDirection.values.firstWhere(
      (e) => e.name == val,
      orElse: () => ComicReadDirection.rtl,
    );
    return _cachedReaderDirection;
  }

  static Future<void> saveReaderDirection(ComicReadDirection d) async {
    _cachedReaderDirection = d;
    await AppDataService.setString(_readerDirectionKey, d.name);
  }

  static Future<ComicFitMode> loadReaderFitMode() async {
    final val = await AppDataService.getString(_readerFitKey);
    _cachedReaderFit = ComicFitMode.values.firstWhere(
      (e) => e.name == val,
      orElse: () => ComicFitMode.height,
    );
    return _cachedReaderFit;
  }

  static Future<void> saveReaderFitMode(ComicFitMode f) async {
    _cachedReaderFit = f;
    await AppDataService.setString(_readerFitKey, f.name);
  }

  static Future<bool> loadReaderShowThumbnails() async {
    final val = await AppDataService.getString(_readerShowThumbsKey);
    _cachedReaderShowThumbs = val == null || val == 'true';
    return _cachedReaderShowThumbs;
  }

  static Future<void> saveReaderShowThumbnails(bool v) async {
    _cachedReaderShowThumbs = v;
    await AppDataService.setString(_readerShowThumbsKey, v.toString());
  }

  static Future<bool> loadReaderShowPageNumber() async {
    final val = await AppDataService.getString(_readerShowPageNumKey);
    _cachedReaderShowPageNum = val == null || val == 'true';
    return _cachedReaderShowPageNum;
  }

  static Future<void> saveReaderShowPageNumber(bool v) async {
    _cachedReaderShowPageNum = v;
    await AppDataService.setString(_readerShowPageNumKey, v.toString());
  }

  static Future<double> loadReaderThumbnailWidth() async {
    final val = await AppDataService.getString(_readerThumbWidthKey);
    final w = double.tryParse(val ?? '');
    _cachedReaderThumbWidth = w != null ? w.clamp(140.0, 460.0) : 200.0;
    return _cachedReaderThumbWidth;
  }

  static Future<void> saveReaderThumbnailWidth(double w) async {
    _cachedReaderThumbWidth = w;
    await AppDataService.setString(_readerThumbWidthKey, w.toString());
  }

  // --- Ebook reader settings ---

  static const _ebookReadModeKey = 'ebook_read_mode';
  static const _ebookFontSizeKey = 'ebook_font_size';
  static const _ebookLineHeightKey = 'ebook_line_height';
  static const _ebookFontFamilyKey = 'ebook_font_family';
  static const _ebookThemeKey = 'ebook_theme';
  static const _ebookPageMarginKey = 'ebook_page_margin';
  static const _ebookJustifyKey = 'ebook_justify';
  static const _ebookShowTocKey = 'ebook_show_toc';
  static const _ebookTocWidthKey = 'ebook_toc_width';

  static EbookReadMode _cachedEbookReadMode = EbookReadMode.paginated;
  static double _cachedEbookFontSize = 16.0;
  static double _cachedEbookLineHeight = 1.7;
  static String _cachedEbookFontFamily = 'system';
  static EbookTheme _cachedEbookTheme = EbookTheme.light;
  static double _cachedEbookPageMargin = 28.0;
  static bool _cachedEbookJustify = true;
  static bool _cachedEbookShowToc = true;
  static double _cachedEbookTocWidth = 220.0;

  static EbookReadMode loadEbookReadModeSync() => _cachedEbookReadMode;
  static double loadEbookFontSizeSync() => _cachedEbookFontSize;
  static double loadEbookLineHeightSync() => _cachedEbookLineHeight;
  static String loadEbookFontFamilySync() => _cachedEbookFontFamily;
  static EbookTheme loadEbookThemeSync() => _cachedEbookTheme;
  static double loadEbookPageMarginSync() => _cachedEbookPageMargin;
  static bool loadEbookJustifySync() => _cachedEbookJustify;
  static bool loadEbookShowTocSync() => _cachedEbookShowToc;
  static double loadEbookTocWidthSync() => _cachedEbookTocWidth;

  static Future<EbookReadMode> loadEbookReadMode() async {
    final val = await AppDataService.getString(_ebookReadModeKey);
    _cachedEbookReadMode = EbookReadMode.values.firstWhere(
      (e) => e.name == val,
      orElse: () => EbookReadMode.paginated,
    );
    return _cachedEbookReadMode;
  }

  static Future<void> saveEbookReadMode(EbookReadMode m) async {
    _cachedEbookReadMode = m;
    await AppDataService.setString(_ebookReadModeKey, m.name);
  }

  static Future<double> loadEbookFontSize() async {
    final val = await AppDataService.getString(_ebookFontSizeKey);
    final v = double.tryParse(val ?? '');
    _cachedEbookFontSize = v != null ? v.clamp(10.0, 40.0) : 16.0;
    return _cachedEbookFontSize;
  }

  static Future<void> saveEbookFontSize(double v) async {
    _cachedEbookFontSize = v.clamp(10.0, 40.0);
    await AppDataService.setString(_ebookFontSizeKey, v.toString());
  }

  static Future<double> loadEbookLineHeight() async {
    final val = await AppDataService.getString(_ebookLineHeightKey);
    final v = double.tryParse(val ?? '');
    _cachedEbookLineHeight = v != null ? v.clamp(1.0, 3.0) : 1.7;
    return _cachedEbookLineHeight;
  }

  static Future<void> saveEbookLineHeight(double v) async {
    _cachedEbookLineHeight = v.clamp(1.0, 3.0);
    await AppDataService.setString(_ebookLineHeightKey, v.toString());
  }

  static Future<String> loadEbookFontFamily() async {
    final val = await AppDataService.getString(_ebookFontFamilyKey);
    _cachedEbookFontFamily = val ?? 'system';
    return _cachedEbookFontFamily;
  }

  static Future<void> saveEbookFontFamily(String v) async {
    _cachedEbookFontFamily = v;
    await AppDataService.setString(_ebookFontFamilyKey, v);
  }

  static Future<EbookTheme> loadEbookTheme() async {
    final val = await AppDataService.getString(_ebookThemeKey);
    _cachedEbookTheme = EbookTheme.values.firstWhere(
      (e) => e.name == val,
      orElse: () => EbookTheme.light,
    );
    return _cachedEbookTheme;
  }

  static Future<void> saveEbookTheme(EbookTheme t) async {
    _cachedEbookTheme = t;
    await AppDataService.setString(_ebookThemeKey, t.name);
  }

  static Future<double> loadEbookPageMargin() async {
    final val = await AppDataService.getString(_ebookPageMarginKey);
    final v = double.tryParse(val ?? '');
    _cachedEbookPageMargin = v != null ? v.clamp(0.0, 80.0) : 28.0;
    return _cachedEbookPageMargin;
  }

  static Future<void> saveEbookPageMargin(double v) async {
    _cachedEbookPageMargin = v.clamp(0.0, 80.0);
    await AppDataService.setString(_ebookPageMarginKey, v.toString());
  }

  static Future<bool> loadEbookJustify() async {
    final val = await AppDataService.getString(_ebookJustifyKey);
    _cachedEbookJustify = val != 'false';
    return _cachedEbookJustify;
  }

  static Future<void> saveEbookJustify(bool v) async {
    _cachedEbookJustify = v;
    await AppDataService.setString(_ebookJustifyKey, v.toString());
  }

  static Future<bool> loadEbookShowToc() async {
    final val = await AppDataService.getString(_ebookShowTocKey);
    _cachedEbookShowToc = val != 'false';
    return _cachedEbookShowToc;
  }

  static Future<void> saveEbookShowToc(bool v) async {
    _cachedEbookShowToc = v;
    await AppDataService.setString(_ebookShowTocKey, v.toString());
  }

  static Future<double> loadEbookTocWidth() async {
    final val = await AppDataService.getString(_ebookTocWidthKey);
    final v = double.tryParse(val ?? '');
    _cachedEbookTocWidth = v != null ? v.clamp(160.0, 420.0) : 220.0;
    return _cachedEbookTocWidth;
  }

  static Future<void> saveEbookTocWidth(double w) async {
    _cachedEbookTocWidth = w.clamp(160.0, 420.0);
    await AppDataService.setString(_ebookTocWidthKey, w.toString());
  }

  // --- Grouping ---

  static Future<bool> loadGroupingEnabled() async {
    return (await AppDataService.getString('grouping_enabled')) == 'true';
  }

  static Future<void> saveGroupingEnabled(bool v) async {
    await AppDataService.setString('grouping_enabled', v.toString());
  }

  // --- Background settings ---

  static Future<BackgroundSettings> loadBackgroundSettings() async {
    final data = await AppDataService.loadSettings();
    return BackgroundSettings(
      path: data['${_bgPrefix}path'] as String?,
      leftOpacity: (data['${_bgPrefix}leftOpacity'] as num?)?.toDouble() ?? 1.0,
      middleOpacity: (data['${_bgPrefix}middleOpacity'] as num?)?.toDouble() ?? 1.0,
      rightOpacity: (data['${_bgPrefix}rightOpacity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  static Future<void> saveBackgroundSettings(BackgroundSettings settings) async {
    final data = await AppDataService.loadSettings();
    if (settings.path != null) {
      data['${_bgPrefix}path'] = settings.path;
    } else {
      data.remove('${_bgPrefix}path');
    }
    data['${_bgPrefix}leftOpacity'] = settings.leftOpacity;
    data['${_bgPrefix}middleOpacity'] = settings.middleOpacity;
    data['${_bgPrefix}rightOpacity'] = settings.rightOpacity;
    await AppDataService.saveSettings(data);
  }
}
