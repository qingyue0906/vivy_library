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

class GridSettings {
  final double minCardWidth;
  final double maxCardWidth;
  final String aspectRatio; // "1:1", "4:3", "16:9"
  final int itemsPerRow; // 0 = auto
  final double compactLevel; // 0.5~2.0, 1.0 = current baseline
  final GifDisplayMode cardGifMode;
  final GifDisplayMode fileGifMode;

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
  });

  GridSettings copyWith({
    double? minCardWidth,
    double? maxCardWidth,
    String? aspectRatio,
    int? itemsPerRow,
    double? compactLevel,
    GifDisplayMode? cardGifMode,
    GifDisplayMode? fileGifMode,
  }) {
    return GridSettings(
      minCardWidth: minCardWidth ?? this.minCardWidth,
      maxCardWidth: maxCardWidth ?? this.maxCardWidth,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      itemsPerRow: itemsPerRow ?? this.itemsPerRow,
      compactLevel: compactLevel ?? this.compactLevel,
      cardGifMode: cardGifMode ?? this.cardGifMode,
      fileGifMode: fileGifMode ?? this.fileGifMode,
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
      };

  factory GridSettings.fromMap(Map<String, dynamic> map) => GridSettings(
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
      );
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
