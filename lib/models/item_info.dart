import 'goto_entry.dart';
import '../services/translations.dart';

/// 对应每个项目文件夹里 info.json 的内容。
/// 字段尽量保持 final(不可变),要"修改"时通过 copyWith 生成新对象。
class ItemInfo {
  final String? uuid; // 唯一标识，编辑保存时自动生成
  final String define; // 'dir' 或 'item'，默认 'item'
  final String title;
  final String description;
  final String? creator; // 可能没有创建者信息,所以允许 null
  final String type;
  final String contentRating;
  final int rating; // 0~10,对应原项目里的半星机制(实际是 0~5 星,每星 2 个单位)
  final List<String> tags;
  final List<String> classes; // 对应 Python 里的 "class" 字段,这里改名避开关键字
  final String? preview; // 自定义预览图相对路径，null 则自动选择
  final List<GotoEntry> goto; // 关联项目链接列表
  final bool star; // 是否标星，卡片右上角显示星星

  const ItemInfo({
    this.uuid,
    this.define = 'item',
    required this.title,
    required this.description,
    this.creator,
    required this.type,
    required this.contentRating,
    required this.rating,
    required this.tags,
    required this.classes,
    this.preview,
    this.goto = const [],
    this.star = false,
  });

  /// 默认值,对应 Python 里 scan_all_items 里那个写死的 info_data 初始字典
  factory ItemInfo.defaults(String folderName) {
    return ItemInfo(
      uuid: null,
      define: 'item',
      title: folderName,
      description: Strings.t('noDescription'),
      creator: null,
      type: 'application',
      contentRating: 'G',
      rating: 5,
      tags: const [],
      classes: const [],
      preview: null,
      goto: const [],
      star: false,
    );
  }

  /// 从 JSON map 解析。传入的 json 通常是 info.json 文件解析后的结果,
  /// 也可能是空 map(文件不存在或解析失败时)。
  /// defaults 用于在某个字段缺失时提供兜底值,
  /// 对应 Python 里先建默认字典再 update 的逻辑。
  factory ItemInfo.fromJson(Map<String, dynamic> json, ItemInfo defaults) {
    final gotoRaw = json['goto'];
    List<GotoEntry> gotoList = const [];
    if (gotoRaw is List) {
      gotoList = gotoRaw
          .whereType<Map>()
          .map((e) => GotoEntry.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return ItemInfo(
      uuid: json['uuid'] as String? ?? defaults.uuid,
      define: json['define'] as String? ?? defaults.define,
      title: json['title'] as String? ?? defaults.title,
      description: json['description'] as String? ?? defaults.description,
      creator: json['creator'] as String? ?? defaults.creator,
      type: json['type'] as String? ?? defaults.type,
      contentRating: json['contentrating'] as String? ?? defaults.contentRating,
      rating: json['rating'] as int? ?? defaults.rating,
      tags: _parseStringList(json['tags']) ?? defaults.tags,
      classes: _parseStringList(json['class']) ?? defaults.classes,
      preview: json['preview'] as String? ?? defaults.preview,
      goto: gotoList,
      star: json['star'] as bool? ?? defaults.star,
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
      'uuid': uuid,
      'define': define,
      'title': title,
      'description': description,
      'creator': creator,
      'type': type,
      'contentrating': contentRating,
      'rating': rating,
      'class': classes,
      'tags': tags,
      'preview': preview,
      'goto': goto.map((e) => e.toJson()).toList(),
      'star': star,
    };
  }

  /// 因为字段是 final 不可变,"修改"的方式是基于旧对象生成一个新对象,
  /// 没传的字段保持原值。这是 Dart 里处理不可变数据对象的标准模式。
  ItemInfo copyWith({
    String? uuid,
    String? define,
    String? title,
    String? description,
    String? creator,
    String? type,
    String? contentRating,
    int? rating,
    List<String>? tags,
    List<String>? classes,
    String? preview,
    List<GotoEntry>? goto,
    bool? star,
  }) {
    return ItemInfo(
      uuid: uuid ?? this.uuid,
      define: define ?? this.define,
      title: title ?? this.title,
      description: description ?? this.description,
      creator: creator ?? this.creator,
      type: type ?? this.type,
      contentRating: contentRating ?? this.contentRating,
      rating: rating ?? this.rating,
      tags: tags ?? this.tags,
      classes: classes ?? this.classes,
      preview: preview ?? this.preview,
      goto: goto ?? this.goto,
      star: star ?? this.star,
    );
  }
}