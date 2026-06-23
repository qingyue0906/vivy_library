import 'item_info.dart';

/// 对应 Python 里 items_data 列表中的每一条记录:
/// 一个项目文件夹的全部信息,包括它所在的分类、路径、info.json 内容、
/// 预览图路径、文件夹总大小、最近修改时间。
class LibraryItem {
  final String category; // 直接父文件夹名（用于显示）
  final String categoryPath; // 直接父文件夹的绝对路径（用于精确筛选）
  final String folderName; // 项目自己的文件夹名
  final String path; // 项目文件夹的完整路径
  final ItemInfo info; // info.json 解析后的内容
  final String? previewPath; // 预览图完整路径,可能没有图所以是 String?
  final int sizeInBytes; // 文件夹总大小
  final DateTime modifiedTime; // 最近修改时间(排除 info.json 和预览图后的业务文件时间)

  const LibraryItem({
    required this.category,
    required this.categoryPath,
    required this.folderName,
    required this.path,
    required this.info,
    this.previewPath,
    required this.sizeInBytes,
    required this.modifiedTime,
  });
}