import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/library_item.dart';
import '../models/video_entry.dart';

/// 递归扫描项目文件夹，构建视频播放列表（扁平 entries + 文件夹树）。
class VideoPlaylistService {
  static const _videoExts = {
    'mp4',
    'mkv',
    'avi',
    'mov',
    'wmv',
    'flv',
    'webm',
    'm4v',
    'mpg',
    'mpeg',
    'ts',
    'm2ts',
    'ogv',
    '3gp',
    'f4v',
    'vob',
  };

  /// 判断文件路径是否为受支持的视频扩展名。
  static bool isVideoFile(String path) {
    final ext = p.extension(path).toLowerCase().replaceAll('.', '');
    return _videoExts.contains(ext);
  }

  /// 构建项目内全部视频的播放列表。
  static Future<VideoPlaylist> build(LibraryItem item) async {
    final root = item.path;
    final entries = <VideoEntry>[];
    final rootNode = VideoFolderNode(p.basename(root), root);
    if (Directory(root).existsSync()) {
      await _scan(Directory(root), entries, rootNode);
    }
    _sortNode(rootNode);
    entries.sort((a, b) => a.path.compareTo(b.path));
    return VideoPlaylist(entries: entries, tree: [rootNode]);
  }

  static Future<void> _scan(
    Directory dir,
    List<VideoEntry> entries,
    VideoFolderNode node,
  ) async {
    List<FileSystemEntity> list;
    try {
      list = dir.listSync();
    } catch (_) {
      return;
    }
    final subDirs = <Directory>[];
    for (final e in list) {
      if (e is Directory) {
        subDirs.add(e);
      } else if (e is File && isVideoFile(e.path)) {
        int size;
        try {
          size = e.lengthSync();
        } catch (_) {
          size = 0;
        }
        final entry = VideoEntry(
          path: e.path,
          name: p.basename(e.path),
          dirPath: dir.path,
          sizeInBytes: size,
          isVideo: true,
        );
        node.files.add(entry);
        entries.add(entry);
      }
    }
    for (final d in subDirs) {
      final child = VideoFolderNode(p.basename(d.path), d.path);
      node.children.add(child);
      await _scan(d, entries, child);
    }
    // 清理扫描后仍无内容的空文件夹节点
    node.children.removeWhere((c) => c.children.isEmpty && c.files.isEmpty);
  }

  static void _sortNode(VideoFolderNode node) {
    node.files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    node.children.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final c in node.children) {
      _sortNode(c);
    }
  }

  /// 直接扫描一个文件夹路径构建播放列表（用于"打开文件夹"加载额外视频）。
  static Future<VideoPlaylist> buildFromPath(String path) async {
    final entries = <VideoEntry>[];
    final rootNode = VideoFolderNode(p.basename(path), path);
    if (Directory(path).existsSync()) {
      await _scan(Directory(path), entries, rootNode);
    }
    _sortNode(rootNode);
    entries.sort((a, b) => a.path.compareTo(b.path));
    return VideoPlaylist(entries: entries, tree: [rootNode]);
  }
}
