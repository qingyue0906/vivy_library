import 'dart:typed_data';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import '../models/audio_track.dart';

/// 音频标签解析服务。
///
/// 基于纯 Dart 包 [audio_metadata_reader]（无原生 / Rust 构建，跨平台直接可用）读取：
/// 标题 / 艺人 / 专辑 / 封面图 / 内嵌歌词 / 时长，覆盖 mp3/flac/m4a/ogg 等常见格式。
/// 该包原生按需读取、不整文件常驻，配合下方 LRU 缓存与封面缩略图，常驻内存有界。
class AudioTagService {
  /// 受支持的音频扩展名（含 mid/midi 尽力播放）。
  static const audioExts = {
    'mp3', 'flac', 'wav', 'aac', 'ogg', 'opus', 'm4a', 'm4v',
    'wma', 'mid', 'midi', 'mp4', 'caf', 'aif', 'aiff',
  };

  static bool isAudioFile(String path) =>
      audioExts.contains(p.extension(path).toLowerCase().replaceAll('.', ''));

  // ===================== 标签缓存（LRU 限容） =====================
  //
  // 旧实现用「path::size::mtime」作 key 写入一个永不清理的静态 Map，导致：
  // 1) 反复打开不同项目时内嵌封面字节（coverBytes）无限累积，内存只增不减；
  // 2) 文件被云盘/git/解压触碰后 mtime 变化 → 旧 key 的封面永不回收，僵尸 key 膨胀。
  //
  // 现改为「path 主键 + size/mtime 失效校验 + LRU 容量上限」：
  // - key 用 path，size/mtime 仅用于判断文件是否被修改（失效则重读），不再因
  //   mtime 变化产生僵尸 key；
  // - 容量封顶（_maxCache），超出淘汰最久未访问项，封面内存被压在上限内；
  // - 提供 [clearCache] 供「切换超大项目 / 退出 app」等场景主动清场。

  /// 缓存条目数上限。超出按 LRU 淘汰最旧项。可按项目规模调整。
  static const int _maxCache = 1200;

  static final Map<String, _TagCacheEntry> _cache = {};
  static final List<String> _lru = []; // 队头最旧，队尾最新

  static void _touchLru(String path) {
    final i = _lru.indexOf(path);
    if (i >= 0) _lru.removeAt(i);
    _lru.add(path);
  }

  static void _putCache(String path, AudioMeta meta, int size, int mtime) {
    _cache[path] = _TagCacheEntry(meta, size, mtime);
    _lru.add(path);
    while (_lru.length > _maxCache) {
      final old = _lru.removeAt(0);
      _cache.remove(old);
    }
  }

  /// 主动清空标签缓存（封面字节随之释放）。跨页面仍有效的「组合元数据缓存」
  /// 在 [AudioMetadataService] 中维护，调用方按需处理，此处只负责标签解析缓存。
  static void clearCache() {
    _cache.clear();
    _lru.clear();
  }

  /// 读取单个文件的标签元数据。使用 [readMetadata]（纯 Dart 按需读取，不整文件
  /// 常驻）取标题/艺人/专辑/封面/时长/歌词；命中缓存直接秒回，重开项目不重复读盘。
  /// 容量上限 + LRU 淘汰，封面内存有界。
  static Future<AudioMeta> read(String path) async {
    try {
      final f = File(path);
      if (!f.existsSync()) return const AudioMeta();
      final stat = f.statSync();
      final size = stat.size;
      final mtime = stat.modified.millisecondsSinceEpoch;
      final cached = _cache[path];
      if (cached != null && cached.size == size && cached.mtime == mtime) {
        _touchLru(path);
        return cached.meta;
      }
      // 纯 Dart 解析，原生按需读取，不整文件常驻；封面按需取出（getImage:true）。
      final m = readMetadata(f, getImage: true);
      final cover = m.pictures.isNotEmpty ? m.pictures.first.bytes : null;
      final meta = AudioMeta(
        title: _nz(m.title),
        artist: _nz(m.artist),
        album: _nz(m.album),
        coverBytes: _toThumbnail(cover),
        lyrics: _nz(m.lyrics),
        duration: m.duration,
      );
      _putCache(path, meta, size, mtime);
      return meta;
    } catch (_) {
      return const AudioMeta();
    }
  }

  // ===================== 封面缩略图 =====================
  //
  // 内嵌封面原始图常 500–2000px、数百 KB~数 MB（FLAC/高清封面更夸张）。曾直接把原图
  // 字节塞进 coverBytes 并常驻内存，300 个音频因此占 ~1GB。现于解析阶段即把封面
  // 等比缩放到固定边长并重编码为紧凑格式（不透明图用 JPEG，透明图用 PNG），单张约
  // 20–60KB，常驻内存从数百 MB 降到 ~12MB。这在概念上对齐开源播放器（Phonograph/
  // VLC 等）"列表只显示小缩略图、大图按需另取"的做法。

  /// 内嵌封面缩略图目标边长。影响内存与正在播放页清晰度，512px 对桌面屏足够。
  static const int _coverThumbEdge = 512;

  /// 将内嵌封面解码并等比缩放到 [_coverThumbEdge]，再紧凑重编码；
  /// 失败则退化为原字节，保证至少能显示。返回 null 表示无封面。
  static Uint8List? _toThumbnail(Uint8List? cover) {
    if (cover == null || cover.isEmpty) return null;
    try {
      final decoded = img.decodeImage(cover);
      if (decoded == null) return null;
      final maxEdge = _coverThumbEdge;
      final Uint8List out;
      if (decoded.width > maxEdge || decoded.height > maxEdge) {
        final ratio = maxEdge /
            (decoded.width > decoded.height ? decoded.width : decoded.height);
        final r = img.copyResize(
          decoded,
          width: (decoded.width * ratio).round(),
          height: (decoded.height * ratio).round(),
        );
        out = decoded.hasAlpha
            ? img.encodePng(r)
            : img.encodeJpg(r, quality: 85);
      } else {
        out = decoded.hasAlpha
            ? img.encodePng(decoded)
            : img.encodeJpg(decoded, quality: 85);
      }
      return Uint8List.fromList(out);
    } catch (_) {
      return cover;
    }
  }

  /// 空串/纯空白归并为 null，统一「无标签」语义。
  static String? _nz(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }
}

/// 标签缓存条目：解析出的元数据 + 文件 size/mtime（用于失效校验）。
class _TagCacheEntry {
  final AudioMeta meta;
  final int size;
  final int mtime;

  _TagCacheEntry(this.meta, this.size, this.mtime);
}
