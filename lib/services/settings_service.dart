import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/library_state.dart';

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

  const WindowState({
    required this.dx,
    required this.dy,
    required this.width,
    required this.height,
  });

  Map<String, double> toMap() => {
        'dx': dx,
        'dy': dy,
        'width': width,
        'height': height,
      };

  factory WindowState.fromMap(Map<String, double?> map) => WindowState(
        dx: map['dx'] ?? 10,
        dy: map['dy'] ?? 10,
        width: map['width'] ?? 1280,
        height: map['height'] ?? 720,
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

  static Future<(SortField, SortOrder)> loadSortPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final fieldStr = prefs.getString(_sortFieldKey);
    final orderStr = prefs.getString(_sortOrderKey);

    final field = SortField.values.firstWhere(
      (e) => e.name == fieldStr,
      orElse: () => SortField.name,
    );
    final order = SortOrder.values.firstWhere(
      (e) => e.name == orderStr,
      orElse: () => SortOrder.ascending,
    );
    return (field, order);
  }

  static Future<void> saveSortPreferences(
      SortField field, SortOrder order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortFieldKey, field.name);
    await prefs.setString(_sortOrderKey, order.name);
  }

  // --- Layout (panel sizes) ---

  static Future<LayoutState> loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    return LayoutState.fromMap({
      'leftPanelWidth': prefs.getDouble('${_layoutPrefix}leftPanelWidth'),
      'rightPanelWidth': prefs.getDouble('${_layoutPrefix}rightPanelWidth'),
      'filePanelHeight': prefs.getDouble('${_layoutPrefix}filePanelHeight'),
    });
  }

  static Future<void> saveLayout(LayoutState state) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in state.toMap().entries) {
      await prefs.setDouble('$_layoutPrefix${entry.key}', entry.value);
    }
  }

  // --- Window state ---

  static Future<WindowState> loadWindowState() async {
    final prefs = await SharedPreferences.getInstance();
    return WindowState.fromMap({
      'dx': prefs.getDouble('${_windowPrefix}dx'),
      'dy': prefs.getDouble('${_windowPrefix}dy'),
      'width': prefs.getDouble('${_windowPrefix}width'),
      'height': prefs.getDouble('${_windowPrefix}height'),
    });
  }

  static Future<void> saveWindowState(WindowState state) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in state.toMap().entries) {
      await prefs.setDouble('$_windowPrefix${entry.key}', entry.value);
    }
  }

  // --- Theme ---

  static Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_themeKey);
    return ThemeMode.values.firstWhere(
      (e) => e.name == val,
      orElse: () => ThemeMode.system,
    );
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  // --- Grid/UI settings ---

  static Future<GridSettings> loadGridSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return GridSettings.fromMap({
      'minCardWidth': prefs.getDouble('${_gridPrefix}minCardWidth'),
      'maxCardWidth': prefs.getDouble('${_gridPrefix}maxCardWidth'),
      'aspectRatio': prefs.getString('${_gridPrefix}aspectRatio'),
      'itemsPerRow': prefs.getInt('${_gridPrefix}itemsPerRow'),
      'compactLevel': prefs.getDouble('${_gridPrefix}compactLevel'),
      'cardGifMode': prefs.getString('${_gridPrefix}cardGifMode'),
      'fileGifMode': prefs.getString('${_gridPrefix}fileGifMode'),
    });
  }

  static Future<void> saveGridSettings(GridSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in settings.toMap().entries) {
      final v = entry.value;
      if (v is double) {
        await prefs.setDouble('$_gridPrefix${entry.key}', v);
      } else if (v is int) {
        await prefs.setInt('$_gridPrefix${entry.key}', v);
      } else if (v is String) {
        await prefs.setString('$_gridPrefix${entry.key}', v);
      }
    }
  }

  // --- Background settings ---

  static Future<BackgroundSettings> loadBackgroundSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return BackgroundSettings(
      path: prefs.getString('${_bgPrefix}path'),
      leftOpacity: prefs.getDouble('${_bgPrefix}leftOpacity') ?? 1.0,
      middleOpacity: prefs.getDouble('${_bgPrefix}middleOpacity') ?? 1.0,
      rightOpacity: prefs.getDouble('${_bgPrefix}rightOpacity') ?? 1.0,
    );
  }

  static Future<void> saveBackgroundSettings(BackgroundSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    if (settings.path != null) {
      await prefs.setString('${_bgPrefix}path', settings.path!);
    } else {
      await prefs.remove('${_bgPrefix}path');
    }
    await prefs.setDouble('${_bgPrefix}leftOpacity', settings.leftOpacity);
    await prefs.setDouble('${_bgPrefix}middleOpacity', settings.middleOpacity);
    await prefs.setDouble('${_bgPrefix}rightOpacity', settings.rightOpacity);
  }
}
