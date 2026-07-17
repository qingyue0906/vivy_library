import 'dart:typed_data';

/// 单条音频的元数据（标题/艺人/专辑/内嵌封面/内嵌歌词/时长），由 [AudioTagService] 填充。
class AudioMeta {
  final String? title;
  final String? artist;
  final String? album;
  final Uint8List? coverBytes; // 内嵌封面图（APIC / METADATA_BLOCK_PICTURE / covr）
  final String? lyrics; // 内嵌歌词原始文本（可能含 LRC 时间戳）
  final Duration? duration; // 以播放器权威时长为准，标签仅作兜底

  const AudioMeta({
    this.title,
    this.artist,
    this.album,
    this.coverBytes,
    this.lyrics,
    this.duration,
  });

  AudioMeta copyWith({
    String? title,
    String? artist,
    String? album,
    Uint8List? coverBytes,
    String? lyrics,
    Duration? duration,
  }) {
    return AudioMeta(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      coverBytes: coverBytes ?? this.coverBytes,
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

  AudioEntry({
    required this.path,
    required this.name,
    required this.dirPath,
    required this.sizeInBytes,
    required this.modifiedTime,
    this.isAudio = true,
    this.meta,
  });

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
