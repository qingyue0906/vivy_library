/// 一个资源库快照的元数据记录。
///
/// [id] 即快照目录名（时间戳+随机后缀，创建后不可变），
/// [name]/[note] 为可编辑的展示名称与备注（存于 meta.json），
/// [sourcePath] 是创建时的资源库绝对路径（用于返回与归属展示），
/// [createdAt] 创建时间，[sizeBytes] 快照目录总大小（含预览图）。
class SnapshotMeta {
  final String id;
  final String name;
  final String note;
  final String sourcePath;
  final DateTime createdAt;
  final int sizeBytes;

  const SnapshotMeta({
    required this.id,
    required this.name,
    required this.note,
    required this.sourcePath,
    required this.createdAt,
    this.sizeBytes = 0,
  });

  factory SnapshotMeta.fromJson(Map<String, dynamic> json) {
    return SnapshotMeta(
      id: json['id'] as String,
      name: json['name'] as String,
      note: json['note'] as String? ?? '',
      sourcePath: json['sourcePath'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sizeBytes: json['sizeBytes'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'sourcePath': sourcePath,
        'createdAt': createdAt.toIso8601String(),
        'sizeBytes': sizeBytes,
      };

  SnapshotMeta copyWith({String? name, String? note, int? sizeBytes}) {
    return SnapshotMeta(
      id: id,
      name: name ?? this.name,
      note: note ?? this.note,
      sourcePath: sourcePath,
      createdAt: createdAt,
      sizeBytes: sizeBytes ?? this.sizeBytes,
    );
  }
}
