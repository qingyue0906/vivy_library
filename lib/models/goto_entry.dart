/// info.json 中 goto 列表的一条记录。
/// goto 用于在右侧面板底部展示"关联项目"链接，点击后切换到目标。
///
/// 两种目标定位方式：
/// - uuid：指向当前资源库内的某个项目（uuid 有值，path 为 null）。
/// - path：指向当前项目内的嵌套子文件夹（相对路径，uuid 为 null/空）。
///   用于访问 item 内嵌套的"隐藏项目"，不进主扫描列表。
class GotoEntry {
  final String name;
  final String uuid; // 可空（path 型条目）
  final String? path; // 相对当前 item 的路径，可空（uuid 型条目）

  const GotoEntry({required this.name, this.uuid = '', this.path});

  factory GotoEntry.fromJson(Map<String, dynamic> json) {
    return GotoEntry(
      name: json['name'] as String? ?? '',
      uuid: json['uuid'] as String? ?? '',
      path: json['path'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'name': name};
    if (uuid.isNotEmpty) m['uuid'] = uuid;
    if (path != null && path!.isNotEmpty) m['path'] = path;
    return m;
  }

  GotoEntry copyWith({String? name, String? uuid, String? path}) {
    return GotoEntry(
      name: name ?? this.name,
      uuid: uuid ?? this.uuid,
      path: path ?? this.path,
    );
  }

  /// 去重键：uuid 非空用 uuid，否则用 path，再否则用 name。
  String get dedupKey => uuid.isNotEmpty ? uuid : (path ?? name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GotoEntry && name == other.name && uuid == other.uuid && path == other.path;

  @override
  int get hashCode => Object.hash(name, uuid, path);
}
