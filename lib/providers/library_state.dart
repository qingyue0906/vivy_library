import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/category_node.dart';
import '../models/library_item.dart';
import '../models/item_info.dart';
import '../models/goto_entry.dart';
import '../services/library_scanner.dart';
import '../services/settings_service.dart';

enum SortField { name, size, date }
enum SortOrder { ascending, descending }

class LibraryState extends ChangeNotifier {
  CategoryNode _categoryRoot = CategoryNode(path: '', name: '');
  List<LibraryItem> _allItems = [];
  Map<String, LibraryItem> _itemByUuid = {};
  bool _isLoading = true;
  String? _error;

  String _currentRootPath = '';

  String _searchQuery = '';
  String? _selectedCategoryPath; // null=全部，否则为文件夹绝对路径
  String _selectedClass = '全部';
  SortField _sortField = SortField.name;
  SortOrder _sortOrder = SortOrder.ascending;

  LibraryItem? _selectedItem;
  CategoryNode? _selectedFolder; // 选中的文件夹节点（用于右侧显示文件夹 info）

  bool _initialized = false;

  bool _fileBrowserVisible = false;
  bool _showSystemFiles = false;

  final Set<String> _selectedPaths = {};
  String? _selectionAnchorPath;

  bool get isLoading => _isLoading;
  String? get error => _error;
  String get currentRootPath => _currentRootPath;
  String get searchQuery => _searchQuery;
  String? get selectedCategoryPath => _selectedCategoryPath;
  String? get selectedCategoryName {
    if (_selectedCategoryPath == null) return null;
    return _categoryRoot.findByPath(_selectedCategoryPath!)?.name;
  }
  String get selectedClass => _selectedClass;
  SortField get sortField => _sortField;
  SortOrder get sortOrder => _sortOrder;
  LibraryItem? get selectedItem => _selectedItem;
  CategoryNode? get selectedFolder => _selectedFolder;
  Set<String> get selectedPaths => Set.unmodifiable(_selectedPaths);

  CategoryNode get categoryRoot => _categoryRoot;

  List<LibraryItem> get selectedItems =>
      _allItems.where((e) => _selectedPaths.contains(e.path)).toList();

  /// 当前选中文件夹的直接子文件夹（"全部"时返回空）。
  List<CategoryNode> get currentSubDirs {
    if (_selectedCategoryPath == null) return [];
    final node = _categoryRoot.findByPath(_selectedCategoryPath!);
    return node?.subDirs ?? [];
  }

  /// 顶部 class 导航的选项列表，只统计当前左侧分类下的项目。
  List<MapEntry<String, int>> get classNavOptions {
    final inCategory = _selectedCategoryPath == null
        ? _allItems
        : _allItems.where((e) => e.categoryPath == _selectedCategoryPath).toList();

    int totalCount = inCategory.length;
    int uncategorizedCount = 0;
    final classCounts = <String, int>{};

    for (final item in inCategory) {
      final classes = item.info.classes;
      if (classes.isEmpty) {
        uncategorizedCount++;
      } else {
        for (final c in classes) {
          classCounts[c] = (classCounts[c] ?? 0) + 1;
        }
      }
    }

    final sortedClassNames = classCounts.keys.toList()..sort();

    return [
      MapEntry('全部', totalCount),
      MapEntry('未分类', uncategorizedCount),
      ...sortedClassNames.map((c) => MapEntry(c, classCounts[c]!)),
    ];
  }

  List<LibraryItem> get filteredAndSortedItems {
    var result = _allItems;
    // 1 分类筛选：按 categoryPath 精确匹配（"全部"时不过滤）
    if (_selectedCategoryPath != null) {
      result = result.where((e) => e.categoryPath == _selectedCategoryPath).toList();
    }

    // 1.5 顶部 class 导航筛选
    if (_selectedClass == '未分类') {
      result = result.where((e) => e.info.classes.isEmpty).toList();
    } else if (_selectedClass != '全部') {
      result =
          result.where((e) => e.info.classes.contains(_selectedClass)).toList();
    }

    // 2 搜索过滤
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((item) {
        final info = item.info;
        return info.title.toLowerCase().contains(query) ||
            info.description.toLowerCase().contains(query) ||
            (info.creator?.toLowerCase().contains(query) ?? false) ||
            info.tags.any((t) => t.toLowerCase().contains(query)) ||
            info.classes.any((c) => c.toLowerCase().contains(query));
      }).toList();
    }
    result.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case SortField.name:
          cmp = a.info.title.compareTo(b.info.title);
        case SortField.size:
          cmp = a.sizeInBytes.compareTo(b.sizeInBytes);
        case SortField.date:
          cmp = a.modifiedTime.compareTo(b.modifiedTime);
      }
      return _sortOrder == SortOrder.ascending ? cmp : -cmp;
    });
    return result;
  }

  bool get fileBrowserVisible => _fileBrowserVisible;
  bool get showSystemFiles => _showSystemFiles;

  void showFileBrowser() {
    _fileBrowserVisible = true;
    notifyListeners();
  }

  void hideFileBrowser() {
    _fileBrowserVisible = false;
    notifyListeners();
  }

  void toggleSystemFiles() {
    _showSystemFiles = !_showSystemFiles;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// 选中左侧文件夹（null=全部）。
  void setSelectedCategory(String? path) {
    _selectedCategoryPath = path;
    _selectedClass = '全部';
    _selectedItem = null;
    _selectedFolder = null;
    _selectedPaths.clear();
    _fileBrowserVisible = false;
    if (path != null) {
      _selectedFolder = _categoryRoot.findByPath(path);
    }
    notifyListeners();
  }

  void setSelectedClass(String className) {
    _selectedClass = className;
    _selectedItem = null;
    _selectedPaths.clear();
    _fileBrowserVisible = false;
    notifyListeners();
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final (field, order) = await SettingsService.loadSortPreferences();
    _sortField = field;
    _sortOrder = order;
    notifyListeners();
  }

  void setSortField(SortField field) {
    _sortField = field;
    SettingsService.saveSortPreferences(_sortField, _sortOrder);
    notifyListeners();
  }

  void toggleSortOrder() {
    _sortOrder = _sortOrder == SortOrder.ascending
        ? SortOrder.descending
        : SortOrder.ascending;
    SettingsService.saveSortPreferences(_sortField, _sortOrder);
    notifyListeners();
  }

  void setSelectedItem(LibraryItem item) {
    _selectedItem = item;
    _selectedFolder = null;
    _selectedPaths
      ..clear()
      ..add(item.path);
    _selectionAnchorPath = item.path;
    _fileBrowserVisible = true;
    notifyListeners();
  }

  /// 选中一个文件夹节点（用于单击文件夹卡片：显示文件夹 info，不进底部）。
  void setSelectedFolder(CategoryNode node) {
    _selectedFolder = node;
    _selectedItem = null;
    _selectedPaths.clear();
    _fileBrowserVisible = false;
    notifyListeners();
  }

  /// 通过 uuid 选中项目（goto 点击）。找不到返回 false，调用方提示。
  bool selectByUuid(String uuid) {
    final item = _itemByUuid[uuid];
    if (item == null) return false;
    setSelectedItem(item);
    return true;
  }

  void toggleItemSelection(LibraryItem item) {
    if (_selectedPaths.contains(item.path)) {
      _selectedPaths.remove(item.path);
      if (_selectedItem?.path == item.path) _selectedItem = null;
    } else {
      _selectedPaths.add(item.path);
      _selectedItem = item;
      _selectionAnchorPath = item.path;
    }
    notifyListeners();
  }

  void selectRange(LibraryItem item, List<LibraryItem> currentList) {
    if (_selectionAnchorPath == null) {
      setSelectedItem(item);
      return;
    }

    final anchorIndex =
        currentList.indexWhere((e) => e.path == _selectionAnchorPath);
    final targetIndex = currentList.indexWhere((e) => e.path == item.path);
    if (anchorIndex == -1 || targetIndex == -1) {
      setSelectedItem(item);
      return;
    }

    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;

    _selectedPaths
      ..clear()
      ..addAll(currentList.sublist(start, end + 1).map((e) => e.path));
    _selectedItem = item;
    notifyListeners();
  }

  void selectAll(List<LibraryItem> currentList) {
    _selectedPaths
      ..clear()
      ..addAll(currentList.map((e) => e.path));
    _selectedItem = currentList.isNotEmpty ? currentList.last : null;
    notifyListeners();
  }

  void selectItemForContextMenu(LibraryItem item) {
    if (!_selectedPaths.contains(item.path)) {
      _selectedPaths
        ..clear()
        ..add(item.path);
      _selectedItem = item;
      notifyListeners();
    }
  }

  bool isItemSelected(String path) => _selectedPaths.contains(path);

  /// 保存单项编辑结果：用新的 ItemInfo 替换对应项目的 info,并写回 info.json。
  /// uuid 为空时自动生成。
  Future<bool> saveItemInfo(String itemPath, ItemInfo newInfo) async {
    final index = _allItems.indexWhere((e) => e.path == itemPath);
    if (index == -1) return false;

    // uuid 为空时自动生成
    ItemInfo finalInfo = newInfo;
    if (newInfo.uuid == null || newInfo.uuid!.isEmpty) {
      finalInfo = newInfo.copyWith(uuid: const Uuid().v4());
    }

    final jsonFile = File('$itemPath${Platform.pathSeparator}info.json');
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(finalInfo.toJson()),
    );

    final oldItem = _allItems[index];
    final wasDir = oldItem.info.define == 'dir';
    final isNowDir = finalInfo.define == 'dir';

    _allItems[index] = LibraryItem(
      category: oldItem.category,
      categoryPath: oldItem.categoryPath,
      folderName: oldItem.folderName,
      path: oldItem.path,
      info: finalInfo,
      previewPath: oldItem.previewPath,
      sizeInBytes: oldItem.sizeInBytes,
      modifiedTime: oldItem.modifiedTime,
    );
    _rebuildUuidIndex();

    if (_selectedItem?.path == itemPath) {
      _selectedItem = _allItems[index];
    }

    notifyListeners();

    // define 变化（item↔dir）需要重扫以更新树结构
    return wasDir != isNowDir;
  }

  /// 批量编辑:对所有选中项应用同一批字段变更。
  /// 列表字段（tags/classes/goto）支持 overwrite/append/remove 模式。
  /// 返回是否有 define 变化（需要重扫）。
  Future<bool> batchEditItems({
    required List<String> itemPaths,
    String? description,
    String? creator,
    String? type,
    String? contentRating,
    List<String>? tags,
    List<String>? classes,
    List<GotoEntry>? goto,
    String? define,
    String? preview,
    bool? star,
    String classMode = 'overwrite',
    String tagsMode = 'overwrite',
    String gotoMode = 'overwrite',
  }) async {
    bool anyDefineChanged = false;

    List<String> mergeList(
        List<String> oldList, List<String>? newList, String mode) {
      if (newList == null || newList.isEmpty) return oldList;
      switch (mode) {
        case 'overwrite':
          return newList;
        case 'append':
          return {...oldList, ...newList}.toList();
        case 'remove':
          return oldList.where((e) => !newList.contains(e)).toList();
        default:
          return oldList;
      }
    }

    List<GotoEntry> mergeGoto(
        List<GotoEntry> oldList, List<GotoEntry>? newList, String mode) {
      if (newList == null || newList.isEmpty) return oldList;
      switch (mode) {
        case 'overwrite':
          return newList;
        case 'append':
          final seen = <String>{};
          final result = <GotoEntry>[];
          for (final e in oldList.followedBy(newList)) {
            if (!seen.contains(e.uuid)) {
              seen.add(e.uuid);
              result.add(e);
            }
          }
          return result;
        case 'remove':
          final removeUuids = newList.map((e) => e.uuid).toSet();
          return oldList.where((e) => !removeUuids.contains(e.uuid)).toList();
        default:
          return oldList;
      }
    }

    for (final path in itemPaths) {
      final index = _allItems.indexWhere((e) => e.path == path);
      if (index == -1) continue;
      final old = _allItems[index].info;

      final wasDir = old.define == 'dir';
      final newDefine = define ?? old.define;
      final isNowDir = newDefine == 'dir';
      if (wasDir != isNowDir) anyDefineChanged = true;

      ItemInfo newInfo = old.copyWith(
        description: description,
        creator: creator,
        type: type,
        contentRating: contentRating,
        tags: mergeList(old.tags, tags, tagsMode),
        classes: mergeList(old.classes, classes, classMode),
        goto: mergeGoto(old.goto, goto, gotoMode),
        define: define,
        preview: preview,
        star: star,
      );

      // uuid 为空时自动生成
      if (newInfo.uuid == null || newInfo.uuid!.isEmpty) {
        newInfo = newInfo.copyWith(uuid: const Uuid().v4());
      }

      final jsonFile = File('$path${Platform.pathSeparator}info.json');
      await jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(newInfo.toJson()),
      );

      final oldItem = _allItems[index];
      _allItems[index] = LibraryItem(
        category: oldItem.category,
        categoryPath: oldItem.categoryPath,
        folderName: oldItem.folderName,
        path: oldItem.path,
        info: newInfo,
        previewPath: oldItem.previewPath,
        sizeInBytes: oldItem.sizeInBytes,
        modifiedTime: oldItem.modifiedTime,
      );

      if (_selectedItem?.path == path) {
        _selectedItem = _allItems[index];
      }
    }
    _rebuildUuidIndex();
    notifyListeners();
    return anyDefineChanged;
  }

  void _rebuildUuidIndex() {
    _itemByUuid = {
      for (final item in _allItems)
        if (item.info.uuid != null && item.info.uuid!.isNotEmpty)
          item.info.uuid!: item,
    };
  }

  /// 重命名项目文件夹内的某个文件或子文件夹,重命名后刷新文件面板
  Future<String?> renameFile(String oldPath, String newName) async {
    try {
      final dirSegments = oldPath.replaceAll('\\', '/').split('/')
        ..removeLast();
      final newPath = '${dirSegments.join('/')}/$newName';
      final type = await FileSystemEntity.type(oldPath);
      if (type == FileSystemEntityType.directory) {
        await Directory(oldPath).rename(newPath);
      } else {
        await File(oldPath).rename(newPath);
      }
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> scan(String rootDir) async {
    _currentRootPath = rootDir;
    _isLoading = true;
    _error = null;
    _selectedCategoryPath = null;
    _selectedClass = '全部';
    _selectedItem = null;
    _selectedFolder = null;
    _selectedPaths.clear();
    _fileBrowserVisible = false;
    notifyListeners();

    try {
      _categoryRoot = await LibraryScanner().scanAll(rootDir);
      _allItems = _categoryRoot.allItems;
      _rebuildUuidIndex();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void markNoLibrarySelected() {
    _isLoading = false;
    notifyListeners();
  }
}
