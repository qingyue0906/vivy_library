/// 单条视频/文件的元数据（编码/分辨率/帧率/时长），由 [VideoMetadataService] 填充。
class VideoMeta {
  final String? codec;
  final int? width;
  final int? height;
  final double? fps;
  final Duration? duration;

  const VideoMeta({this.codec, this.width, this.height, this.fps, this.duration});

  VideoMeta copyWith({
    String? codec,
    int? width,
    int? height,
    double? fps,
    Duration? duration,
  }) {
    return VideoMeta(
      codec: codec ?? this.codec,
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      duration: duration ?? this.duration,
    );
  }

  /// 常见编码的友好标签（如 h264→AVC、hevc→HEVC、av1→AV1）。
  static const Map<String, String> _codecLabels = {
    'av1': 'AV1',
    'hevc': 'HEVC',
    'h265': 'HEVC',
    'h264': 'AVC',
    'avc': 'AVC',
    'vp9': 'VP9',
    'vp8': 'VP8',
    'mpeg4': 'MPEG4',
    'mpeg2video': 'MPEG2',
    'mpeg1video': 'MPEG1',
    'theora': 'Theora',
    'vc1': 'VC1',
  };

  String get codecText {
    if (codec == null) return '--';
    final lower = codec!.toLowerCase();
    return _codecLabels[lower] ?? codec!.toUpperCase();
  }

  String get resolutionText {
    if (width != null && height != null) return '${width}x$height';
    return '--';
  }

  String get fpsText {
    if (fps == null) return '--';
    // 取整显示更干净；非整数保留 2 位
    if ((fps! - fps!.round()).abs() < 0.01) return '${fps!.round()}';
    return fps!.toStringAsFixed(2);
  }

  static String formatDuration(Duration? d) {
    if (d == null || d == Duration.zero) return '--:--';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// 进度条时钟格式：分:秒.毫秒(3位)，如 0:09.150；超过 1 小时为 时:分:秒.毫秒。
  static String formatClock(Duration? d) {
    if (d == null || d == Duration.zero) return '--:--';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final ms = d.inMilliseconds.remainder(1000);
    final ss = s.toString().padLeft(2, '0');
    final mmm = ms.toString().padLeft(3, '0');
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:$ss.$mmm'
        : '$m:$ss.$mmm';
  }

  String get durationText => formatDuration(duration);
}

/// 播放列表中的单个文件条目。既可能是视频（可播放），也可能是普通文件（如 info.json）。
class VideoEntry {
  final String path;
  final String name;
  final String dirPath; // 所在文件夹绝对路径
  final int sizeInBytes;
  final bool isVideo; // 是否受支持的视频（决定是否可点击播放）
  VideoMeta? meta; // 渐进填充，初始为空

  VideoEntry({
    required this.path,
    required this.name,
    required this.dirPath,
    required this.sizeInBytes,
    this.isVideo = true,
    this.meta,
  });

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

/// 文件夹树节点：children 为子文件夹，files 为该文件夹下的文件（视频或非视频）。
class VideoFolderNode {
  final String name;
  final String path; // 该文件夹的绝对路径（用于展开状态与归属判断）
  final List<VideoFolderNode> children = [];
  final List<VideoEntry> files = [];

  VideoFolderNode(this.name, this.path);
}

/// 一次构建出的完整播放列表：扁平 entries（仅视频，用于顺序播放）+ tree（用于文件夹树展示）。
class VideoPlaylist {
  final List<VideoEntry> entries;
  final List<VideoFolderNode> tree;

  VideoPlaylist({required this.entries, required this.tree});
}
