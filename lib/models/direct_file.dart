/// 文件夹下直接存放的普通文件（非项目文件夹）。
class DirectFile {
  final String path;
  final String name;
  final int sizeInBytes;
  final DateTime modifiedTime;

  const DirectFile({
    required this.path,
    required this.name,
    required this.sizeInBytes,
    required this.modifiedTime,
  });

  String get extension => name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
}
