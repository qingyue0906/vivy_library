import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/settings_service.dart';
import '../services/preset_service.dart';

class SettingsPage extends StatefulWidget {
  final void Function(ThemeMode mode) onThemeChanged;
  final void Function(GridSettings settings) onGridSettingsChanged;

  const SettingsPage({
    super.key,
    required this.onThemeChanged,
    required this.onGridSettingsChanged,
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

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _load();
  }

  Future<void> _load() async {
    final theme = await SettingsService.loadThemeMode();
    final grid = await SettingsService.loadGridSettings();
    final presets = await PresetService.loadAll();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontSize: 14)),
        bottom: TabBar(
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
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildDataTab(),
          _buildThemeTab(),
          _buildUiTab(),
          _buildPresetTab(),
          _buildAboutTab(),
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
    return Padding(
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
          const Text('自定义颜色', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          const Text('（开发中）', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
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
                    itemsPerRow: _gridSettings.itemsPerRow,
                  )),
          const SizedBox(height: 16),
          _buildSliderField('卡片最大宽度', _gridSettings.maxCardWidth, 120, 400,
              (v) => _gridSettings = GridSettings(
                    minCardWidth: _gridSettings.minCardWidth,
                    maxCardWidth: v,
                    aspectRatio: _gridSettings.aspectRatio,
                    itemsPerRow: _gridSettings.itemsPerRow,
                  )),
          const SizedBox(height: 16),
          _buildAspectRatioSelector(),
          const SizedBox(height: 16),
          _buildItemsPerRowField(),
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

  Widget _buildAspectRatioSelector() {
    const ratios = ['1:1', '4:3', '16:9'];
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
                itemsPerRow: n.clamp(0, 20),
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
              await PresetService.saveAll(Map.from(_presets));
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
      final prefs = await SharedPreferences.getInstance();
      final all = prefs.getString('edit_presets') ?? '{}';
      final export = {
        'version': '0.1.0',
        'exported_at': DateTime.now().toIso8601String(),
        'presets': jsonDecode(all),
      };
      final file = File('vivy_library_export.json');
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(export));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导出到 ${file.absolute.path}'),
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
      final file = File('vivy_library_export.json');
      if (!file.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到 vivy_library_export.json'), duration: Duration(seconds: 2)),
          );
        }
        return;
      }
      final data = jsonDecode(await file.readAsString()) as Map;
      final presets = data['presets'] as Map<String, dynamic>;
      final converted = presets.map((k, v) => MapEntry(k, List<String>.from(v as List)));
      await PresetService.saveAll(converted);
      _presets = converted;
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
