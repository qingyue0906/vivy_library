import 'package:flutter/foundation.dart';

/// 单条音频的元数据（标题/艺人/专辑/内嵌封面/内嵌歌词/时长），由 [AudioTagService] 填充。
class AudioMeta {
  final String? title;
  final String? artist;
  final String? album;
  final Uint8List? coverBytes; // 内嵌封面「缩略图」(≤128px，由 AudioTagService 解码缩放)，非原图，供列表/卡片
  final Uint8List? coverFullBytes; // 内嵌封面「原图」(舞台大图高清显示，仅当前播放曲按需加载，不缩放)
  final String? lyrics; // 内嵌歌词原始文本（可能含 LRC 时间戳）
  final Duration? duration; // 以播放器权威时长为准，标签仅作兜底

  const AudioMeta({
    this.title,
    this.artist,
    this.album,
    this.coverBytes,
    this.coverFullBytes,
    this.lyrics,
    this.duration,
  });

  AudioMeta copyWith({
    String? title,
    String? artist,
    String? album,
    Uint8List? coverBytes,
    Uint8List? coverFullBytes,
    String? lyrics,
    Duration? duration,
  }) {
    return AudioMeta(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      coverBytes: coverBytes ?? this.coverBytes,
      coverFullBytes: coverFullBytes ?? this.coverFullBytes,
      lyrics: lyrics ?? this.lyrics,
      duration: duration ?? this.duration,
    );
  }

  String get durationText => formatDuration(duration);

  /// 时长格式化：与视频播放器一致（分:秒，超过 1 小时为 时:分:秒）。
  static String formatDuration(Duration? d) {
    if (d == null || d == Duration.zero) return '--:--';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

/// 播放列表中的单个音频条目。
class AudioEntry {
  final String path;
  final String name; // 含扩展名的文件名
  final String dirPath; // 所在文件夹绝对路径
  final int sizeInBytes;
  final DateTime modifiedTime; // 文件最后修改时间（用于日期排序）
  final bool isAudio; // 是否受支持的音频（决定是否可点击播放）
  AudioMeta? meta; // 渐进填充，初始为空

  /// 当 [meta] 变化时通知监听者（播放列表中的叶子小部件借此自更新，
  /// 无需父级整树重建），是“探测完成只刷新单个条目”的关键。
  final ValueNotifier<AudioMeta?> metaNotifier;

  AudioEntry({
    required this.path,
    required this.name,
    required this.dirPath,
    required this.sizeInBytes,
    required this.modifiedTime,
    this.isAudio = true,
    this.meta,
  }) : metaNotifier = ValueNotifier(meta);

  /// 写入元数据并通知监听者。替代直接 `meta = ...`，让挂载中的叶子小部件自行刷新。
  void setMeta(AudioMeta? m) {
    meta = m;
    metaNotifier.value = m;
  }

  /// 去除扩展名后的文件名（无标签时的兜底显示名）。
  String get baseName {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// 展示标题：优先标签标题，否则用文件名（去扩展名）。
  String get displayTitle => (meta?.title?.isNotEmpty ?? false) ? meta!.title! : baseName;

  /// 展示艺人：优先标签艺人，否则空串（占位交给 UI）。
  String get displayArtist =>
      (meta?.artist?.isNotEmpty ?? false) ? meta!.artist! : '';

  String get sizeText {
    final b = sizeInBytes;
    if (b < 1024) return '$b B';
    final kb = b / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
}

/// 文件夹树节点：children 为子文件夹，files 为该文件夹下的音频文件。
class AudioFolderNode {
  final String name;
  final String path; // 该文件夹的绝对路径（用于展开状态与归属判断）
  final List<AudioFolderNode> children = [];
  final List<AudioEntry> files = [];

  AudioFolderNode(this.name, this.path);
}

/// 一次构建出的完整播放列表：扁平 entries（仅音频，用于顺序播放）+ tree（用于文件夹树展示）。
class AudioPlaylist {
  final List<AudioEntry> entries;
  final List<AudioFolderNode> tree;

  AudioPlaylist({required this.entries, required this.tree});

  /// 深拷贝播放列表，但**保留每个条目的 meta（封面/时长/标签）**——这是反复打开同一
  /// 项目时「不重复解析标签、不重探时长」的关键：重建的是轻量的条目/树对象，
  /// 而 meta 与跨页面缓存共享同一引用，封面字节不再被反复读盘、不再泄漏累积。
  /// 每次打开都拿到独立副本，页面级的排序/展开/当前索引等状态互不干扰。
  AudioPlaylist clone() {
    // 关键修正：扁平 entries 与树 files 必须共享「同一份」AudioEntry 实例
    // （与原 build() 行为一致）。否则 setMeta 只更新扁平表、树里的文件叶永远拿不到
    // meta → 播放列表无缩略图、无标题/艺人；且每个文件只有 1 个对象持有 meta，
    // 避免重复拷贝封面字节。
    final byPath = <String, AudioEntry>{};
    AudioEntry cloneEntry(AudioEntry e) => byPath.putIfAbsent(
          e.path,
          () => AudioEntry(
            path: e.path,
            name: e.name,
            dirPath: e.dirPath,
            sizeInBytes: e.sizeInBytes,
            modifiedTime: e.modifiedTime,
            isAudio: e.isAudio,
            meta: e.meta,
          ),
        );
    AudioFolderNode cloneNode(AudioFolderNode n) {
      final c = AudioFolderNode(n.name, n.path);
      c.files.addAll(n.files.map(cloneEntry));
      c.children.addAll(n.children.map(cloneNode));
      return c;
    }

    return AudioPlaylist(
      entries: entries.map(cloneEntry).toList(),
      tree: tree.map(cloneNode).toList(),
    );
  }
}

/// 一行歌词（带时间戳）。无时间戳时 [time] 为 null。
class LyricLine {
  final Duration? time;
  final String text;

  LyricLine(this.time, this.text);
}

/// LRC 歌词解析：提取形如 [mm:ss.xx] 的时间戳并排序。
/// 若整篇都没有时间戳，返回空列表（UI 退化为整块纯文本展示）。
class LyricParser {
  static final RegExp _ts = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');

  static List<LyricLine> parse(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final lines = raw.split(RegExp(r'\r\n|\n|\r'));
    final out = <LyricLine>[];
    var hasTs = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final matches = _ts.allMatches(trimmed);
      if (matches.isEmpty) {
        // 无时间戳行：记为一句（time 为 null），仅当已出现过带时间戳行时保留。
        if (hasTs) out.add(LyricLine(null, trimmed));
        continue;
      }
      hasTs = true;
      // 一行可能挂多个时间戳（如重复段），每个时间戳生成一句。
      final text = trimmed.replaceAll(_ts, '').trim();
      for (final m in matches) {
        final min = int.tryParse(m.group(1)!) ?? 0;
        final sec = double.tryParse(m.group(2)!) ?? 0;
        final t = Duration(
          minutes: min,
          milliseconds: ((sec - sec.truncate()) * 1000).round() + sec.truncate() * 1000,
        );
        out.add(LyricLine(t, text));
      }
    }
    if (!hasTs) return const [];
    out.sort((a, b) {
      if (a.time == null) return 1;
      if (b.time == null) return -1;
      return a.time!.compareTo(b.time!);
    });
    // 合并相同时间戳的相邻行（常见「原文 + 翻译」双语歌词）：
    // 让它们作为整体一起高亮、一起滚动，而非只高亮最后一行（翻译）。
    final merged = <LyricLine>[];
    for (final line in out) {
      if (merged.isNotEmpty) {
        final prev = merged.last;
        if (prev.time != null && line.time != null && prev.time == line.time) {
          merged[merged.length - 1] =
              LyricLine(prev.time, '${prev.text}\n${line.text}');
          continue;
        }
      }
      merged.add(line);
    }
    return merged;
  }
}
