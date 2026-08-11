// 播放列表「单文件文件夹折叠」工具。
//
// 当树中某个文件夹只含一个（受支持的）子项、且整条单子项链最终落到
// 一个文件上时，把整条链折叠为一条「文件」条目，显示名拼接为
// 「文件夹1/文件夹2/文件.mp4」（类似 VS Code 的资源管理器折叠行为）。
// 折叠只影响树的显示层，不改变文件条目本身与扁平播放顺序。
//
// 4 种播放列表节点（VideoFolderNode / AudioFolderNode / ComicFolderNode /
// EbookFolderNode）结构完全对称，通过回调适配。

/// 沿单子文件夹链向下找到折叠链末端的唯一文件；链在某处分叉（或末端
/// 不是单文件节点）时返回 null。
///
/// 返回值非 null ⇔ 该节点可以折叠（与 [collapsedPath] 判定完全一致），
/// 且返回值就是折叠条目应指向的那个文件。
F? collapseLeafFile<T, F>(
  T node, {
  required List<T> Function(T node) childrenOf,
  required List<F> Function(T node) filesOf,
}) {
  final kids = childrenOf(node);
  final files = filesOf(node);
  if (kids.isEmpty && files.length == 1) return files.first;
  if (kids.length == 1 && files.isEmpty) {
    return collapseLeafFile(
      kids.first,
      childrenOf: childrenOf,
      filesOf: filesOf,
    );
  }
  return null;
}

/// 判断 [node] 是否为一条折叠链的顶端，并返回折叠后的完整显示名；
/// 不可折叠时返回 null，应正常渲染为文件夹头。
///
/// 规则（从文件向上，只要父节点只有这一个子项就继续拼名，遇分支停止）：
/// - 单文件节点（无子文件夹、恰 1 个文件）→ 折叠为「节点名/文件名」；
/// - 单子文件夹节点（无文件、恰 1 个子文件夹）→ 取决于该子文件夹能否
///   折叠，能则继续拼接；不能则整链不折叠（末端不是单文件）。
String? collapsedPath<T, F>(
  T node, {
  required List<T> Function(T node) childrenOf,
  required List<F> Function(T node) filesOf,
  required String Function(T node) nameOf,
  required String Function(F file) fileNameOf,
}) {
  final leaf = collapseLeafFile(node, childrenOf: childrenOf, filesOf: filesOf);
  if (leaf == null) return null;
  final segs = <String>[nameOf(node)];
  var cur = node;
  while (true) {
    final kids = childrenOf(cur);
    final files = filesOf(cur);
    if (kids.isEmpty) break;
    if (kids.length == 1 && files.isEmpty) {
      cur = kids.first;
      segs.add(nameOf(cur));
    } else {
      break;
    }
  }
  segs.add(fileNameOf(leaf));
  return segs.join('/');
}

/// 对过长的折叠显示名做「省略中间」处理：保留首段（顶层文件夹名）与
/// 末段（文件名），中间以省略号替代，使列表行不至于被一个超长名占满。
/// 段长不足时不省略，原样返回。完整名应另以 tooltip 展示。
String ellipsizePathMiddle(String name, {int maxLen = 60}) {
  if (name.length <= maxLen) return name;
  const middle = '…';
  final segs = name.split('/');
  if (segs.length < 2) {
    // 无分隔符的单段名：首尾各留一半。
    final half = (maxLen - middle.length) ~/ 2;
    return '${name.substring(0, half)}$middle${name.substring(name.length - half)}';
  }
  final head = segs.first;
  final tail = segs.last;
  // 首末段放得下时用「首/…/末」形式
  if (head.length + tail.length + middle.length + 1 <= maxLen) {
    return '$head/$middle/$tail';
  }
  // 首末段本身超长（如单段名极长）：各占一半并截断，仍保留「/…/」分隔
  final half = (maxLen - middle.length - 2) ~/ 2;
  final h = head.length > half ? head.substring(0, half) : head;
  final t = tail.length > half ? tail.substring(tail.length - half) : tail;
  return '$h/$middle/$t';
}
