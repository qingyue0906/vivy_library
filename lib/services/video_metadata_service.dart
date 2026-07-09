import 'dart:convert';
import 'dart:io';
import '../models/video_entry.dart';

/// 视频元数据探测：优先使用系统 ffprobe（最快最全），
/// 若不可用则返回 null，由播放器在播放时从 media_kit 的 player.state 提取并补全。
class VideoMetadataService {
  static bool? _hasFfprobe;

  static Future<bool> get hasFfprobe async {
    if (_hasFfprobe != null) return _hasFfprobe!;
    try {
      final r = await Process.run('ffprobe', ['-version']);
      _hasFfprobe = r.exitCode == 0;
    } catch (_) {
      _hasFfprobe = false;
    }
    return _hasFfprobe!;
  }

  /// 探测单个视频的元数据；无 ffprobe 时返回 null。
  static Future<VideoMeta?> probe(String path) async {
    if (await hasFfprobe) {
      return _probeFfprobe(path);
    }
    return null;
  }

  static Future<VideoMeta?> _probeFfprobe(String path) async {
    try {
      final r = await Process.run('ffprobe', [
        '-v',
        'error',
        '-show_entries',
        'stream=codec_name,width,height,avg_frame_rate,r_frame_rate,duration',
        '-show_entries',
        'format=duration',
        '-of',
        'json',
        path,
      ]);
      if (r.exitCode != 0) return null;
      final data = jsonDecode(r.stdout) as Map<String, dynamic>;
      final streams = data['streams'] as List?;
      final videoStream = streams?.firstWhere(
        (s) => s['codec_type'] == 'video',
        orElse: () => null,
      ) as Map<String, dynamic>?;

      final codec = videoStream?['codec_name'] as String?;
      final width = videoStream?['width'] as int?;
      final height = videoStream?['height'] as int?;

      double? fps;
      final frRaw = videoStream?['avg_frame_rate'] ?? videoStream?['r_frame_rate'];
      if (frRaw is String && frRaw.contains('/')) {
        final parts = frRaw.split('/');
        final a = double.tryParse(parts[0]);
        final b = double.tryParse(parts[1]);
        if (a != null && b != null && b != 0) fps = a / b;
      } else if (frRaw is double) {
        fps = frRaw;
      }

      Duration? duration;
      final durRaw = videoStream?['duration'] ?? data['format']?['duration'];
      if (durRaw is String) {
        final d = double.tryParse(durRaw);
        if (d != null) duration = Duration(milliseconds: (d * 1000).round());
      }

      return VideoMeta(
        codec: codec,
        width: width,
        height: height,
        fps: fps,
        duration: duration,
      );
    } catch (_) {
      return null;
    }
  }
}
