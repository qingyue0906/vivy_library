// 项目类型 → 图标/颜色的统一映射（与详情面板 _typeIcon/_typeColor、卡片
// 徽章一致的 12 种预设类型），供筛选面板等 UI 复用。
// 预设类型列表见 ItemFilter.presetTypes（单一来源）。

import 'package:flutter/material.dart';

/// 类型图标（预设类型 → Material 图标）。
IconData typeIcon(String type) {
  switch (type) {
    case 'video':
      return Icons.movie;
    case 'anime':
      return Icons.live_tv;
    case 'novel':
      return Icons.menu_book;
    case 'book':
      return Icons.book;
    case 'application':
      return Icons.apps;
    case 'zip':
      return Icons.archive;
    case 'picture':
      return Icons.photo;
    case 'comic':
      return Icons.auto_stories;
    case 'voice':
      return Icons.mic;
    case 'music':
      return Icons.music_note;
    case 'edgehtml':
      return Icons.html;
    case 'markdown':
      return Icons.article;
    default:
      return Icons.label;
  }
}

/// 类型颜色（预设类型 → 强调色）。
Color typeColor(String type) {
  switch (type) {
    case 'video':
      return Colors.redAccent;
    case 'anime':
      return Colors.pinkAccent;
    case 'novel':
      return Colors.tealAccent;
    case 'book':
      return Colors.brown.shade300;
    case 'application':
      return Colors.lightBlueAccent;
    case 'zip':
      return Colors.amber;
    case 'picture':
      return Colors.greenAccent;
    case 'comic':
      return Colors.purpleAccent;
    case 'voice':
      return Colors.orangeAccent;
    case 'music':
      return Colors.cyanAccent;
    case 'edgehtml':
      return Colors.orange;
    case 'markdown':
      return Colors.lightGreen;
    default:
      return Colors.grey;
  }
}
