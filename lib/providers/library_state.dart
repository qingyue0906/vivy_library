import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/category_node.dart';
import '../models/library_item.dart';
import '../models/item_info.dart';
import '../models/goto_entry.dart';
import '../models/direct_file.dart';
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

  // 左侧文件夹树的展开状态（已从 widget 层上移，便于刷新/编辑后保留）。
  final Set<String> _expandedPaths = {};

  bool _initialized = false;

  bool _fileBrowserVisible = false;
  bool _showSystemFiles = false;

  final Set<String> _selectedPaths = {};
  String? _selectionAnchorPath;

  // 文件夹多选状态（与项目多选分开，二者互斥）
  final Set<String> _selectedFolderPaths = {};
  String? _folderSelectionAnchorPath;

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
  Set<String> get expandedPaths => Set.unmodifiable(_expandedPaths);
  Set<String> get selectedPaths => Set.unmodifiable(_selectedPaths);
  Set<String> get selectedFolderPaths =>
      Set.unmodifiable(_selectedFolderPaths);

  CategoryNode get categoryRoot => _categoryRoot;

  List<LibraryItem> get selectedItems =>
      _allItems.where((e) => _selectedPaths.contains(e.path)).toList();

  List<CategoryNode> get selectedFolders => _selectedFolderPaths
      .map((p) => _categoryRoot.findByPath(p))
      .whereType<CategoryNode>()
      .toList();

  /// 当前选中文件夹是否在中间区显示"直接子文件夹 + 直接项目"。
  /// - null（全部项目）：不显示子文件夹。
  /// - 根目录：无展开概念，恒显示直接内容。
  /// - 普通文件夹：折叠时不显示子文件夹（中间区递归显示其全部项目），
  ///   展开时显示直接子文件夹 + 直接项目。
  bool get _selectedShowsSubDirs {
    if (_selectedCategoryPath == null) return false;
    if (_selectedCategoryPath == _categoryRoot.path) return true;
    return _expandedPaths.contains(_selectedCategoryPath!);
  }

  /// 当前选中分类下的项目集合（供网格与 class 导航统一取数）。
  /// - null（全部项目）：全库。
  /// - 文件夹展开 / 根目录：仅直接项目。
  /// - 文件夹折叠：该文件夹下所有递归项目。
  List<LibraryItem> get _itemsInSelectedCategory {
    if (_selectedCategoryPath == null) return _allItems;
    if (_selectedShowsSubDirs) {
      return _allItems
          .where((e) => e.categoryPath == _selectedCategoryPath)
          .toList();
    }
    final node = _categoryRoot.findByPath(_selectedCategoryPath!);
    if (node == null) {
      // 节点已不存在（如刚被删/改名），回退到精确匹配。
      return _allItems
          .where((e) => e.categoryPath == _selectedCategoryPath)
          .toList();
    }
    final paths = node.allItems.map((e) => e.path).toSet();
    return _allItems.where((e) => paths.contains(e.path)).toList();
  }

  /// 当前选中文件夹的直接子文件夹。
  /// 仅当展开态下（或选中根目录）才返回；折叠/"全部"时返回空。
  List<CategoryNode> get currentSubDirs {
    if (!_selectedShowsSubDirs) return [];
    final node = _categoryRoot.findByPath(_selectedCategoryPath!);
    return node?.subDirs ?? [];
  }

  /// 当前选中文件夹下的直接文件（非项目）。
  /// 仅当展开态下（或选中根目录）才返回；折叠/"全部"时返回空。
  List<DirectFile> get currentDirectFiles {
    if (!_selectedShowsSubDirs) return [];
    final node = _categoryRoot.findByPath(_selectedCategoryPath!);
    return node?.files ?? [];
  }

  /// 顶部 class 导航的选项列表，只统计当前左侧分类下的项目。
  List<MapEntry<String, int>> get classNavOptions {
    final inCategory = _itemsInSelectedCategory;

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

  List<String> get uniqueTypes {
    return _itemsInSelectedCategory
        .map((e) => e.info.type)
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> get uniqueContentRatings {
    return _itemsInSelectedCategory
        .map((e) => e.info.contentRating)
        .where((r) => r.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> get uniqueCreators {
    return _itemsInSelectedCategory
        .map((e) => e.info.creator)
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();
  }

  List<String> get uniqueClasses {
    return _itemsInSelectedCategory
        .expand((e) => e.info.classes)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> get uniqueTags {
    return _itemsInSelectedCategory
        .expand((e) => e.info.tags)
        .toSet()
        .toList()
      ..sort();
  }

  List<LibraryItem> get filteredAndSortedItems {
    var result = _itemsInSelectedCategory;

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
    _selectedFolderPaths.clear();
    _fileBrowserVisible = false;
    if (path != null) {
      _selectedFolder = _categoryRoot.findByPath(path);
    }
    notifyListeners();
  }

  /// 在左侧目录树中定位并选中 [folderPath]，同时自动展开所有祖先节点，
  /// 并清空项目和文件夹的选中状态。
  void locateInTree(String folderPath) {
    final ancestors = _categoryRoot.ancestorPaths(folderPath);
    _expandedPaths.addAll(ancestors);
    _selectedCategoryPath = folderPath;
    _selectedClass = '全部';
    _selectedItem = null;
    _selectedPaths.clear();
    _selectedFolderPaths.clear();
    _selectedFolder = _categoryRoot.findByPath(folderPath);
    _fileBrowserVisible = false;
    notifyListeners();
  }

  /// 切换左侧文件夹节点的展开/收起状态。
  void toggleExpand(String path) {
    if (_expandedPaths.contains(path)) {
      _expandedPaths.remove(path);
    } else {
      _expandedPaths.add(path);
    }
    notifyListeners();
  }

  void setSelectedClass(String className) {
    _selectedClass = className;
    _selectedItem = null;
    _selectedPaths.clear();
    _selectedFolderPaths.clear();
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
    _selectedFolderPaths.clear();
    _fileBrowserVisible = true;
    notifyListeners();
  }

  /// 选中一个文件夹节点（用于单击文件夹卡片：显示文件夹 info，不进底部）。
  void setSelectedFolder(CategoryNode node) {
    _selectedFolder = node;
    _selectedItem = null;
    _selectedPaths.clear();
    _selectedFolderPaths
      ..clear()
      ..add(node.path);
    _folderSelectionAnchorPath = node.path;
    _fileBrowserVisible = false;
    notifyListeners();
  }

  bool isFolderSelected(String path) => _selectedFolderPaths.contains(path);

  void toggleFolderSelection(CategoryNode node) {
    if (_selectedFolderPaths.contains(node.path)) {
      _selectedFolderPaths.remove(node.path);
      if (_selectedFolder?.path == node.path) _selectedFolder = null;
    } else {
      _selectedFolderPaths.add(node.path);
      _selectedFolder = node;
      _folderSelectionAnchorPath = node.path;
    }
    _selectedItem = null;
    _selectedPaths.clear();
    _fileBrowserVisible = false;
    notifyListeners();
  }

  void selectFolderRange(CategoryNode node, List<CategoryNode> currentList) {
    if (_folderSelectionAnchorPath == null) {
      setSelectedFolder(node);
      return;
    }
    final anchorIndex = currentList
        .indexWhere((e) => e.path == _folderSelectionAnchorPath);
    final targetIndex = currentList.indexWhere((e) => e.path == node.path);
    if (anchorIndex == -1 || targetIndex == -1) {
      setSelectedFolder(node);
      return;
    }
    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;

    _selectedFolderPaths
      ..clear()
      ..addAll(currentList.sublist(start, end + 1).map((e) => e.path));
    _selectedFolder = node;
    _selectedItem = null;
    _selectedPaths.clear();
    _fileBrowserVisible = false;
    notifyListeners();
  }

  void selectAllFolders(List<CategoryNode> currentList) {
    _selectedFolderPaths
      ..clear()
      ..addAll(currentList.map((e) => e.path));
    _selectedFolder = currentList.isNotEmpty ? currentList.last : null;
    _selectedItem = null;
    _selectedPaths.clear();
    _fileBrowserVisible = false;
    notifyListeners();
  }

  void selectFolderForContextMenu(CategoryNode node) {
    if (!_selectedFolderPaths.contains(node.path)) {
      _selectedFolderPaths
        ..clear()
        ..add(node.path);
      _selectedFolder = node;
      _selectedItem = null;
      _selectedPaths.clear();
      notifyListeners();
    }
  }

  /// 通过 uuid 选中项目（goto 点击）。找不到返回 false，调用方提示。
  bool selectByUuid(String uuid) {
    final item = _itemByUuid[uuid];
    if (item == null) return false;
    setSelectedItem(item);
    return true;
  }

  /// 通过相对路径选中嵌套 item（goto 点击 path 型）。
  /// [currentItemPath] 是当前选中项目的绝对路径，[relativePath] 是相对它的路径。
  /// 即时扫描构建临时 LibraryItem 显示。找不到返回 false。
  Future<bool> selectByGotoPath(String currentItemPath, String relativePath) async {
    final sep = Platform.pathSeparator;
    final target = '$currentItemPath$sep$relativePath';
    final dir = Directory(target);
    if (!await dir.exists()) return false;
    try {
      final item = await LibraryScanner().buildSingleItem(
        category: _baseName(currentItemPath),
        categoryPath: currentItemPath,
        folderName: _baseName(target),
        itemPath: target,
      );
      setSelectedItem(item);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _baseName(String p) =>
      p.replaceAll('\\', '/').split('/').last;

  void toggleItemSelection(LibraryItem item) {
    if (_selectedPaths.contains(item.path)) {
      _selectedPaths.remove(item.path);
      if (_selectedItem?.path == item.path) _selectedItem = null;
    } else {
      _selectedPaths.add(item.path);
      _selectedItem = item;
      _selectionAnchorPath = item.path;
    }
    _selectedFolderPaths.clear();
    _selectedFolder = null;
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
    _selectedFolderPaths.clear();
    _selectedFolder = null;
    notifyListeners();
  }

  void selectAll(List<LibraryItem> currentList) {
    _selectedPaths
      ..clear()
      ..addAll(currentList.map((e) => e.path));
    _selectedItem = currentList.isNotEmpty ? currentList.last : null;
    _selectedFolderPaths.clear();
    _selectedFolder = null;
    notifyListeners();
  }

  void selectItemForContextMenu(LibraryItem item) {
    if (!_selectedPaths.contains(item.path)) {
      _selectedPaths
        ..clear()
        ..add(item.path);
      _selectedItem = item;
      _selectedFolderPaths.clear();
      _selectedFolder = null;
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
    final defineChanged = oldItem.info.define != finalInfo.define;

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

    // define 变化（item/dir/hide 之间任意切换）需要重扫以更新树结构
    return defineChanged;
  }

  /// 保存文件夹（CategoryNode）的 info.json。返回 define 是否变化（需重扫）。
  Future<bool> saveFolderInfo(String folderPath, ItemInfo newInfo) async {
    // uuid 为空时自动生成
    ItemInfo finalInfo = newInfo;
    if (newInfo.uuid == null || newInfo.uuid!.isEmpty) {
      finalInfo = newInfo.copyWith(uuid: const Uuid().v4());
    }

    final jsonFile = File('$folderPath${Platform.pathSeparator}info.json');
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(finalInfo.toJson()),
    );

    // 更新树中的节点 info
    final node = _categoryRoot.findByPath(folderPath);
    final defineChanged = node?.info?.define != finalInfo.define;
    if (node != null) {
      _categoryRoot = _updateFolderInfoInTree(_categoryRoot, folderPath, finalInfo);
    }
    if (_selectedFolder?.path == folderPath) {
      _selectedFolder = _categoryRoot.findByPath(folderPath);
    }
    notifyListeners();
    return defineChanged;
  }

  /// 递归更新树中某节点 info（不可变树需重建根）。
  CategoryNode _updateFolderInfoInTree(CategoryNode node, String targetPath, ItemInfo newInfo) {
    if (node.path == targetPath) {
      return node.copyWith(info: newInfo);
    }
    final newSubDirs = node.subDirs.map((sub) =>
        _updateFolderInfoInTree(sub, targetPath, newInfo)).toList();
    return node.copyWith(subDirs: newSubDirs);
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

    for (final path in itemPaths) {
      final index = _allItems.indexWhere((e) => e.path == path);
      if (index == -1) continue;
      final old = _allItems[index].info;

      if (old.define != (define ?? old.define)) {
        anyDefineChanged = true;
      }

      ItemInfo newInfo = old.copyWith(
        description: description,
        creator: creator,
        type: type,
        contentRating: contentRating,
        tags: _mergeList(old.tags, tags, tagsMode),
        classes: _mergeList(old.classes, classes, classMode),
        goto: _mergeGoto(old.goto, goto, gotoMode),
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

  /// 批量编辑文件夹：与 batchEditItems 字段对齐，用于多选文件夹卡片后的批量编辑。
  Future<bool> batchEditFolders({
    required List<String> folderPaths,
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

    for (final path in folderPaths) {
      final node = _categoryRoot.findByPath(path);
      final old = node?.info ?? ItemInfo.defaults(_baseName(path));

      if (old.define != (define ?? old.define)) {
        anyDefineChanged = true;
      }

      ItemInfo newInfo = old.copyWith(
        description: description,
        creator: creator,
        type: type,
        contentRating: contentRating,
        tags: _mergeList(old.tags, tags, tagsMode),
        classes: _mergeList(old.classes, classes, classMode),
        goto: _mergeGoto(old.goto, goto, gotoMode),
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

      _categoryRoot = _updateFolderInfoInTree(_categoryRoot, path, newInfo);

      if (_selectedFolder?.path == path) {
        _selectedFolder = _categoryRoot.findByPath(path);
      }
    }
    notifyListeners();
    return anyDefineChanged;
  }

  List<String> _mergeList(
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

  List<GotoEntry> _mergeGoto(
      List<GotoEntry> oldList, List<GotoEntry>? newList, String mode) {
    if (newList == null || newList.isEmpty) return oldList;
    switch (mode) {
      case 'overwrite':
        return newList;
      case 'append':
        final seen = <String>{};
        final result = <GotoEntry>[];
        for (final e in oldList.followedBy(newList)) {
          if (!seen.contains(e.dedupKey)) {
            seen.add(e.dedupKey);
            result.add(e);
          }
        }
        return result;
      case 'remove':
        final removeKeys = newList.map((e) => e.dedupKey).toSet();
        return oldList.where((e) => !removeKeys.contains(e.dedupKey)).toList();
      default:
        return oldList;
    }
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
    _selectedFolderPaths.clear();
    _expandedPaths.clear();
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

  /// 重扫当前资源库，保留当前选中的分类路径和搜索（不跳回开头）。
  /// 用于 define 变化后刷新树结构。
  Future<void> rescan() async {
    if (_currentRootPath.isEmpty) return;
    final keepCategoryPath = _selectedCategoryPath;
    final keepSearch = _searchQuery;
    _isLoading = true;
    notifyListeners();

    try {
      _categoryRoot = await LibraryScanner().scanAll(_currentRootPath);
      _allItems = _categoryRoot.allItems;
      _rebuildUuidIndex();
      // 保留展开态，仅清理已不存在的路径（文件夹可能被删/改名）。
      _expandedPaths.removeWhere((p) => _categoryRoot.findByPath(p) == null);
      // 恢复分类路径（若新树里不存在则置 null）
      if (keepCategoryPath != null &&
          _categoryRoot.findByPath(keepCategoryPath) == null) {
        _selectedCategoryPath = null;
      } else {
        _selectedCategoryPath = keepCategoryPath;
      }
      _selectedFolder = _selectedCategoryPath == null
          ? null
          : _categoryRoot.findByPath(_selectedCategoryPath!);
      _selectedItem = null;
      _selectedPaths.clear();
      _selectedFolderPaths.clear();
      _fileBrowserVisible = false;
      _searchQuery = keepSearch;
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
