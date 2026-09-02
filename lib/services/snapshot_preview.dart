import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:image_size_getter/image_size_getter.dart';
import 'package:image_size_getter/file_input.dart';

/// 快照预览图处理器。
///
/// 处理规则（与用户确认的方案一致）：
/// - 短边 360px 等比缩放（短边已 ≤360 时跳过缩放）
/// - 动图（GIF）只提取第一帧（GifDecoder 逐帧接口，避免全帧解码爆内存）
/// - 透明通道先铺白底（JPEG 无 alpha，直接编码透明区域会变黑块）
/// - 编码为 JPEG q80
/// - 任一步失败返回 false，由调用方回退为"复制原文件"
///
/// 图片解码/编码是纯 CPU 密集操作，全部走同步函数，由调用方通过
/// compute()/Isolate 放到后台线程执行，避免大库创建快照时阻塞 UI。
class SnapshotPreview {
  /// 读取图片原始尺寸（文件头解析，不解码像素）。失败返回 null。
  static (int, int)? readSize(String path) {
    try {
      final r = ImageSizeGetter.getSizeResult(FileInput(File(path)));
      var w = r.size.width;
      var h = r.size.height;
      if (r.size.needRotate) {
        final t = w;
        w = h;
        h = t;
      }
      if (w > 0 && h > 0) return (w, h);
    } catch (_) {}
    return null;
  }

  /// 处理 [srcPath] 并写入 [destPath]（.jpg）。成功返回 true；失败返回 false，
  /// 调用方应改为把原文件复制到 [destPath]（保留原扩展名）。
  static bool processSync(String srcPath, String destPath) {
    final file = File(srcPath);
    if (!file.existsSync()) return false;
    final bytes = file.readAsBytesSync();
    if (bytes.isEmpty) return false;

    try {
      img.Image? decoded;
      final lower = srcPath.toLowerCase();
      if (lower.endsWith('.gif')) {
        // 只解第一帧：GifDecoder.startDecode + decodeFrame(0) 按帧解码，
        // 不把整段动画展开进内存。
        try {
          final decoder = img.GifDecoder();
          if (decoder.startDecode(bytes) != null) {
            decoded = decoder.decodeFrame(0);
          }
        } catch (_) {
          decoded = null;
        }
      }
      decoded ??= img.decodeImage(bytes);
      if (decoded == null) return false;

      // 短边 360 等比缩放
      var target = decoded;
      final w = decoded.width;
      final h = decoded.height;
      final shortSide = w < h ? w : h;
      if (shortSide > 360) {
        final scale = 360.0 / shortSide;
        final nw = (w * scale).round().clamp(1, 1 << 16);
        final nh = (h * scale).round().clamp(1, 1 << 16);
        target = img.copyResize(
          decoded,
          width: nw,
          height: nh,
          interpolation: img.Interpolation.linear,
        );
      }

      // 透明通道铺白底（JPEG 无 alpha，直接编码透明区域会变黑块）
      if (target.numChannels == 4) {
        final bg = img.Image(
          width: target.width,
          height: target.height,
          numChannels: 3,
        );
        img.fill(bg, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(bg, target);
        target = bg;
      }

      final encoded = img.encodeJpg(target, quality: 80);
      if (encoded.isEmpty) return false;
      final out = File(destPath);
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(encoded, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 复制原文件作为回退预览图（保留原扩展名）。返回是否成功。
  static bool copyOriginalSync(String srcPath, String destPath) {
    try {
      final src = File(srcPath);
      if (!src.existsSync()) return false;
      final out = File(destPath);
      out.parent.createSync(recursive: true);
      src.copySync(destPath);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// compute() 的入参载体：源路径 + 目标路径（必须是顶层可序列化对象）。
class PreviewJob {
  final String srcPath;
  final String destPath;
  const PreviewJob(this.srcPath, this.destPath);
}

/// compute 入口：同步处理一张预览图。成功（已写入 .jpg）返回 true。
bool processPreviewSync(PreviewJob job) =>
    SnapshotPreview.processSync(job.srcPath, job.destPath);

/// compute 入口：复制原文件作为回退预览图。成功返回 true。
bool copyOriginalPreviewSync(PreviewJob job) =>
    SnapshotPreview.copyOriginalSync(job.srcPath, job.destPath);
