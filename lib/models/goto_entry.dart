/// info.json 中 goto 列表的一条记录。
/// goto 用于在右侧面板底部展示"关联项目"链接，点击后切换到 uuid 对应的项目。
class GotoEntry {
  final String name;
  final String uuid;

  const GotoEntry({required this.name, required this.uuid});

  factory GotoEntry.fromJson(Map<String, dynamic> json) {
    return GotoEntry(
      name: json['name'] as String? ?? '',
      uuid: json['uuid'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'uuid': uuid};

  GotoEntry copyWith({String? name, String? uuid}) {
    return GotoEntry(name: name ?? this.name, uuid: uuid ?? this.uuid);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GotoEntry && name == other.name && uuid == other.uuid;

  @override
  int get hashCode => Object.hash(name, uuid);
}
