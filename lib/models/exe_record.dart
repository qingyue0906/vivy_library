/// 用户选过的可执行程序记录,用于"打开方式"功能里记住历史选择。
class ExeRecord {
  final String path;        // 程序的完整路径
  final String displayName; // 显示给用户看的名字,默认取文件名(不含扩展名)

  const ExeRecord({required this.path, required this.displayName});

  factory ExeRecord.fromJson(Map<String, dynamic> json) {
    return ExeRecord(
      path: json['path'] as String,
      displayName: json['displayName'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'path': path, 'displayName': displayName};
  }
}