/// 对应每个项目文件夹里 info.json 的内容。
/// 字段尽量保持 final(不可变),要"修改"时通过 copyWith 生成新对象。
class ItemInfo {
  final String title;
  final String description;
  final String? creator; // 可能没有创建者信息,所以允许 null
  final String type;
  final String contentRating;
  final int rating; // 0~10,对应原项目里的半星机制(实际是 0~5 星,每星 2 个单位)
  final List<String> tags;
  final List<String> classes; // 对应 Python 里的 "class" 字段,这里改名避开关键字

  const ItemInfo({
    required this.title,
    required this.description,
    this.creator,
    required this.type,
    required this.contentRating,
    required this.rating,
    required this.tags,
    required this.classes,
  });

  /// 默认值,对应 Python 里 scan_all_items 里那个写死的 info_data 初始字典
  factory ItemInfo.defaults(String folderName) {
    return ItemInfo(
      title: folderName,
      description: '无描述',
      creator: null,
      type: 'application',
      contentRating: 'G',
      rating: 10,
      tags: const [],
      classes: const [],
    );
  }

  /// 从 JSON map 解析。传入的 json 通常是 info.json 文件解析后的结果,
  /// 也可能是空 map(文件不存在或解析失败时)。
  /// defaults 用于在某个字段缺失时提供兜底值,
  /// 对应 Python 里先建默认字典再 update 的逻辑。
  factory ItemInfo.fromJson(Map<String, dynamic> json, ItemInfo defaults) {
    return ItemInfo(
      title: json['title'] as String? ?? defaults.title,
      description: json['description'] as String? ?? defaults.description,
      creator: json['creator'] as String? ?? defaults.creator,
      type: json['type'] as String? ?? defaults.type,
      contentRating: json['contentrating'] as String? ?? defaults.contentRating,
      rating: json['rating'] as int? ?? defaults.rating,
      tags: _parseStringList(json['tags']) ?? defaults.tags,
      classes: _parseStringList(json['class']) ?? defaults.classes,
    );
  }

  /// 把 dynamic 类型的 JSON 列表安全转换成 List<String>。
  /// 抽成静态方法是因为 tags 和 classes 两个字段做的事完全一样,避免重复代码。
  static List<String>? _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'creator': creator,
      'type': type,
      'contentrating': contentRating,
      'rating': rating,
      'class': classes,
      'tags': tags,
    };
  }

  /// 因为字段是 final 不可变,"修改"的方式是基于旧对象生成一个新对象,
  /// 没传的字段保持原值。这是 Dart 里处理不可变数据对象的标准模式。
  ItemInfo copyWith({
    String? title,
    String? description,
    String? creator,
    String? type,
    String? contentRating,
    int? rating,
    List<String>? tags,
    List<String>? classes,
  }) {
    return ItemInfo(
      title: title ?? this.title,
      description: description ?? this.description,
      creator: creator ?? this.creator,
      type: type ?? this.type,
      contentRating: contentRating ?? this.contentRating,
      rating: rating ?? this.rating,
      tags: tags ?? this.tags,
      classes: classes ?? this.classes,
    );
  }
}