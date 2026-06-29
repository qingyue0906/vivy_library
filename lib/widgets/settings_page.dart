import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import '../models/library_root.dart';
import '../services/app_data_service.dart';
import '../services/library_root_service.dart';
import '../services/script_service.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';
import '../utils/app_quit.dart';
import 'smooth_scroll.dart';

class SettingsPage extends StatefulWidget {
  final String libraryRootPath;
  final void Function(ThemeMode mode) onThemeChanged;
  final void Function(GridSettings settings) onGridSettingsChanged;
  final BackgroundSettings backgroundSettings;
  final void Function(BackgroundSettings settings) onBackgroundChanged;
  final void Function(AppLocale locale) onLocaleChanged;
  final ScriptService scriptService;

  const SettingsPage({
    super.key,
    required this.libraryRootPath,
    required this.onThemeChanged,
    required this.onGridSettingsChanged,
    required this.backgroundSettings,
    required this.onBackgroundChanged,
    required this.onLocaleChanged,
    required this.scriptService,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  ThemeMode _themeMode = ThemeMode.system;
  GridSettings _gridSettings = const GridSettings();
  late BackgroundSettings _bgSettings;
  late AppLocale _locale;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this);
    _bgSettings = widget.backgroundSettings;
    _locale = Strings.currentLocale;
    _load();
  }

  Future<void> _load() async {
    final theme = await SettingsService.loadThemeMode();
    final grid = await SettingsService.loadGridSettings();
    setState(() {
      _themeMode = theme;
      _gridSettings = grid;
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
                _windowButton(Icons.close, cs, () => quitApp(), isClose: true),
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
            tabs: [
              Tab(text: Strings.t('tabGeneral')),
              Tab(text: Strings.t('tabData')),
              Tab(text: Strings.t('tabTheme')),
              Tab(text: Strings.t('tabUi')),
              Tab(text: Strings.t('tabScripts')),
              Tab(text: Strings.t('tabAbout')),
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
            _buildGeneralTab(),
            _buildDataTab(),
            _buildThemeTab(),
            _buildUiTab(),
            _buildScriptsTab(),
            _buildAboutTab(),
          ],
        ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Strings.t('language'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(Strings.t('languageDesc'), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 12),
          ...AppLocale.values.map((locale) {
            final selected = _locale == locale;
            return InkWell(
              onTap: () {
                setState(() => _locale = locale);
                widget.onLocaleChanged(locale);
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
                    Text(locale.displayName, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            );
          }),
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
          Text(Strings.t('dataManage'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _buildActionButton(Strings.t('exportData'), Icons.file_upload_outlined, _exportData),
          const SizedBox(height: 10),
          _buildActionButton(Strings.t('importData'), Icons.file_download_outlined, _importData),
          const SizedBox(height: 10),
          _buildActionButton(Strings.t('clearData'), Icons.delete_outline, _clearData,
              color: Colors.red.shade700),
        ],
      ),
    );
  }

  Widget _buildThemeTab() {
    final cs = Theme.of(context).colorScheme;
    final hasBg = _bgSettings.path != null;
    return SmoothScroll(
      builder: (context, controller, physics) => SingleChildScrollView(
        controller: controller,
        physics: physics,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Strings.t('themeSection'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            _buildThemeOption(Strings.t('followSystem'), ThemeMode.system),
            _buildThemeOption(Strings.t('light'), ThemeMode.light),
            _buildThemeOption(Strings.t('dark'), ThemeMode.dark),
            const SizedBox(height: 20),
            Text(Strings.t('customBg'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickBackgroundImage,
                  icon: const Icon(Icons.image, size: 16),
                  label: Text(Strings.t('selectBg'), style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                if (hasBg) ...[
                  OutlinedButton.icon(
                    onPressed: _clearBackground,
                    icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade700),
                    label: Text(Strings.t('clearBg'),
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
            Text(Strings.t('panelOpacity'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            _buildOpacitySlider(Strings.t('leftPanel'), _bgSettings.leftOpacity, hasBg, (v) {
              _bgSettings = _bgSettings.copyWith(leftOpacity: v);
              _saveBackground();
            }),
            _buildOpacitySlider(Strings.t('middlePanel'), _bgSettings.middleOpacity, hasBg, (v) {
              _bgSettings = _bgSettings.copyWith(middleOpacity: v);
              _saveBackground();
            }),
            _buildOpacitySlider(Strings.t('rightPanel'), _bgSettings.rightOpacity, hasBg, (v) {
              _bgSettings = _bgSettings.copyWith(rightOpacity: v);
              _saveBackground();
            }),
          ],
        ),
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
      dialogTitle: Strings.t('selectBgTitle'),
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
    return SmoothScroll(
      builder: (context, controller, physics) => SingleChildScrollView(
        controller: controller,
        physics: physics,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Strings.t('gridSettings'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            _buildSliderField(Strings.t('minCardWidth'), _gridSettings.minCardWidth, 80, 300,
                (v) => _gridSettings = _gridSettings.copyWith(minCardWidth: v)),
            const SizedBox(height: 16),
            _buildSliderField(Strings.t('maxCardWidth'), _gridSettings.maxCardWidth, 120, 400,
                (v) => _gridSettings = _gridSettings.copyWith(maxCardWidth: v)),
            const SizedBox(height: 16),
            _buildAspectRatioSelector(),
            const SizedBox(height: 16),
            _buildItemsPerRowField(),
            const SizedBox(height: 20),
            _buildCompactLevelSlider(),
            const SizedBox(height: 20),
            Text(Strings.t('gifDisplayMode'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _buildGifModeSelector(Strings.t('cardGifMode'), _gridSettings.cardGifMode, (v) {
              setState(() => _gridSettings = _gridSettings.copyWith(cardGifMode: v));
            }),
            const SizedBox(height: 12),
            _buildGifModeSelector(Strings.t('fileGifMode'), _gridSettings.fileGifMode, (v) {
              setState(() => _gridSettings = _gridSettings.copyWith(fileGifMode: v));
            }),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saveGridSettings,
                child: Text(Strings.t('apply'), style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactLevelSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(Strings.t('compactLevel'), style: const TextStyle(fontSize: 11, color: Color(0xFF616161))),
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
              _gridSettings = _gridSettings.copyWith(compactLevel: v);
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildGifModeSelector(String label, GifDisplayMode current, ValueChanged<GifDisplayMode> onChanged) {
    final labels = {
      GifDisplayMode.unlimited: Strings.t('gifUnlimited'),
      GifDisplayMode.hover: Strings.t('gifHover'),
      GifDisplayMode.static: Strings.t('gifStatic'),
    };
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF616161))),
        ),
        Expanded(
          child: DropdownButtonFormField<GifDisplayMode>(
            key: ValueKey(current),
            initialValue: current,
            isDense: true,
            style: TextStyle(fontSize: 12, color: cs.onSurface),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            ),
            items: GifDisplayMode.values
                .map((mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(labels[mode]!, style: TextStyle(fontSize: 12, color: cs.onSurface)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScriptsTab() {
    final scripts = widget.scriptService.scripts;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Python 路径
          Text(Strings.t('pythonPath'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.scriptService.pythonPath.isEmpty
                        ? Strings.t('pythonPathDefault')
                        : widget.scriptService.pythonPath,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _pickPythonPath,
                child: Text(Strings.t('pythonBrowse'), style: const TextStyle(fontSize: 12)),
              ),
              if (widget.scriptService.pythonPath.isNotEmpty)
                TextButton(
                  onPressed: _clearPythonPath,
                  child: Text(Strings.t('pythonReset'), style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          // 脚本管理
          Row(
            children: [
              Text(Strings.t('scriptManage'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              _smallButton(Strings.t('scriptImport'), Icons.add, _importScript),
            ],
          ),
          const SizedBox(height: 8),
          if (scripts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(Strings.t('noScripts'),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ),
            )
          else
            Expanded(
              child: SmoothScroll(
                builder: (context, controller, physics) => ListView(
                  controller: controller,
                  physics: physics,
                  children: [
                    for (final script in scripts) _buildScriptItem(script),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScriptItem(ScriptEntry script) {
    final cs = Theme.of(context).colorScheme;
    final desc = widget.scriptService.readDescriptionSync(script);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.code, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(script.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(script.fileName,
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
                ],
              ],
            ),
          ),
          _execModeToggle(script),
          SizedBox(
            width: 36,
            height: 20,
            child: Switch(
              value: script.enabled,
              onChanged: (v) {
                final updated = script.copyWith(enabled: v);
                widget.scriptService.updateScript(updated);
                setState(() {});
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          _smallIconBtn(Icons.edit_outlined, Strings.t('scriptEdit'), () => _editScript(script)),
          _smallIconBtn(Icons.file_download_outlined, Strings.t('scriptExport'), () => _exportScript(script)),
          _smallIconBtn(Icons.delete_outline, Strings.t('scriptDelete'), () => _deleteScript(script), Colors.red),
        ],
      ),
    );
  }

  Widget _execModeToggle(ScriptEntry script) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<ScriptExecMode>(
      tooltip: _execModeLabel(script.execMode),
      onSelected: (mode) {
        final updated = script.copyWith(execMode: mode);
        widget.scriptService.updateScript(updated);
        setState(() {});
      },
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_execModeIcon(script.execMode), size: 12, color: cs.onSurfaceVariant),
            const SizedBox(width: 3),
            Text(_execModeLabel(script.execMode),
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(value: ScriptExecMode.result, child: Text(Strings.t('execModeResult'), style: const TextStyle(fontSize: 12))),
        PopupMenuItem(value: ScriptExecMode.terminal, child: Text(Strings.t('execModeTerminal'), style: const TextStyle(fontSize: 12))),
        PopupMenuItem(value: ScriptExecMode.silent, child: Text(Strings.t('execModeSilent'), style: const TextStyle(fontSize: 12))),
      ],
    );
  }

  IconData _execModeIcon(ScriptExecMode mode) {
    switch (mode) {
      case ScriptExecMode.result: return Icons.description_outlined;
      case ScriptExecMode.terminal: return Icons.terminal;
      case ScriptExecMode.silent: return Icons.check_circle_outline;
    }
  }

  String _execModeLabel(ScriptExecMode mode) {
    switch (mode) {
      case ScriptExecMode.result: return Strings.t('execModeResult');
      case ScriptExecMode.terminal: return Strings.t('execModeTerminal');
      case ScriptExecMode.silent: return Strings.t('execModeSilent');
    }
  }

  Widget _smallButton(String label, IconData icon, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
    );
  }

  Widget _smallIconBtn(IconData icon, String tooltip, VoidCallback onTap, [Color? color]) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      tooltip: tooltip,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }

  Future<void> _pickPythonPath() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: Strings.t('pythonPickTitle'),
      type: FileType.custom,
      allowedExtensions: ['exe'],
    );
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        await widget.scriptService.savePythonPath(path);
        setState(() {});
      }
    }
  }

  Future<void> _clearPythonPath() async {
    await widget.scriptService.savePythonPath('');
    setState(() {});
  }

  Future<void> _importScript() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: Strings.t('scriptImportTitle'),
      type: FileType.custom,
      allowedExtensions: ['py'],
    );
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        await widget.scriptService.importScript(path);
        setState(() {});
      }
    }
  }

  Future<void> _editScript(ScriptEntry script) async {
    final scriptPath = '${_resolveScriptsDir()}/${script.fileName}';
    await Process.run('cmd', ['/c', 'start', '', scriptPath]);
  }

  String get _baseDir => AppDataService.baseDir;
  String _resolveScriptsDir() => '$_baseDir/scripts';

  String _basename(String path) {
    return path.replaceAll('\\', '/').split('/').last;
  }

  Future<void> _exportScript(ScriptEntry script) async {
    final dest = await FilePicker.platform.getDirectoryPath(
      dialogTitle: Strings.t('scriptExportTitle'),
    );
    if (dest == null) return;
    final src = File('${_resolveScriptsDir()}/${script.fileName}');
    await src.copy('$dest/${script.fileName}');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Strings.t('scriptExported')), duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _deleteScript(ScriptEntry script) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('scriptDeleteConfirm'), style: const TextStyle(fontSize: 13)),
        content: Text(Strings.tn('scriptDeleteMsg', {'name': script.name}),
            style: const TextStyle(fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Strings.t('cancel'), style: const TextStyle(fontSize: 12)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(Strings.t('scriptDelete'), style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.scriptService.deleteScript(script);
      setState(() {});
    }
  }

  Widget _buildAboutTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Vivy Library', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(Strings.t('appVersion'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          Text(Strings.t('projectUrl'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {},
            child: const Text(
              'https://github.com/qingyue0906/vivy-library',
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
        Text(Strings.t('aspectRatio'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF616161))),
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
                  _gridSettings = _gridSettings.copyWith(aspectRatio: r);
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
        Text(Strings.t('itemsPerRow'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF616161))),
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
              _gridSettings = _gridSettings.copyWith(itemsPerRow: n.clamp(0, 20));
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
      SnackBar(content: Text(Strings.t('gridSaved')), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _exportData() async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: Strings.t('exportDirTitle'),
      );
      if (dir == null) return;

      final settings = await AppDataService.loadSettings();

      final export = {
        'version': '0.1.0',
        'exported_at': DateTime.now().toIso8601String(),
        'settings': settings,
      };

      final archive = Archive();
      archive.addFile(ArchiveFile('data.json', jsonEncode(export).codeUnits.length, utf8.encode(jsonEncode(export))));

      final scriptsMeta = widget.scriptService.scripts.map((s) => s.toJson()).toList();
      archive.addFile(ArchiveFile('scripts.json', jsonEncode(scriptsMeta).codeUnits.length, utf8.encode(jsonEncode(scriptsMeta))));

      final scriptsDir = _resolveScriptsDir();
      final scriptsFolder = Directory(scriptsDir);
      if (await scriptsFolder.exists()) {
        await for (final f in scriptsFolder.list()) {
          if (f is File && f.path.endsWith('.py')) {
            final bytes = await f.readAsBytes();
            final name = _basename(f.path);
            archive.addFile(ArchiveFile('scripts/$name', bytes.length, bytes));
          }
        }
      }

      final zipBytes = ZipEncoder().encode(archive);
      final outPath = '$dir/vivy_library_export.zip';
      await File(outPath).writeAsBytes(zipBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Strings.tn('exportedTo', {'path': outPath})),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.tn('exportFailed', {'error': '$e'})), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _importData() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: Strings.t('importFileTitle'),
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path!;

      final file = File(path);
      if (!file.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Strings.t('fileNotExist')), duration: const Duration(seconds: 2)),
          );
        }
        return;
      }

      final zipBytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      String? dataJson;
      String? scriptsMetaJson;
      for (final entry in archive) {
        if (entry.isFile) {
          if (entry.name == 'data.json') {
            dataJson = utf8.decode(entry.content);
          } else if (entry.name == 'scripts.json') {
            scriptsMetaJson = utf8.decode(entry.content);
          }
        }
      }

      if (dataJson == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Strings.t('invalidImportFile')), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final data = jsonDecode(dataJson) as Map;
      if (data['settings'] != null) {
        final importedSettings = data['settings'] as Map<String, dynamic>;
        final oldTheme = importedSettings['theme_mode'] as String?;
        if (oldTheme != null) {
          final themeMode = ThemeMode.values.firstWhere((e) => e.name == oldTheme, orElse: () => ThemeMode.system);
          await SettingsService.saveThemeMode(themeMode);
          widget.onThemeChanged(themeMode);
        }
        final oldGrid = importedSettings['grid_minCardWidth'];
        if (oldGrid != null) {
          final gs = GridSettings.fromMap({
            'minCardWidth': importedSettings['grid_minCardWidth'],
            'maxCardWidth': importedSettings['grid_maxCardWidth'],
            'aspectRatio': importedSettings['grid_aspectRatio'],
            'itemsPerRow': importedSettings['grid_itemsPerRow'],
            'compactLevel': importedSettings['grid_compactLevel'],
            'cardGifMode': importedSettings['grid_cardGifMode'],
            'fileGifMode': importedSettings['grid_fileGifMode'],
          });
          await SettingsService.saveGridSettings(gs);
          widget.onGridSettingsChanged(gs);
        }
        if (importedSettings['layout_leftPanelWidth'] != null) {
          final l = LayoutState.fromMap({
            'leftPanelWidth': (importedSettings['layout_leftPanelWidth'] as num?)?.toDouble(),
            'rightPanelWidth': (importedSettings['layout_rightPanelWidth'] as num?)?.toDouble(),
            'filePanelHeight': (importedSettings['layout_filePanelHeight'] as num?)?.toDouble(),
          });
          await SettingsService.saveLayout(l);
        }
        if (importedSettings['window_dx'] != null) {
          final w = WindowState.fromMap({
            'dx': (importedSettings['window_dx'] as num?)?.toDouble(),
            'dy': (importedSettings['window_dy'] as num?)?.toDouble(),
            'width': (importedSettings['window_width'] as num?)?.toDouble(),
            'height': (importedSettings['window_height'] as num?)?.toDouble(),
          });
          await SettingsService.saveWindowState(w);
        }
        final rootsStr = importedSettings['library_roots'] as String?;
        if (rootsStr != null) {
          try {
            final roots = (jsonDecode(rootsStr) as List)
                .map((r) => LibraryRoot(name: r['name'] as String, path: r['path'] as String))
                .toList();
            await LibraryRootService().saveAll(roots);
          } catch (_) {}
        }
      }

      if (scriptsMetaJson != null) {
        final scriptsList = (jsonDecode(scriptsMetaJson) as List)
            .map((e) => ScriptEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        final scriptsDirPath = _resolveScriptsDir();
        await Directory(scriptsDirPath).create(recursive: true);
        for (final entry in archive) {
          if (entry.isFile && entry.name.startsWith('scripts/')) {
            final fileName = entry.name.substring('scripts/'.length);
            if (fileName.isNotEmpty) {
              await File('$scriptsDirPath/$fileName').writeAsBytes(entry.content);
            }
          }
        }
        await widget.scriptService.replaceAllScripts(scriptsList);
      }

      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.t('dataImported')), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.tn('importFailed', {'error': '$e'})), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _clearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('confirmClear'), style: const TextStyle(fontSize: 13)),
        content: Text(Strings.t('confirmClearMsg'),
            style: const TextStyle(fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Strings.t('cancel'), style: const TextStyle(fontSize: 12)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(Strings.t('confirm'), style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await AppDataService.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.t('dataCleared')), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.tn('clearFailed', {'error': '$e'})), backgroundColor: Colors.red),
        );
      }
    }
  }
}
