import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/category_node.dart';
import '../models/library_item.dart';
import '../models/item_info.dart';
import '../models/goto_entry.dart';
import '../models/direct_file.dart';
import '../models/search_query.dart';
import '../services/library_scanner.dart';
import '../services/settings_service.dart';
import '../services/translations.dart';

class GroupedEntries<T> {
  final String groupLabel;
  final List<T> entries;
  const GroupedEntries(this.groupLabel, this.entries);
}

enum SortField { name, size, date }

enum SortOrder { ascending, descending }

class LibraryState extends ChangeNotifier {
  static const kAllClass = '__all__';
  static const kUnclassified = '__unclass__';
  CategoryNode _categoryRoot = CategoryNode(path: '', name: '');
  List<LibraryItem> _allItems = [];
  Map<String, LibraryItem> _itemByUuid = {};
  bool _isLoading = true;
  String? _error;

  String _currentRootPath = '';

  String _searchQuery = '';
  SearchScope _searchScope = SearchScope.defaults();
  ClassSource _classSource = ClassSource.class_;
  String? _selectedCategoryPath; // null=鍏ㄩ儴锛屽惁鍒欎负鏂囦欢澶圭粷瀵硅矾寰?
  String _selectedClass = kAllClass;
  SortField _sortField = SortField.name;
  SortOrder _sortOrder = SortOrder.ascending;
  bool _groupingEnabled = false;

  LibraryItem? _selectedItem;
  CategoryNode? _selectedFolder; // 閫変腑鐨勬枃浠跺す鑺傜偣锛堢敤浜庡彸渚ф樉绀烘枃浠跺す info锛?
  DirectFile? _selectedFile;

  // 宸︿晶鏂囦欢澶规爲鐨勫睍寮€鐘舵€侊紙宸蹭粠 widget 灞備笂绉伙紝渚夸簬鍒锋柊/缂栬緫鍚庝繚鐣欙級銆?
  final Set<String> _expandedPaths = {};

  bool _initialized = false;

  bool _fileBrowserVisible = false;
  bool _showSystemFiles = false;
  double _copyProgress = -1;
  String _copyStatus = '';

  final Set<String> _selectedPaths = {};
  String? _selectionAnchorPath;

  // 鏂囦欢澶瑰閫夌姸鎬侊紙涓庨」鐩閫夊垎寮€锛屼簩鑰呬簰鏂ワ級
  final Set<String> _selectedFolderPaths = {};
  String? _folderSelectionAnchorPath;

  bool get isLoading => _isLoading;
  String? get error => _error;
  String get currentRootPath => _currentRootPath;
  String get searchQuery => _searchQuery;
  SearchScope get searchScope => _searchScope;
  ClassSource get classSource => _classSource;
  bool get groupingEnabled => _groupingEnabled;
  double get copyProgress => _copyProgress;
  String get copyStatus => _copyStatus;
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
  DirectFile? get selectedFile => _selectedFile;
  Set<String> get expandedPaths => Set.unmodifiable(_expandedPaths);
  Set<String> get selectedPaths => Set.unmodifiable(_selectedPaths);
  Set<String> get selectedFolderPaths => Set.unmodifiable(_selectedFolderPaths);

  CategoryNode get categoryRoot => _categoryRoot;

  List<LibraryItem> get selectedItems =>
      _allItems.where((e) => _selectedPaths.contains(e.path)).toList();

  List<CategoryNode> get selectedFolders => _selectedFolderPaths
      .map((p) => _categoryRoot.findByPath(p))
      .whereType<CategoryNode>()
      .toList();

  /// 褰撳墠閫変腑鏂囦欢澶规槸鍚﹀湪涓棿鍖烘樉绀?鐩存帴瀛愭枃浠跺す + 鐩存帴椤圭洰"銆?
  /// - null锛堝叏閮ㄩ」鐩級锛氫笉鏄剧ず瀛愭枃浠跺す銆?
  /// - 鏍圭洰褰曪細鏃犲睍寮€姒傚康锛屾亽鏄剧ず鐩存帴鍐呭銆?
  /// - 鏅€氭枃浠跺す锛氭姌鍙犳椂涓嶆樉绀哄瓙鏂囦欢澶癸紙涓棿鍖洪€掑綊鏄剧ず鍏跺叏閮ㄩ」鐩級锛?
  ///   灞曞紑鏃舵樉绀虹洿鎺ュ瓙鏂囦欢澶?+ 鐩存帴椤圭洰銆?
  bool get _selectedShowsSubDirs {
    if (_selectedCategoryPath == null) return false;
    if (_selectedCategoryPath == _categoryRoot.path) return true;
    return _expandedPaths.contains(_selectedCategoryPath!);
  }

  /// 褰撳墠閫変腑鍒嗙被涓嬬殑椤圭洰闆嗗悎锛堜緵缃戞牸涓?class 瀵艰埅缁熶竴鍙栨暟锛夈€?
  /// - null锛堝叏閮ㄩ」鐩級锛氬叏搴撱€?
  /// - 鏂囦欢澶瑰睍寮€ / 鏍圭洰褰曪細浠呯洿鎺ラ」鐩€?
  /// - 鏂囦欢澶规姌鍙狅細璇ユ枃浠跺す涓嬫墍鏈夐€掑綊椤圭洰銆?
  List<LibraryItem> get _itemsInSelectedCategory {
    if (_selectedCategoryPath == null) return _allItems;
    if (_selectedShowsSubDirs) {
      return _allItems
          .where((e) => e.categoryPath == _selectedCategoryPath)
          .toList();
    }
    final node = _categoryRoot.findByPath(_selectedCategoryPath!);
    if (node == null) {
      // 鑺傜偣宸蹭笉瀛樺湪锛堝鍒氳鍒?鏀瑰悕锛夛紝鍥為€€鍒扮簿纭尮閰嶃€?
      return _allItems
          .where((e) => e.categoryPath == _selectedCategoryPath)
          .toList();
    }
    final paths = node.allItems.map((e) => e.path).toSet();
    return _allItems.where((e) => paths.contains(e.path)).toList();
  }

  /// 褰撳墠閫変腑鏂囦欢澶圭殑鐩存帴瀛愭枃浠跺す銆?
  /// 浠呭綋灞曞紑鎬佷笅锛堟垨閫変腑鏍圭洰褰曪級鎵嶈繑鍥烇紱鎶樺彔/"鍏ㄩ儴"鏃惰繑鍥炵┖銆?
  List<CategoryNode> get currentSubDirs {
    if (!_selectedShowsSubDirs) return [];
    final node = _categoryRoot.findByPath(_selectedCategoryPath!);
    final result = node?.subDirs ?? [];
    return result.toList()..sort((a, b) {
      final cmp = a.name.compareTo(b.name);
      return _sortOrder == SortOrder.ascending ? cmp : -cmp;
    });
  }

  /// 褰撳墠閫変腑鍒嗙被涓嬬殑鐩存帴鏂囦欢锛堥€昏緫涓?_itemsInSelectedCategory 瀵圭瓑锛夈€?
  /// - null锛堝叏閮ㄩ」鐩級锛氬叏搴撱€?
  /// - 鏂囦欢澶瑰睍寮€ / 鏍圭洰褰曪細浠呯洿鎺ユ枃浠躲€?
  /// - 鏂囦欢澶规姌鍙狅細璇ユ枃浠跺す涓嬫墍鏈夐€掑綊鏂囦欢銆?
  List<DirectFile> get currentDirectFiles {
    List<DirectFile> result;
    if (_selectedCategoryPath == null) {
      result = _categoryRoot.allFiles;
    } else if (_selectedShowsSubDirs) {
      final node = _categoryRoot.findByPath(_selectedCategoryPath!);
      result = node?.files.toList() ?? [];
    } else {
      final node = _categoryRoot.findByPath(_selectedCategoryPath!);
      result = node?.allFiles ?? [];
    }
    return result..sort((a, b) {
      int cmp;
      switch (_sortField) {
        case SortField.name:
          cmp = a.name.compareTo(b.name);
        case SortField.size:
          cmp = a.sizeInBytes.compareTo(b.sizeInBytes);
        case SortField.date:
          cmp = a.modifiedTime.compareTo(b.modifiedTime);
      }
      return _sortOrder == SortOrder.ascending ? cmp : -cmp;
    });
  }

  List<CategoryNode> get filteredSubDirs {
    var result = currentSubDirs;
    result = result.where((n) => _matchesClassFilter(n.info)).toList();
    if (_searchQuery.isNotEmpty) {
      final parsed = SearchQuery.parse(
        _searchQuery,
        knownFields: SearchScope.allFields,
      );
      if (!parsed.isEmpty) {
        result = result
            .where((n) => _matchesSearchForInfo(n.info, parsed))
            .toList();
      }
    }
    return result;
  }

  List<DirectFile> get filteredDirectFiles {
    if (_searchQuery.isNotEmpty) return const [];
    if (_selectedClass == kAllClass || _selectedClass == kUnclassified)
      return currentDirectFiles;
    if (_classSource == ClassSource.rating) return const [];
    return const [];
  }

  List<GroupedEntries<CategoryNode>> get groupedSubDirs {
    if (!_groupingEnabled) return [GroupedEntries('', filteredSubDirs)];
    return _groupBy(
      filteredSubDirs,
      (n) => _groupKey(n.name, n.modifiedTime, n.sizeInBytes),
    );
  }

  List<GroupedEntries<LibraryItem>> get groupedItems {
    if (!_groupingEnabled) return [GroupedEntries('', filteredAndSortedItems)];
    return _groupBy(
      filteredAndSortedItems,
      (i) => _groupKey(i.info.title, i.modifiedTime, i.sizeInBytes),
    );
  }

  List<GroupedEntries<DirectFile>> get groupedFiles {
    if (!_groupingEnabled) return [GroupedEntries('', filteredDirectFiles)];
    return _groupBy(
      filteredDirectFiles,
      (f) => _groupKey(f.name, f.modifiedTime, f.sizeInBytes),
    );
  }

  List<GroupedEntries<T>> _groupBy<T>(List<T> items, String Function(T) keyFn) {
    if (items.isEmpty) return [];
    final result = <GroupedEntries<T>>[];
    String? lastKey;
    List<T>? currentGroup;
    for (final item in items) {
      final key = keyFn(item);
      if (key != lastKey) {
        if (currentGroup != null)
          result.add(GroupedEntries(lastKey!, currentGroup));
        lastKey = key;
        currentGroup = [item];
      } else {
        currentGroup!.add(item);
      }
    }
    if (currentGroup != null)
      result.add(GroupedEntries(lastKey!, currentGroup));
    return result;
  }

  String _groupKey(String name, DateTime dt, int size) {
    switch (_sortField) {
      case SortField.name:
        if (name.isEmpty) return '#';
        final first = name[0].toUpperCase();
        if (RegExp(r'[A-Z]').hasMatch(first)) return first;
        if (RegExp(r'[0-9]').hasMatch(first)) return '0-9';
        return '#';
      case SortField.size:
        final mb = size / (1024 * 1024);
        if (mb < 4) return '< 4 MB';
        if (mb < 8) return '4 - 8 MB';
        if (mb < 16) return '8 - 16 MB';
        if (mb < 32) return '16 - 32 MB';
        if (mb < 64) return '32 - 64 MB';
        if (mb < 128) return '64 - 128 MB';
        if (mb < 256) return '128 - 256 MB';
        if (mb < 512) return '256 - 512 MB';
        if (mb < 1024) return '512 MB - 1 GB';
        if (mb < 2048) return '1 - 2 GB';
        if (mb < 4096) return '2 - 4 GB';
        if (mb < 8192) return '4 - 8 GB';
        if (mb < 16384) return '8 - 16 GB';
        if (mb < 32768) return '16 - 32 GB';
        if (mb < 65536) return '32 - 64 GB';
        return '> 64 GB';
      case SortField.date:
        return '${dt.year}${Strings.t('year')}${dt.month}${Strings.t('month')}${dt.day}${Strings.t('day')}';
    }
  }

  /// 椤堕儴 class 瀵艰埅鐨勯€夐」鍒楄〃锛岀粺璁″綋鍓嶅乏渚у垎绫讳笅鐨勯」鐩拰鏂囦欢澶广€?
  List<MapEntry<String, int>> get classNavOptions {
    final inCategory = _itemsInSelectedCategory;
    final inFolders = currentSubDirs;

    int totalCount = inCategory.length + inFolders.length;
    int uncategorizedCount = 0;
    final counts = <String, int>{};

    void add(String key) {
      counts[key] = (counts[key] ?? 0) + 1;
    }

    void addUncategorized() {
      uncategorizedCount++;
    }

    void processInfo(ItemInfo? info) {
      switch (_classSource) {
        case ClassSource.creator:
          final v = info?.creator;
          if (v == null || v.isEmpty) {
            addUncategorized();
          } else {
            add(v);
          }
        case ClassSource.type:
          final v = info?.type;
          if (v == null || v.isEmpty) {
            addUncategorized();
          } else {
            add(v);
          }
        case ClassSource.contentrating:
          final v = info?.contentRating;
          if (v == null || v.isEmpty) {
            addUncategorized();
          } else {
            add(v);
          }
        case ClassSource.rating:
          add((info?.rating ?? 0).toString());
        case ClassSource.class_:
          final vals = info?.classes ?? [];
          if (vals.isEmpty) {
            addUncategorized();
          } else {
            for (final v in vals) {
              add(v);
            }
          }
        case ClassSource.tags:
          final vals = info?.tags ?? [];
          if (vals.isEmpty) {
            addUncategorized();
          } else {
            for (final v in vals) {
              add(v);
            }
          }
      }
    }

    for (final item in inCategory) {
      processInfo(item.info);
    }
    for (final node in inFolders) {
      processInfo(node.info);
    }

    final sortedKeys = counts.keys.toList()..sort();

    final entries = <MapEntry<String, int>>[MapEntry(kAllClass, totalCount)];
    if (_classSource != ClassSource.rating) {
      entries.add(MapEntry(kUnclassified, uncategorizedCount));
    }
    for (final k in sortedKeys) {
      entries.add(MapEntry(k, counts[k]!));
    }
    return entries;
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
    return _itemsInSelectedCategory.expand((e) => e.info.tags).toSet().toList()
      ..sort();
  }

  List<LibraryItem> get filteredAndSortedItems {
    var result = _itemsInSelectedCategory;

    // 1.5 椤堕儴 class 瀵艰埅绛涢€夛紙鐢ㄦ湁鏁?info 浠ュ懡涓户鎵垮€硷級
    result = result
        .where((e) => _matchesClassFilter(effectiveInfo(e)))
        .toList();

    // 2 鎼滅储杩囨护
    if (_searchQuery.isNotEmpty) {
      final parsed = SearchQuery.parse(
        _searchQuery,
        knownFields: SearchScope.allFields,
      );
      if (!parsed.isEmpty) {
        result = result.where((item) => _matchesSearch(item, parsed)).toList();
      }
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

  bool _matchesClassFilter(ItemInfo? info) {
    if (_selectedClass == kAllClass) return true;
    switch (_classSource) {
      case ClassSource.creator:
        if (_selectedClass == kUnclassified)
          return info?.creator == null || (info?.creator ?? '').isEmpty;
        return info?.creator == _selectedClass;
      case ClassSource.type:
        if (_selectedClass == kUnclassified) return (info?.type ?? '').isEmpty;
        return info?.type == _selectedClass;
      case ClassSource.contentrating:
        if (_selectedClass == kUnclassified)
          return (info?.contentRating ?? '').isEmpty;
        return info?.contentRating == _selectedClass;
      case ClassSource.rating:
        return info?.rating.toString() == _selectedClass;
      case ClassSource.class_:
        if (_selectedClass == kUnclassified)
          return (info?.classes ?? []).isEmpty;
        return info?.classes.contains(_selectedClass) ?? false;
      case ClassSource.tags:
        if (_selectedClass == kUnclassified) return (info?.tags ?? []).isEmpty;
        return info?.tags.contains(_selectedClass) ?? false;
    }
  }

  bool _matchesSearch(LibraryItem item, SearchQuery parsed) {
    return _matchesSearchForInfo(effectiveInfo(item), parsed);
  }

  bool _matchesSearchForInfo(ItemInfo? info, SearchQuery parsed) {
    if (info == null)
      return parsed.freeTokens.isEmpty && parsed.qualified.isEmpty;
    final i = info;

    // 绮惧噯闄愬畾 (涓嶄緷璧栨悳绱㈣寖鍥村紑鍏?
    for (final e in parsed.qualified.entries) {
      final field = e.key;
      final value = e.value;
      final lv = value.toLowerCase();
      switch (field) {
        case 'uuid':
          if ((i.uuid ?? '').toLowerCase() != lv) return false;
        case 'define':
          if (i.define.toLowerCase() != lv) return false;
        case 'title':
          if (!i.title.toLowerCase().contains(lv)) return false;
        case 'description':
          if (!i.description.toLowerCase().contains(lv)) return false;
        case 'creator':
          if (!(i.creator ?? '').toLowerCase().contains(lv)) return false;
        case 'type':
          if (!i.type.toLowerCase().contains(lv)) return false;
        case 'contentrating':
          if (!i.contentRating.toLowerCase().contains(lv)) return false;
        case 'rating':
          {
            final r = int.tryParse(value);
            if (r == null || i.rating != r) return false;
          }
        case 'class':
          if (!i.classes.any((c) => c.toLowerCase().contains(lv))) return false;
        case 'tags':
          if (!i.tags.any((t) => t.toLowerCase().contains(lv))) return false;
        case 'star':
          {
            final b = _parseBool(value);
            if (b == null || i.star != b) return false;
          }
      }
    }

    // 瀹芥澗 token (闇€鍛戒腑鑷冲皯涓€涓紑鍚殑鑼冨洿瀛楁)
    for (final token in parsed.freeTokens) {
      bool tokenMatched = false;
      final lt = token.toLowerCase();
      if (_searchScope.isEnabled('uuid') &&
          (i.uuid ?? '').toLowerCase().contains(lt))
        tokenMatched = true;
      if (!tokenMatched &&
          _searchScope.isEnabled('define') &&
          i.define.toLowerCase().contains(lt))
        tokenMatched = true;
      if (!tokenMatched &&
          _searchScope.isEnabled('title') &&
          i.title.toLowerCase().contains(lt))
        tokenMatched = true;
      if (!tokenMatched &&
          _searchScope.isEnabled('description') &&
          i.description.toLowerCase().contains(lt))
        tokenMatched = true;
      if (!tokenMatched &&
          _searchScope.isEnabled('creator') &&
          (i.creator ?? '').toLowerCase().contains(lt))
        tokenMatched = true;
      if (!tokenMatched &&
          _searchScope.isEnabled('type') &&
          i.type.toLowerCase().contains(lt))
        tokenMatched = true;
      if (!tokenMatched &&
          _searchScope.isEnabled('contentrating') &&
          i.contentRating.toLowerCase().contains(lt))
        tokenMatched = true;
      if (!tokenMatched && _searchScope.isEnabled('rating')) {
        final r = int.tryParse(token);
        if (r != null && i.rating == r) tokenMatched = true;
      }
      if (!tokenMatched &&
          _searchScope.isEnabled('class') &&
          i.classes.any((c) => c.toLowerCase().contains(lt)))
        tokenMatched = true;
      if (!tokenMatched &&
          _searchScope.isEnabled('tags') &&
          i.tags.any((t) => t.toLowerCase().contains(lt)))
        tokenMatched = true;
      if (!tokenMatched && _searchScope.isEnabled('star')) {
        final b = _parseBool(token);
        if (b != null && i.star == b) tokenMatched = true;
      }
      if (!tokenMatched) return false;
    }

    return true;
  }

  static bool? _parseBool(String value) {
    switch (value.toLowerCase()) {
      case 'true':
      case 'yes':
      case '1':
        return true;
      case 'false':
      case 'no':
      case '0':
        return false;
      default:
        return null;
    }
  }

  /// 鍒ゆ柇 item 鏄惁鏈夎嚜宸辩殑 info.json锛? 涓彲缁ф壙瀛楁浠讳竴闈炲摠鍏靛€硷級銆?
  static bool _hasOwnInfo(LibraryItem item) {
    final i = item.info;
    return i.type.isNotEmpty ||
        i.contentRating.isNotEmpty ||
        i.rating > 0 ||
        i.classes.isNotEmpty ||
        i.tags.isNotEmpty;
  }

  /// 鑾峰彇鐖舵枃浠跺す鐨?ItemInfo銆?
  ItemInfo? parentInfoOf(String categoryPath) {
    return _categoryRoot.findByPath(categoryPath)?.info;
  }

  /// 鑾峰彇 item 鐨勬湁鏁?info锛氫笁閾惧洖閫€锛堣嚜韬?鈫?鐖舵枃浠跺す 鈫?纭紪鐮佷繚搴曪級銆?
  /// - 鏈夎嚜韬?info.json 鈫?涓嶇户鎵跨埗鏂囦欢澶癸紝浠呯┖瀛楁璧扮‖缂栫爜淇濆簳銆?
  /// - 鏃犺嚜韬?info.json 鈫?浠庣埗鏂囦欢澶圭户鎵?5 涓瓧娈碉紝鍐嶈蛋纭紪鐮佷繚搴曘€?
  ItemInfo effectiveInfo(LibraryItem item) {
    if (_hasOwnInfo(item)) {
      return item.info.inheritedFrom(ItemInfo.hardcodedDefaults);
    }
    final parentInfo = parentInfoOf(item.categoryPath);
    return item.info
        .inheritedFrom(parentInfo ?? ItemInfo.hardcodedDefaults)
        .inheritedFrom(ItemInfo.hardcodedDefaults);
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

  void setSearchScope(SearchScope scope) {
    _searchScope = scope;
    notifyListeners();
  }

  void setClassSource(ClassSource source) {
    _classSource = source;
    _selectedClass = kAllClass;
    SettingsService.saveClassSource(source);
    notifyListeners();
  }

  void setGroupingEnabled(bool v) {
    _groupingEnabled = v;
    SettingsService.saveGroupingEnabled(v);
    notifyListeners();
  }

  /// 閫変腑宸︿晶鏂囦欢澶癸紙null=鍏ㄩ儴锛夈€?
  void setSelectedCategory(String? path) {
    _selectedCategoryPath = path;
    _selectedClass = kAllClass;
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

  /// 鍦ㄥ乏渚х洰褰曟爲涓畾浣嶅苟閫変腑 [folderPath]锛屽悓鏃惰嚜鍔ㄥ睍寮€鎵€鏈夌鍏堣妭鐐癸紝
  /// 骞舵竻绌洪」鐩拰鏂囦欢澶圭殑閫変腑鐘舵€併€?
  void locateInTree(String folderPath) {
    final ancestors = _categoryRoot.ancestorPaths(folderPath);
    _expandedPaths.addAll(ancestors);
    _selectedCategoryPath = folderPath;
    _selectedClass = kAllClass;
    _selectedItem = null;
    _selectedPaths.clear();
    _selectedFolderPaths.clear();
    _selectedFolder = _categoryRoot.findByPath(folderPath);
    _fileBrowserVisible = false;
    notifyListeners();
  }

  /// 鍒囨崲宸︿晶鏂囦欢澶硅妭鐐圭殑灞曞紑/鏀惰捣鐘舵€併€?
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
    _searchScope = await SettingsService.loadSearchScope();
    _classSource = await SettingsService.loadClassSource();
    _groupingEnabled = await SettingsService.loadGroupingEnabled();
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
    _selectedFile = null;
    _selectedPaths
      ..clear()
      ..add(item.path);
    _selectionAnchorPath = item.path;
    _selectedFolderPaths.clear();
    _fileBrowserVisible = true;
    notifyListeners();
  }

  /// 閫変腑涓€涓枃浠跺す鑺傜偣锛堢敤浜庡崟鍑绘枃浠跺す鍗＄墖锛氭樉绀烘枃浠跺す info锛屼笉杩涘簳閮級銆?
  void setSelectedFolder(CategoryNode node) {
    _selectedFolder = node;
    _selectedItem = null;
    _selectedFile = null;
    _selectedPaths.clear();
    _selectedFolderPaths
      ..clear()
      ..add(node.path);
    _folderSelectionAnchorPath = node.path;
    _fileBrowserVisible = false;
    notifyListeners();
  }

  void setSelectedFile(DirectFile file) {
    _selectedFile = file;
    _selectedItem = null;
    _selectedFolder = null;
    _selectedPaths.clear();
    _selectedFolderPaths.clear();
    _fileBrowserVisible = false;
    notifyListeners();
  }

  /// 清除所有卡片选中状态（点击网格空白处调用），对齐 Windows 资源管理器行为。
  ///
  /// 右侧面板回退到显示当前所在文件夹的 info（与点击左侧文件夹树一致）：
  /// [_selectedFolder] 重新指向当前 [_selectedCategoryPath] 对应的节点；
  /// 若当前为"全部"视图（[_selectedCategoryPath] == null）则为 null，显示空状态。
  void clearSelection() {
    _selectedItem = null;
    _selectedFile = null;
    _selectedPaths.clear();
    _selectedFolderPaths.clear();
    _selectionAnchorPath = null;
    _folderSelectionAnchorPath = null;
    _fileBrowserVisible = false;
    _selectedFolder = _selectedCategoryPath == null
        ? null
        : _categoryRoot.findByPath(_selectedCategoryPath!);
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
    final anchorIndex = currentList.indexWhere(
      (e) => e.path == _folderSelectionAnchorPath,
    );
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

  /// 閫氳繃 uuid 閫変腑椤圭洰锛坓oto 鐐瑰嚮锛夈€傛壘涓嶅埌杩斿洖 false锛岃皟鐢ㄦ柟鎻愮ず銆?
  bool selectByUuid(String uuid) {
    final item = _itemByUuid[uuid];
    if (item == null) return false;
    setSelectedItem(item);
    return true;
  }

  /// 閫氳繃鐩稿璺緞閫変腑宓屽 item锛坓oto 鐐瑰嚮 path 鍨嬶級銆?
  /// [currentItemPath] 鏄綋鍓嶉€変腑椤圭洰鐨勭粷瀵硅矾寰勶紝[relativePath] 鏄浉瀵瑰畠鐨勮矾寰勩€?
  /// 鍗虫椂鎵弿鏋勫缓涓存椂 LibraryItem 鏄剧ず銆傛壘涓嶅埌杩斿洖 false銆?
  Future<bool> selectByGotoPath(
    String currentItemPath,
    String relativePath,
  ) async {
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

  String _baseName(String p) => p.replaceAll('\\', '/').split('/').last;

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

    final anchorIndex = currentList.indexWhere(
      (e) => e.path == _selectionAnchorPath,
    );
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

  /// 淇濆瓨鍗曢」缂栬緫缁撴灉锛氱敤鏂扮殑 ItemInfo 鏇挎崲瀵瑰簲椤圭洰鐨?info,骞跺啓鍥?info.json銆?
  /// uuid 涓虹┖鏃惰嚜鍔ㄧ敓鎴愩€?
  Future<bool> saveItemInfo(String itemPath, ItemInfo newInfo) async {
    final index = _allItems.indexWhere((e) => e.path == itemPath);
    if (index == -1) return false;

    // uuid 涓虹┖鏃惰嚜鍔ㄧ敓鎴?
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

    // define 鍙樺寲锛坕tem/dir/hide 涔嬮棿浠绘剰鍒囨崲锛夐渶瑕侀噸鎵互鏇存柊鏍戠粨鏋?
    return defineChanged;
  }

  /// Create a new item: creates folder, writes info.json, saves preview, rescans.
  void startCopy(String message) {
    _copyProgress = 0.0;
    _copyStatus = message;
    notifyListeners();
  }

  void updateCopyProgress(double value, String message) {
    _copyProgress = value;
    _copyStatus = message;
    notifyListeners();
  }

  void showCopyComplete(String message) {
    _copyProgress = 1.0;
    _copyStatus = message;
    notifyListeners();
    Future.delayed(const Duration(seconds: 3), () {
      _copyProgress = -1;
      _copyStatus = '';
      notifyListeners();
    });
  }

  Future<void> _copySingle(String src, String dest) async {
    final entity = FileSystemEntity.typeSync(src);
    if (entity == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(src), Directory(dest));
    } else {
      await File(src).copy(dest);
    }
  }

  Future<void> _copyDirectory(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in src.list()) {
      if (entity is File) {
        final relative = entity.path.substring(src.path.length + 1);
        await entity.copy("${dest.path}${Platform.pathSeparator}$relative");
      } else if (entity is Directory) {
        final relative = entity.path.substring(src.path.length + 1);
        await _copyDirectory(
          entity,
          Directory("${dest.path}${Platform.pathSeparator}$relative"),
        );
      }
    }
  }

  String _uniqueName(String destDir, String name) {
    final dest = "$destDir${Platform.pathSeparator}$name";
    if (!Directory(dest).existsSync() && !File(dest).existsSync()) return dest;
    int counter = 1;
    while (true) {
      final alt = "$destDir${Platform.pathSeparator}${name}_$counter";
      if (!Directory(alt).existsSync() && !File(alt).existsSync()) return alt;
      counter++;
    }
  }

  Future<String?> createItem({
    required String parentPath,
    required String folderName,
    required ItemInfo info,
    Uint8List? croppedImage,
    List<String> importedPaths = const [],
  }) async {
    final safeName = folderName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    String itemPath = '$parentPath${Platform.pathSeparator}$safeName';
    if (Directory(itemPath).existsSync()) {
      int counter = 1;
      do {
        itemPath = '$parentPath${Platform.pathSeparator}${safeName}_$counter';
        counter++;
      } while (Directory(itemPath).existsSync());
    }
    try {
      await Directory(itemPath).create(recursive: true);
      ItemInfo finalInfo = info;
      if (info.uuid == null || info.uuid!.isEmpty) {
        finalInfo = info.copyWith(uuid: const Uuid().v4());
      }
      if (croppedImage != null) {
        final previewFile = File(
          '$itemPath${Platform.pathSeparator}preview.png',
        );
        await previewFile.writeAsBytes(croppedImage);
        finalInfo = finalInfo.copyWith(preview: 'preview.png');
      }
      final jsonFile = File('$itemPath${Platform.pathSeparator}info.json');
      await jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(finalInfo.toJson()),
      );
      if (importedPaths.isNotEmpty) {
        startCopy("Copying ${importedPaths.length} item(s)...");
        for (int i = 0; i < importedPaths.length; i++) {
          final src = importedPaths[i];
          final srcName = src.replaceAll("\\", "/").split("/").last;
          updateCopyProgress(
            i / importedPaths.length,
            "Copying $srcName (${i + 1}/${importedPaths.length})",
          );
          final dest = _uniqueName(itemPath, srcName);
          try {
            await _copySingle(src, dest);
          } catch (e) {
            debugPrint("copy error for $src: $e");
          }
        }
        showCopyComplete("Copy complete");
      }
      await rescan();
      return itemPath;
    } catch (e) {
      debugPrint('createItem error: $e');
      return null;
    }
  }

  /// 淇濆瓨鏂囦欢澶癸紙CategoryNode锛夌殑 info.json銆傝繑鍥?define 鏄惁鍙樺寲锛堥渶閲嶆壂锛夈€?
  Future<bool> saveFolderInfo(String folderPath, ItemInfo newInfo) async {
    // uuid 涓虹┖鏃惰嚜鍔ㄧ敓鎴?
    ItemInfo finalInfo = newInfo;
    if (newInfo.uuid == null || newInfo.uuid!.isEmpty) {
      finalInfo = newInfo.copyWith(uuid: const Uuid().v4());
    }

    final jsonFile = File('$folderPath${Platform.pathSeparator}info.json');
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(finalInfo.toJson()),
    );

    // 鏇存柊鏍戜腑鐨勮妭鐐?info
    final node = _categoryRoot.findByPath(folderPath);
    final defineChanged = node?.info?.define != finalInfo.define;
    if (node != null) {
      _categoryRoot = _updateFolderInfoInTree(
        _categoryRoot,
        folderPath,
        finalInfo,
      );
    }
    if (_selectedFolder?.path == folderPath) {
      _selectedFolder = _categoryRoot.findByPath(folderPath);
    }
    notifyListeners();
    return defineChanged;
  }

  /// 閫掑綊鏇存柊鏍戜腑鏌愯妭鐐?info锛堜笉鍙彉鏍戦渶閲嶅缓鏍癸級銆?
  CategoryNode _updateFolderInfoInTree(
    CategoryNode node,
    String targetPath,
    ItemInfo newInfo,
  ) {
    if (node.path == targetPath) {
      return node.copyWith(info: newInfo);
    }
    final newSubDirs = node.subDirs
        .map((sub) => _updateFolderInfoInTree(sub, targetPath, newInfo))
        .toList();
    return node.copyWith(subDirs: newSubDirs);
  }

  /// 鎵归噺缂栬緫:瀵规墍鏈夐€変腑椤瑰簲鐢ㄥ悓涓€鎵瑰瓧娈靛彉鏇淬€?
  /// 鍒楄〃瀛楁锛坱ags/classes/goto锛夋敮鎸?overwrite/append/remove 妯″紡銆?
  /// 杩斿洖鏄惁鏈?define 鍙樺寲锛堥渶瑕侀噸鎵級銆?
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

      // uuid 涓虹┖鏃惰嚜鍔ㄧ敓鎴?
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

  /// 鎵归噺缂栬緫鏂囦欢澶癸細涓?batchEditItems 瀛楁瀵归綈锛岀敤浜庡閫夋枃浠跺す鍗＄墖鍚庣殑鎵归噺缂栬緫銆?
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

      // uuid 涓虹┖鏃惰嚜鍔ㄧ敓鎴?
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
    List<String> oldList,
    List<String>? newList,
    String mode,
  ) {
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
    List<GotoEntry> oldList,
    List<GotoEntry>? newList,
    String mode,
  ) {
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

  /// 閲嶅懡鍚嶉」鐩枃浠跺す鍐呯殑鏌愪釜鏂囦欢鎴栧瓙鏂囦欢澶?閲嶅懡鍚嶅悗鍒锋柊鏂囦欢闈㈡澘
  Future<String?> renameFile(String oldPath, String newName) async {
    try {
      final sep = oldPath.contains('\\') ? '\\' : '/';
      final dirParts = oldPath.split(sep);
      final parentDir = dirParts.take(dirParts.length - 1).join(sep);
      final newPath = '$parentDir$sep$newName';
      final type = await FileSystemEntity.type(oldPath);
      if (type == FileSystemEntityType.directory) {
        await Directory(oldPath).rename(newPath);
      } else {
        await File(oldPath).rename(newPath);
      }
      // 鏇存柊缂撳瓨涓殑鏂囦欢鏉＄洰锛堢洿鎺ユ枃浠讹級
      if (type != FileSystemEntityType.directory) {
        final node = _categoryRoot.findByPath(parentDir);
        if (node != null) {
          final idx = node.files.indexWhere((f) => f.path == oldPath);
          if (idx != -1) {
            final old = node.files[idx];
            node.files[idx] = DirectFile(
              path: newPath,
              name: newName,
              sizeInBytes: old.sizeInBytes,
              modifiedTime: old.modifiedTime,
            );
          }
        }
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
    _selectedClass = kAllClass;
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

  /// 閲嶆壂褰撳墠璧勬簮搴擄紝淇濈暀褰撳墠閫変腑鐨勫垎绫昏矾寰勫拰鎼滅储锛堜笉璺冲洖寮€澶达級銆?
  /// 鐢ㄤ簬 define 鍙樺寲鍚庡埛鏂版爲缁撴瀯銆?
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
      // 淇濈暀灞曞紑鎬侊紝浠呮竻鐞嗗凡涓嶅瓨鍦ㄧ殑璺緞锛堟枃浠跺す鍙兘琚垹/鏀瑰悕锛夈€?
      _expandedPaths.removeWhere((p) => _categoryRoot.findByPath(p) == null);
      // 鎭㈠鍒嗙被璺緞锛堣嫢鏂版爲閲屼笉瀛樺湪鍒欑疆 null锛?
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
