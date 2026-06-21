import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/library_item.dart';
import '../models/item_info.dart';
import '../services/library_scanner.dart';
import '../services/settings_service.dart';

enum SortField { name, size, date }
enum SortOrder { ascending, descending }

class LibraryState extends ChangeNotifier {
  List<LibraryItem> _allItems = [];
  bool _isLoading = true;
  String? _error;

  String _currentRootPath = '';

  String _searchQuery = '';
  String? _selectedCategory;
  String _selectedClass = '全部'; // 顶部 class 导航当前选中项,默认"全部"
  SortField _sortField = SortField.name;
  SortOrder _sortOrder = SortOrder.ascending;

  LibraryItem? _selectedItem;

  // 标记 init() 是否已完成,确保排序持久化只加载一次
  bool _initialized = false;

  bool _fileBrowserVisible = false;
  bool _showSystemFiles = false;

  // 多选用 Set 存路径而不是存对象引用,原因和 isSelected 判断一样:
  // 路径是稳定的唯一标识符,不依赖对象引用相等。
  final Set<String> _selectedPaths = {};
  String? _selectionAnchorPath; // Shift+点击区间选择的起点

  bool get isLoading => _isLoading;
  String? get error => _error;

  String get currentRootPath => _currentRootPath;

  String get searchQuery => _searchQuery;
  String? get selectedCategory => _selectedCategory;
  String get selectedClass => _selectedClass;  // 加对应 getter
  SortField get sortField => _sortField;
  SortOrder get sortOrder => _sortOrder;
  LibraryItem? get selectedItem => _selectedItem;
  Set<String> get selectedPaths => Set.unmodifiable(_selectedPaths);

  // 当前多选的完整 LibraryItem 列表,供编辑对话框使用
  List<LibraryItem> get selectedItems =>
      _allItems.where((e) => _selectedPaths.contains(e.path)).toList();

  List<String> get categories {
    final cats = _allItems.map((e) => e.category).toSet().toList();
    cats.sort();
    return cats;
  }

  /// 顶部 class 导航的选项列表,每项是 (标签名, 数量)。
  /// 只统计当前左侧分类(_selectedCategory)下的项目,这是这个导航栏
  /// 跟左侧分类筛选最大的不同:它是"分类内再分类",范围是级联的。
  List<MapEntry<String, int>> get classNavOptions {
    // 先按左侧分类筛一遍,作为统计范围(对应 Python 里先 category 过滤的那段)
    final inCategory = _selectedCategory == null
        ? _allItems
        : _allItems.where((e) => e.category == _selectedCategory).toList();

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

    // 按字母排序具体 class 名,"全部"和"未分类"固定排在最前面
    final sortedClassNames = classCounts.keys.toList()..sort();

    return [
      MapEntry('全部', totalCount),
      MapEntry('未分类', uncategorizedCount),
      ...sortedClassNames.map((c) => MapEntry(c, classCounts[c]!)),
    ];
  }

  List<LibraryItem> get filteredAndSortedItems {
    var result = _allItems;
    // 1 分类筛选
    if (_selectedCategory != null) {
      result = result.where((e) => e.category == _selectedCategory).toList();
    }

    // 1.5. 顶部 class 导航筛选,对应 Python 里 current_class 的判断逻辑
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

  void setSelectedCategory(String? category) {
    _selectedCategory = category;
    _selectedClass = '全部'; // 新增:切换左侧分类时,顶部 class 导航回到"全部"
    _selectedItem = null;
    _selectedPaths.clear();
    _fileBrowserVisible = false; // 切换分类时收起面板
    notifyListeners();
  }

  void setSelectedClass(String className) {
    _selectedClass = className;
    _selectedItem = null;
    _selectedPaths.clear();
    _fileBrowserVisible = false;
    notifyListeners();
  }

  /// 从持久化存储中恢复排序选项,仅在首次加载时执行
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
    _selectedPaths
      ..clear()
      ..add(item.path);
    _selectionAnchorPath = item.path; // 新增:更新锚点
    _fileBrowserVisible = true; // 选中时自动展开
    notifyListeners();
  }

  /// Ctrl+点击:切换某项的多选状态,不影响其他已选中项
  void toggleItemSelection(LibraryItem item) {
    if (_selectedPaths.contains(item.path)) {
      _selectedPaths.remove(item.path);
      // 如果取消选中的刚好是详情面板显示的那项,清空详情面板
      if (_selectedItem?.path == item.path) _selectedItem = null;
    } else {
      _selectedPaths.add(item.path);
      _selectedItem = item; // 详情面板显示最后一个 Ctrl+点击的项
      _selectionAnchorPath = item.path; // 新增:更新锚点
    }
    notifyListeners();
  }

  /// Shift+点击:从锚点(上一次单击的项)到这次点击的项之间,
  /// 按 currentList 给出的显示顺序整段选中。
  /// currentList 由调用方传入当前网格实际显示的列表(已过滤排序后的),
  /// 因为"区间"的含义依赖于用户当前看到的顺序,不是全量数据的顺序。
  void selectRange(LibraryItem item, List<LibraryItem> currentList) {
    if (_selectionAnchorPath == null) {
      // 没有锚点(比如这是第一次操作就直接 Shift+点),退化成单选
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

  /// Ctrl+A:全选当前网格显示的所有项
  void selectAll(List<LibraryItem> currentList) {
    _selectedPaths
      ..clear()
      ..addAll(currentList.map((e) => e.path));
    _selectedItem = currentList.isNotEmpty ? currentList.last : null;
    notifyListeners();
  }

  /// 右键点击某项时:
  /// 如果它不在多选集合里,就清空多选、只选它(跟你 Python 版本行为一致)
  /// 如果它已经在多选集合里,保持多选状态不变(右键批量编辑场景)
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

  /// 保存单项编辑结果:用新的 ItemInfo 替换对应项目的 info,并写回 info.json
  Future<void> saveItemInfo(String itemPath, ItemInfo newInfo) async {
    final index = _allItems.indexWhere((e) => e.path == itemPath);
    if (index == -1) return;

    // 写回 info.json
    final jsonFile =
        File('$itemPath${Platform.pathSeparator}info.json');
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(newInfo.toJson()),
    );

    // 用 copyWith 生成新的 LibraryItem(字段不可变,不能直接改)
    _allItems[index] =
        LibraryItem(
          category: _allItems[index].category,
          folderName: _allItems[index].folderName,
          path: _allItems[index].path,
          info: newInfo,
          previewPath: _allItems[index].previewPath,
          sizeInBytes: _allItems[index].sizeInBytes,
          modifiedTime: _allItems[index].modifiedTime,
        );

    // 如果详情面板正在显示这一项,同步更新
    if (_selectedItem?.path == itemPath) {
      _selectedItem = _allItems[index];
    }

    notifyListeners();
  }

  /// 批量编辑:对所有选中项应用同一批字段变更
  /// mode: 'overwrite'(覆盖) | 'append'(追加) | 'remove'(删除)
  /// 对应你 Python 版本里批量编辑对话框的三种操作模式
  Future<void> batchEditItems({
    required List<String> itemPaths,
    String? type,
    String? contentRating,
    List<String>? tags,
    List<String>? classes,
    required String mode,
  }) async {
    for (final path in itemPaths) {
      final index = _allItems.indexWhere((e) => e.path == path);
      if (index == -1) continue;
      final old = _allItems[index].info;

      List<String> mergeList(
          List<String> oldList, List<String>? newList) {
        if (newList == null || newList.isEmpty) return oldList;
        switch (mode) {
          case 'overwrite':
            return newList;
          case 'append':
            // 追加时去重
            return {...oldList, ...newList}.toList();
          case 'remove':
            return oldList.where((e) => !newList.contains(e)).toList();
          default:
            return oldList;
        }
      }

      final newInfo = old.copyWith(
        type: type != null && mode == 'overwrite' ? type : old.type,
        contentRating: contentRating != null && mode == 'overwrite'
            ? contentRating
            : old.contentRating,
        tags: mergeList(old.tags, tags),
        classes: mergeList(old.classes, classes),
      );

      await saveItemInfo(path, newInfo);
    }
  }

  /// 重命名项目文件夹内的某个文件,重命名后刷新文件面板
  Future<String?> renameFile(String oldPath, String newName) async {
    try {
      final file = File(oldPath);
      final dirSegments = oldPath.replaceAll('\\', '/').split('/')
        ..removeLast();
      final newPath = '${dirSegments.join('/')}/$newName';
      await file.rename(newPath);
      notifyListeners(); // 触发文件面板重建,显示新文件名
      return null; // 返回 null 表示成功,跟原来的约定一致
    } catch (e) {
      return e.toString(); // 返回错误信息字符串,表示失败
    }
  }

  Future<void> scan(String rootDir) async {
    _currentRootPath = rootDir;
    _isLoading = true;
    _error = null;
    // 切换资源库时重置所有筛选/选中状态,避免带着上一个库的筛选条件
    // 进入新库后出现"看起来没数据"的困惑(比如还选着上个库才有的 class 标签)
    _selectedCategory = null;
    _selectedClass = '全部';
    _selectedItem = null;
    _selectedPaths.clear();
    _fileBrowserVisible = false;
    notifyListeners();

    try {
      _allItems = await LibraryScanner().scanAll(rootDir);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 应用启动时如果没有可恢复的资源库路径,调用这个方法结束 loading 状态,
  /// 让界面显示"请选择资源库"的引导,而不是一直转圈
  void markNoLibrarySelected() {
    _isLoading = false;
    notifyListeners();
  }
}