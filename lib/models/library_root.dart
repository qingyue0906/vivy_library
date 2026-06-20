/// 一个资源库的记录:显示名称 + 根目录路径。
class LibraryRoot {
  final String name;
  final String path;

  const LibraryRoot({required this.name, required this.path});

  factory LibraryRoot.fromJson(Map<String, dynamic> json) {
    return LibraryRoot(
      name: json['name'] as String,
      path: json['path'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'path': path};
}