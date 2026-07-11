import '../models/video_entry.dart';
import 'fvp_player.dart';

/// 视频元数据探测：基于 fvp 的 libmdk（[FvpPlayer.probeVideoMeta]），
/// 通过 [VideoPlayerController.getMediaInfo()] 一次性拿到编码/分辨率/帧率/时长等信息。
///
/// 不再依赖系统 ffprobe（当前环境不可用），改为播放器内核直接提供。
class VideoMetadataService {
  /// 探测单个视频的元数据；失败返回 null。
  static Future<VideoMeta?> probe(String path) =>
      FvpPlayer.probeVideoMeta(path);
}
