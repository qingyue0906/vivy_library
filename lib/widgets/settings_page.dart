import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../services/app_data_service.dart';
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
  final void Function(Color? color) onAccentChanged;
  final void Function(SearchScope scope) onSearchScopeChanged;
  final SearchScope searchScope;

  const SettingsPage({
    super.key,
    required this.libraryRootPath,
    required this.onThemeChanged,
    required this.onGridSettingsChanged,
    required this.backgroundSettings,
    required this.onBackgroundChanged,
    required this.onLocaleChanged,
    required this.scriptService,
    required this.onAccentChanged,
    required this.onSearchScopeChanged,
    required this.searchScope,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  ThemeMode _themeMode = ThemeMode.system;
  Color? _accentColor;
  GridSettings _gridSettings = const GridSettings();
  late BackgroundSettings _bgSettings;
  late AppLocale _locale;
  late SearchScope _searchScope;
  bool _searchScopeExpanded = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this);
    _bgSettings = widget.backgroundSettings;
    _locale = Strings.currentLocale;
    _searchScope = widget.searchScope;
    _load();
  }

  Future<void> _load() async {
    final theme = await SettingsService.loadThemeMode();
    final grid = await SettingsService.loadGridSettings();
    final accent = await SettingsService.loadAccentColor();
    setState(() {
      _themeMode = theme;
      _gridSettings = grid;
      _accentColor = accent;
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
                      color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(locale.displayName, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
          SizedBox(
            height: 28,
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Text(Strings.t('searchScope'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  width: 60,
                  child: InkWell(
                    onTap: () => setState(() => _searchScopeExpanded = !_searchScopeExpanded),
                    child: Center(
                      child: Icon(
                        _searchScopeExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_searchScopeExpanded) ...[
            const SizedBox(height: 8),
            ..._buildSearchScopeToggles(),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildSearchScopeToggles() {
    const fields = [
      ('searchScopeUuid', 'uuid'),
      ('searchScopeDefine', 'define'),
      ('searchScopeTitle', 'title'),
      ('searchScopeDescription', 'description'),
      ('searchScopeCreator', 'creator'),
      ('searchScopeType', 'type'),
      ('searchScopeContentrating', 'contentrating'),
      ('searchScopeRating', 'rating'),
      ('searchScopeClass', 'class'),
      ('searchScopeTags', 'tags'),
      ('searchScopeStar', 'star'),
    ];
    return [
      for (final (labelKey, field) in fields)
        SizedBox(
          height: 28,
          child: Row(
            children: [
              SizedBox(
                width: 140,
                child: Text(Strings.t(labelKey), style: const TextStyle(fontSize: 12)),
              ),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: _searchScope.isEnabled(field),
                  onChanged: (v) {
                    final updated = _searchScope.copyWithEnabled(field, v);
                    _searchScope = updated;
                    SettingsService.saveSearchScope(updated);
                    widget.onSearchScopeChanged(updated);
                    setState(() {});
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
    ];
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
            _buildAccentSection(),
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
            value: (_gridSettings.compactLevel * 100).clamp(85.0, 125.0),
            min: 85,
            max: 125,
            divisions: 8,
            onChanged: (v) => setState(() {
              _gridSettings = _gridSettings.copyWith(compactLevel: v / 100);
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
          Transform.scale(
            scale: 0.75,
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
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Process.run('cmd', ['/c', 'start', 'https://github.com/qingyue0906/vivy_library']),
              child: const Text(
                'https://github.com/qingyue0906/vivy_library',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
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

  /// 预设强调色（null 表示"默认"，不覆盖）。
  static const List<(String, Color?)> _accentPresets = [
    ('accentDefault', null),
    ('accentDeepPurple', Color(0xFF6750A4)),
    ('accentBlue', Color(0xFF007ACC)),
    ('accentIndigo', Color(0xFF3F51B5)),
    ('accentTeal', Color(0xFF00897B)),
    ('accentGreen', Color(0xFF2E7D32)),
    ('accentOrange', Color(0xFFEF6C00)),
    ('accentPink', Color(0xFFC2185B)),
    ('accentRed', Color(0xFFD32F2F)),
    ('accentAmber', Color(0xFFFFB300)),
  ];

  void _setAccent(Color? color) {
    setState(() => _accentColor = color);
    SettingsService.saveAccentColor(color);
    widget.onAccentChanged(color);
  }

  Widget _buildAccentSection() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(Strings.t('accentColor'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(Strings.t('accentColorDesc'), style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (labelKey, color) in _accentPresets)
              _buildAccentSwatch(
                label: Strings.t(labelKey),
                color: color,
                selected: _accentColor == color,
                onTap: () => _setAccent(color),
              ),
            _buildCustomAccentSwatch(cs),
          ],
        ),
      ],
    );
  }

  Widget _buildAccentSwatch({
    required String label,
    required Color? color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final swatch = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.primaryContainer,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26, width: 1),
      ),
      child: color == null
          ? Icon(Icons.auto_awesome, size: 16, color: Theme.of(context).colorScheme.onPrimaryContainer)
          : null,
    );
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
          child: swatch,
        ),
      ),
    );
  }

  Widget _buildCustomAccentSwatch(ColorScheme cs) {
    final selected = _accentColor != null &&
        !_accentPresets.any((p) => p.$2 == _accentColor);
    return Tooltip(
      message: Strings.t('customColor'),
      child: InkWell(
        onTap: () => _openColorPicker(cs),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? cs.primary : Colors.transparent,
              width: 3,
            ),
          ),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black12, width: 1),
              // 彩色渐变环示意"自定义"。
              gradient: const SweepGradient(
                colors: [
                  Colors.red, Colors.orange, Colors.yellow, Colors.green,
                  Colors.teal, Colors.blue, Colors.indigo, Colors.purple, Colors.red,
                ],
              ),
            ),
            child: Center(
              child: Icon(Icons.add, size: 16, color: cs.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openColorPicker(ColorScheme cs) async {
    // 自定义色块被选中时以其作为初始值，否则回退到当前强调色或蓝。
    final initial = _accentColor ??
        (cs.brightness == Brightness.dark ? const Color(0xFF007ACC) : Colors.deepPurple);
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => _ColorPickerDialog(initialColor: initial),
    );
    if (picked != null) _setAccent(picked);
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
              color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
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
      final dataBytes = utf8.encode(jsonEncode(export));
      archive.addFile(ArchiveFile('settings.json', dataBytes.length, dataBytes));

      final scriptsMeta = widget.scriptService.scripts.map((s) => s.toJson()).toList();
      final scriptsBytes = utf8.encode(jsonEncode(scriptsMeta));
      archive.addFile(ArchiveFile('scripts.json', scriptsBytes.length, scriptsBytes));

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
          if (entry.name == 'settings.json') {
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
        await AppDataService.saveSettings(importedSettings);

        final oldTheme = importedSettings['theme_mode'] as String?;
        if (oldTheme != null) {
          final themeMode = ThemeMode.values.firstWhere((e) => e.name == oldTheme, orElse: () => ThemeMode.system);
          widget.onThemeChanged(themeMode);
        }
        final accentVal = importedSettings['accent_color'] as String?;
        if (accentVal != null && accentVal.isNotEmpty) {
          final intVal = int.tryParse(accentVal);
          final importedAccent = intVal == null ? null : Color(intVal);
          _setAccent(importedAccent);
        }
        if (importedSettings['grid_minCardWidth'] != null) {
          widget.onGridSettingsChanged(GridSettings.fromMap({
            'minCardWidth': importedSettings['grid_minCardWidth'],
            'maxCardWidth': importedSettings['grid_maxCardWidth'],
            'aspectRatio': importedSettings['grid_aspectRatio'],
            'itemsPerRow': importedSettings['grid_itemsPerRow'],
            'compactLevel': importedSettings['grid_compactLevel'],
            'cardGifMode': importedSettings['grid_cardGifMode'],
            'fileGifMode': importedSettings['grid_fileGifMode'],
          }));
        }
        widget.onBackgroundChanged(BackgroundSettings.fromMap({
          'path': importedSettings['bg_path'],
          'leftOpacity': importedSettings['bg_leftOpacity'],
          'middleOpacity': importedSettings['bg_middleOpacity'],
          'rightOpacity': importedSettings['bg_rightOpacity'],
        }));
        final localeStr = importedSettings['app_locale'] as String?;
        if (localeStr != null) {
          final locale = AppLocale.values.firstWhere((e) => e.name == localeStr, orElse: () => AppLocale.system);
          widget.onLocaleChanged(locale);
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

class _ColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  const _ColorPickerDialog({required this.initialColor});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _pickerColor;
  final _rCtrl = TextEditingController();
  final _gCtrl = TextEditingController();
  final _bCtrl = TextEditingController();
  final _rFocus = FocusNode();
  final _gFocus = FocusNode();
  final _bFocus = FocusNode();

  int to255(double v) => (v * 255.0).round().clamp(0, 255);
  Color combine(int r, int g, int b) => Color.fromARGB(255, r, g, b);

  @override
  void initState() {
    super.initState();
    _pickerColor = widget.initialColor;
    _rCtrl.text = to255(_pickerColor.r).toString();
    _gCtrl.text = to255(_pickerColor.g).toString();
    _bCtrl.text = to255(_pickerColor.b).toString();
  }

  @override
  void dispose() {
    _rCtrl.dispose();
    _gCtrl.dispose();
    _bCtrl.dispose();
    _rFocus.dispose();
    _gFocus.dispose();
    _bFocus.dispose();
    super.dispose();
  }

  void _syncFields(Color c) {
    if (!_rFocus.hasFocus) _rCtrl.text = to255(c.r).toString();
    if (!_gFocus.hasFocus) _gCtrl.text = to255(c.g).toString();
    if (!_bFocus.hasFocus) _bCtrl.text = to255(c.b).toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Strings.t('pickColor'), style: const TextStyle(fontSize: 14)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorPicker(
              pickerColor: _pickerColor,
              onColorChanged: (c) {
                setState(() => _pickerColor = c);
                _syncFields(c);
              },
              enableAlpha: false,
              labelTypes: const [],
              pickerAreaBorderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _rgbField('R', _rCtrl, _rFocus,
                    (v) => _pickerColor = combine(v, to255(_pickerColor.g), to255(_pickerColor.b))),
                const SizedBox(width: 8),
                _rgbField('G', _gCtrl, _gFocus,
                    (v) => _pickerColor = combine(to255(_pickerColor.r), v, to255(_pickerColor.b))),
                const SizedBox(width: 8),
                _rgbField('B', _bCtrl, _bFocus,
                    (v) => _pickerColor = combine(to255(_pickerColor.r), to255(_pickerColor.g), v)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(Strings.t('cancel'), style: const TextStyle(fontSize: 12)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _pickerColor),
          child: Text(Strings.t('ok'), style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _rgbField(
    String label,
    TextEditingController ctrl,
    FocusNode focus,
    void Function(int) onValid,
  ) {
    return Expanded(
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: ctrl,
              focusNode: focus,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 3,
              decoration: const InputDecoration(
                isDense: true,
                counterText: '',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: (s) {
                final v = (int.tryParse(s) ?? 0).clamp(0, 255);
                onValid(v);
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }
}
