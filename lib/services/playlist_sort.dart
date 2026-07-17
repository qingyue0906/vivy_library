import '../providers/library_state.dart';

/// 比较两条播放列表条目（视频或音频共用），按所选字段与升降序返回排序值。
///
/// 文件夹节点因无 size/date，调用方应始终按名称排序，本函数仅用于「文件」条目。
int comparePlaylistEntries({
  required String nameA,
  required int sizeA,
  required DateTime dateA,
  required String nameB,
  required int sizeB,
  required DateTime dateB,
  required SortField field,
  required SortOrder order,
}) {
  int cmp;
  switch (field) {
    case SortField.name:
      cmp = nameA.toLowerCase().compareTo(nameB.toLowerCase());
    case SortField.size:
      cmp = sizeA.compareTo(sizeB);
    case SortField.date:
      cmp = dateA.compareTo(dateB);
  }
  return order == SortOrder.ascending ? cmp : -cmp;
}
