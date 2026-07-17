import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/library_item.dart';
import '../models/audio_track.dart';
import 'audio_tag_service.dart';

/// 递归扫描项目文件夹，构建音频播放列表（扁平 entries + 文件夹树）。
/// 标签（标题/艺人/封面/歌词）由播放器页面按需渐进加载，此处仅扫描文件。
class AudioPlaylistService {
  /// 判断文件路径是否为受支持的音频扩展名。
  static bool isAudioFile(String path) => AudioTagService.isAudioFile(path);

  /// 构建项目内全部音频的播放列表。
  static Future<AudioPlaylist> build(LibraryItem item) async =>
      buildFromPath(item.path);

  /// 直接扫描一个文件夹路径构建播放列表（用于"打开文件夹"）。
  static Future<AudioPlaylist> buildFromPath(String root) async {
    final entries = <AudioEntry>[];
    final rootNode = AudioFolderNode(p.basename(root), root);
    if (Directory(root).existsSync()) {
      await _scan(Directory(root), entries, rootNode);
    }
    _sortNode(rootNode);
    entries.sort((a, b) => a.path.compareTo(b.path));
    return AudioPlaylist(entries: entries, tree: [rootNode]);
  }

  static Future<void> _scan(
    Directory dir,
    List<AudioEntry> entries,
    AudioFolderNode node,
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
      } else if (e is File && isAudioFile(e.path)) {
        int size;
        DateTime modified;
        try {
          size = e.lengthSync();
        } catch (_) {
          size = 0;
        }
        try {
          modified = e.lastModifiedSync();
        } catch (_) {
          modified = DateTime.fromMillisecondsSinceEpoch(0);
        }
        final entry = AudioEntry(
          path: e.path,
          name: p.basename(e.path),
          dirPath: dir.path,
          sizeInBytes: size,
          modifiedTime: modified,
          isAudio: true,
        );
        node.files.add(entry);
        entries.add(entry);
      }
    }
    for (final d in subDirs) {
      final child = AudioFolderNode(p.basename(d.path), d.path);
      node.children.add(child);
      await _scan(d, entries, child);
    }
    // 清理扫描后仍无内容的空文件夹节点
    node.children.removeWhere((c) => c.children.isEmpty && c.files.isEmpty);
  }

  static void _sortNode(AudioFolderNode node) {
    node.files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    node.children
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final c in node.children) {
      _sortNode(c);
    }
  }
}
