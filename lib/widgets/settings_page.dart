import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../models/library_root.dart';
import '../services/library_root_service.dart';
import '../services/settings_service.dart';
import '../services/preset_service.dart';

class SettingsPage extends StatefulWidget {
  final String libraryRootPath;
  final void Function(ThemeMode mode) onThemeChanged;
  final void Function(GridSettings settings) onGridSettingsChanged;
  final BackgroundSettings backgroundSettings;
  final void Function(BackgroundSettings settings) onBackgroundChanged;

  const SettingsPage({
    super.key,
    required this.libraryRootPath,
    required this.onThemeChanged,
    required this.onGridSettingsChanged,
    required this.backgroundSettings,
    required this.onBackgroundChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  ThemeMode _themeMode = ThemeMode.system;
  GridSettings _gridSettings = const GridSettings();
  Map<String, List<String>> _presets = {};
  late BackgroundSettings _bgSettings;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _bgSettings = widget.backgroundSettings;
    _load();
  }

  Future<void> _load() async {
    final theme = await SettingsService.loadThemeMode();
    final grid = await SettingsService.loadGridSettings();
    final presets = await PresetService.loadAll(widget.libraryRootPath);
    setState(() {
      _themeMode = theme;
      _gridSettings = grid;
      _presets = presets;
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 30,
            color: cs.surfaceContainerHigh,
            child: Row(
              children: [
                Expanded(
                  child: DragToMoveArea(
                    child: Container(
                      height: 30,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 12),
                      child: Row(
                        children: [
                          Icon(Icons.menu_book, size: 14, color: cs.onSurface),
                          const SizedBox(width: 6),
                          Text('Vivy Library', style: TextStyle(fontSize: 12, color: cs.onSurface)),
                        ],
                      ),
                    ),
                  ),
                ),
                _windowButton(Icons.horizontal_rule, cs, () => windowManager.minimize()),
                _windowButton(Icons.crop_square, cs, () => windowManager.maximize()),
                _windowButton(Icons.close, cs, () => exit(0), isClose: true),
              ],
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 60,
                  height: 48,
                  alignment: Alignment.center,
                  child: Icon(Icons.arrow_back, size: 14, color: cs.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: const TextStyle(fontSize: 12),
            tabs: const [
              Tab(text: '数据'),
              Tab(text: '主题'),
              Tab(text: '界面'),
              Tab(text: '预设管理'),
              Tab(text: '关于'),
            ],
          ),
              ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
              child: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildDataTab(),
            _buildThemeTab(),
            _buildUiTab(),
            _buildPresetTab(),
            _buildAboutTab(),
          ],
        ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('数据管理', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _buildActionButton('导出数据', Icons.file_upload_outlined, _exportData),
          const SizedBox(height: 10),
          _buildActionButton('导入数据（覆盖）', Icons.file_download_outlined, _importData),
          const SizedBox(height: 10),
          _buildActionButton('清空数据', Icons.delete_outline, _clearData,
              color: Colors.red.shade700),
        ],
      ),
    );
  }

  Widget _buildThemeTab() {
    final cs = Theme.of(context).colorScheme;
    final hasBg = _bgSettings.path != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('主题', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _buildThemeOption('跟随系统', ThemeMode.system),
          _buildThemeOption('亮色', ThemeMode.light),
          _buildThemeOption('暗色', ThemeMode.dark),
          const SizedBox(height: 20),
          const Text('自定义背景', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickBackgroundImage,
                icon: const Icon(Icons.image, size: 16),
                label: const Text('选择背景', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              if (hasBg) ...[
                OutlinedButton.icon(
                  onPressed: _clearBackground,
                  icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade700),
                  label: Text('清除背景',
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                ),
              ],
            ],
          ),
          if (hasBg) ...[
            const SizedBox(height: 4),
            Text(
              _bgSettings.path!.replaceAll('\\', '/').split('/').last,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          const Text('面板不透明度', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          _buildOpacitySlider('左面板', _bgSettings.leftOpacity, hasBg, (v) {
            _bgSettings = _bgSettings.copyWith(leftOpacity: v);
            _saveBackground();
          }),
          _buildOpacitySlider('中间区域', _bgSettings.middleOpacity, hasBg, (v) {
            _bgSettings = _bgSettings.copyWith(middleOpacity: v);
            _saveBackground();
          }),
          _buildOpacitySlider('右面板', _bgSettings.rightOpacity, hasBg, (v) {
            _bgSettings = _bgSettings.copyWith(rightOpacity: v);
            _saveBackground();
          }),
          _buildOpacitySlider('卡片', _bgSettings.cardOpacity, hasBg, (v) {
            _bgSettings = _bgSettings.copyWith(cardOpacity: v);
            _saveBackground();
          }),
        ],
      ),
    );
  }

  Widget _buildOpacitySlider(String label, double value, bool enabled, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF616161))),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: value,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  onChanged: enabled
                      ? (v) {
                          setState(() => onChanged(v));
                        }
                      : null,
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text('${(value * 100).round()}%',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickBackgroundImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: '选择背景图片',
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    setState(() {
      _bgSettings = _bgSettings.copyWith(path: path);
    });
    _saveBackground();
  }

  void _clearBackground() {
    setState(() {
      _bgSettings = _bgSettings.copyWith(clearPath: true);
    });
    _saveBackground();
  }

  void _saveBackground() {
    SettingsService.saveBackgroundSettings(_bgSettings);
    widget.onBackgroundChanged(_bgSettings);
  }

  Widget _buildUiTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('网格设置', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _buildSliderField('卡片最小宽度', _gridSettings.minCardWidth, 80, 300,
              (v) => _gridSettings = GridSettings(
                    minCardWidth: v,
                    maxCardWidth: _gridSettings.maxCardWidth,
                    aspectRatio: _gridSettings.aspectRatio,
                    itemsPerRow: _gridSettings.itemsPerRow, compactLevel: _gridSettings.compactLevel,
                  )),
          const SizedBox(height: 16),
          _buildSliderField('卡片最大宽度', _gridSettings.maxCardWidth, 120, 400,
              (v) => _gridSettings = GridSettings(
                    minCardWidth: _gridSettings.minCardWidth,
                    maxCardWidth: v,
                    aspectRatio: _gridSettings.aspectRatio,
                    itemsPerRow: _gridSettings.itemsPerRow, compactLevel: _gridSettings.compactLevel,
                  )),
          const SizedBox(height: 16),
          _buildAspectRatioSelector(),
          const SizedBox(height: 16),
          _buildItemsPerRowField(),
          const SizedBox(height: 20),
          _buildCompactLevelSlider(),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saveGridSettings,
              child: const Text('应用', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLevelSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('紧凑度', style: TextStyle(fontSize: 11, color: Color(0xFF616161))),
            const SizedBox(width: 8),
            Text('${(_gridSettings.compactLevel * 100).round()}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: _gridSettings.compactLevel,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            onChanged: (v) => setState(() {
              _gridSettings = GridSettings(
                minCardWidth: _gridSettings.minCardWidth,
                maxCardWidth: _gridSettings.maxCardWidth,
                aspectRatio: _gridSettings.aspectRatio,
                itemsPerRow: _gridSettings.itemsPerRow,
                compactLevel: v,
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('编辑预设管理',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: _presets.entries.map((entry) {
                return Card(
                  child: ListTile(
                    dense: true,
                    title: Text(entry.key,
                        style: const TextStyle(fontSize: 12)),
                    subtitle: Text(
                      entry.value.join(', '),
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, size: 16),
                      onPressed: () => _editPreset(entry.key),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Vivy Library', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('版本 0.1.0', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          const Text('项目地址', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {},
            child: const Text(
              'https://github.com/anomalyco/vivy-library',
              style: TextStyle(fontSize: 12, color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
      String label, IconData icon, VoidCallback onTap, {Color? color}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: color ?? Theme.of(context).textTheme.bodyLarge?.color)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }

  Widget _buildThemeOption(String label, ThemeMode mode) {
    final selected = _themeMode == mode;
    return InkWell(
      onTap: () {
        setState(() => _themeMode = mode);
        SettingsService.saveThemeMode(mode);
        widget.onThemeChanged(mode);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? Colors.deepPurple : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderField(
      String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toInt()}px',
            style: const TextStyle(fontSize: 11, color: Color(0xFF616161))),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) / 10).round(),
          onChanged: (v) => setState(() => onChanged(v)),
        ),
      ],
    );
  }

  Widget _windowButton(IconData icon, ColorScheme cs, VoidCallback onTap, {bool isClose = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 30,
        alignment: Alignment.center,
        child: Icon(icon, size: 12, color: isClose ? Colors.red.shade300 : cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildAspectRatioSelector() {
    const ratios = ['1:1', '4:3', '3:2', '16:9'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('卡片宽高比',
            style: TextStyle(fontSize: 11, color: Color(0xFF616161))),
        const SizedBox(height: 8),
        Row(
          children: ratios.map((r) {
            final selected = _gridSettings.aspectRatio == r;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(r, style: const TextStyle(fontSize: 11)),
                selected: selected,
                onSelected: (_) => setState(() {
                  _gridSettings = GridSettings(
                    minCardWidth: _gridSettings.minCardWidth,
                    maxCardWidth: _gridSettings.maxCardWidth,
                    aspectRatio: r,
                    itemsPerRow: _gridSettings.itemsPerRow,
                  );
                }),
                visualDensity: VisualDensity.compact,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildItemsPerRowField() {
    return Row(
      children: [
        const Text('每行固定数量（0=自动）',
            style: TextStyle(fontSize: 11, color: Color(0xFF616161))),
        const SizedBox(width: 12),
        SizedBox(
          width: 60,
          child: TextField(
            keyboardType: TextInputType.number,
            controller: TextEditingController(
                text: _gridSettings.itemsPerRow.toString()),
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onChanged: (v) {
              final n = int.tryParse(v) ?? 0;
              _gridSettings = GridSettings(
                minCardWidth: _gridSettings.minCardWidth,
                maxCardWidth: _gridSettings.maxCardWidth,
                aspectRatio: _gridSettings.aspectRatio,
                itemsPerRow: n.clamp(0, 20), compactLevel: _gridSettings.compactLevel,
              );
            },
          ),
        ),
      ],
    );
  }

  void _saveGridSettings() {
    SettingsService.saveGridSettings(_gridSettings);
    widget.onGridSettingsChanged(_gridSettings);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('网格设置已保存'), duration: Duration(seconds: 1)),
    );
  }

  void _editPreset(String key) {
    final ctrl = TextEditingController(text: _presets[key]?.join('\n') ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑 $key', style: const TextStyle(fontSize: 13)),
        content: SizedBox(
          width: 300,
          child: TextField(
            controller: ctrl,
            maxLines: 8,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: '每行一个选项',
              border: OutlineInputBorder(),
              contentPadding: const EdgeInsets.all(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(fontSize: 12)),
          ),
          FilledButton(
            onPressed: () async {
              final lines = ctrl.text
                  .split('\n')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              _presets[key] = lines;
              await PresetService.saveAll(widget.libraryRootPath, Map.from(_presets));
              if (!ctx.mounted) return;
              if (mounted) setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('保存', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportData() async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择导出目录',
      );
      if (dir == null) return;

      final prefs = await SharedPreferences.getInstance();
      final theme = prefs.getString('theme_mode') ?? 'system';
      final sortField = prefs.getString('sort_field') ?? 'name';
      final sortOrder = prefs.getString('sort_order') ?? 'ascending';
      final gridSettings = await SettingsService.loadGridSettings();
      final layout = await SettingsService.loadLayout();
      final windowState = await SettingsService.loadWindowState();
      final roots = await LibraryRootService().loadAll();

      final export = {
        'version': '0.1.0',
        'exported_at': DateTime.now().toIso8601String(),
        'theme_mode': theme,
        'sort_field': sortField,
        'sort_order': sortOrder,
        'grid_settings': gridSettings.toMap(),
        'layout': layout.toMap(),
        'window_state': windowState.toMap(),
        'library_roots': roots.map((r) => {'name': r.name, 'path': r.path}).toList(),
      };

      final file = File('$dir/vivy_library_export.json');
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(export));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导出到 $dir/vivy_library_export.json'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _importData() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择导入文件',
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path!;

      final file = File(path);
      if (!file.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), duration: Duration(seconds: 2)),
          );
        }
        return;
      }

      final data = jsonDecode(await file.readAsString()) as Map;
      final prefs = await SharedPreferences.getInstance();

      if (data['theme_mode'] != null) {
        await prefs.setString('theme_mode', data['theme_mode'] as String);
      }
      if (data['sort_field'] != null) {
        await prefs.setString('sort_field', data['sort_field'] as String);
      }
      if (data['sort_order'] != null) {
        await prefs.setString('sort_order', data['sort_order'] as String);
      }
      if (data['grid_settings'] != null) {
        final gs = GridSettings.fromMap(data['grid_settings'] as Map<String, dynamic>);
        await SettingsService.saveGridSettings(gs);
        widget.onGridSettingsChanged(gs);
      }
      if (data['layout'] != null) {
        final l = LayoutState.fromMap(
            (data['layout'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
        await SettingsService.saveLayout(l);
      }
      if (data['window_state'] != null) {
        final w = WindowState.fromMap(
            (data['window_state'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
        await SettingsService.saveWindowState(w);
      }
      if (data['library_roots'] != null) {
        final roots = (data['library_roots'] as List)
            .map((r) => LibraryRoot(name: r['name'] as String, path: r['path'] as String))
            .toList();
        await LibraryRootService().saveAll(roots);
      }
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('数据已导入'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _clearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空', style: TextStyle(fontSize: 13)),
        content: const Text('确定要清空所有数据吗？此操作不可撤销。',
            style: TextStyle(fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(fontSize: 12)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确认清空', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('数据已清空'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清空失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
