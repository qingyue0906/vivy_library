import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/audio_track.dart';

/// 纯 Dart 的音频标签解析服务（零新增依赖）。
///
/// 从音频文件内嵌标签中读取：标题 / 艺人 / 专辑 / 封面图 / 歌词。
/// 重点覆盖 mp3(ID3v2/ID3v1)、flac(VORBIS_COMMENT + PICTURE)、
/// m4a(ilst covr/©lyr)、ogg/opus(VORBIS_COMMENT + METADATA_BLOCK_PICTURE)。
/// wav/mid 等无内嵌标签格式返回空元数据（仅文件名兜底）。
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

  /// 读取单个文件的标签元数据。结果按 path 缓存，以 size+mtime 做失效校验；
  /// 命中缓存直接秒回，重开项目不重复读盘。容量上限 + LRU 淘汰，封面内存有界。
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
      final bytes = await f.readAsBytes();
      final ext = p.extension(path).toLowerCase().replaceAll('.', '');
      AudioMeta meta;
      switch (ext) {
        case 'mp3':
          meta = _readMp3(bytes);
        case 'flac':
          meta = _readFlac(bytes);
        case 'm4a' || 'mp4' || 'm4v' || 'aac':
          meta = _readM4a(bytes);
        case 'ogg' || 'opus':
          meta = _readOgg(bytes);
        default:
          meta = const AudioMeta();
      }
      _putCache(path, meta, size, mtime);
      return meta;
    } catch (_) {
      return const AudioMeta();
    }
  }

  // ===================== 通用编解码辅助 =====================

  static int _u32(Uint8List b, int off) =>
      ByteData.sublistView(b).getUint32(off, Endian.big);

  static int _u24(Uint8List b, int off) =>
      (b[off] << 16) | (b[off + 1] << 8) | b[off + 2];

  /// 解析 4 字节 synchsafe 整型（每字节仅用低 7 位）。
  static int _synchsafe(Uint8List b, int off) => ((b[off] & 0x7F) << 21) |
      ((b[off + 1] & 0x7F) << 14) |
      ((b[off + 2] & 0x7F) << 7) |
      (b[off + 3] & 0x7F);

  static String _fourcc(Uint8List b, int off) =>
      String.fromCharCode(b[off]) +
      String.fromCharCode(b[off + 1]) +
      String.fromCharCode(b[off + 2]) +
      String.fromCharCode(b[off + 3]);

  static String _utf16(List<int> bytes, Endian endian) {
    if (bytes.length < 2) return '';
    final bd = ByteData.sublistView(Uint8List.fromList(bytes));
    final sb = StringBuffer();
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      sb.writeCharCode(bd.getUint16(i, endian));
    }
    return sb.toString();
  }

  /// 按 ID3 文本编码字节解码文本，并去掉末尾的 null 终止符。
  /// enc: 0=latin1, 1=utf-16(BOM), 2=utf-16BE, 3=utf-8。
  static String _decodeText(int enc, List<int> data) {
    if (data.isEmpty) return '';
    if (enc == 0 || enc == 8) {
      return latin1.decode(data, allowInvalid: true).replaceAll('\u0000', '').trim();
    } else if (enc == 1) {
      Endian e = Endian.little;
      var start = 0;
      if (data.length >= 2) {
        if (data[0] == 0xFE && data[1] == 0xFF) {
          e = Endian.big;
          start = 2;
        } else if (data[0] == 0xFF && data[1] == 0xFE) {
          e = Endian.little;
          start = 2;
        }
      }
      return _utf16(data.sublist(start), e).replaceAll('\u0000', '').trim();
    } else if (enc == 2) {
      return _utf16(data, Endian.big).replaceAll('\u0000', '').trim();
    } else {
      return utf8
          .decode(data, allowMalformed: true)
          .replaceAll('\u0000', '')
          .trim();
    }
  }

  // ===================== MP3 (ID3v2 / ID3v1) =====================

  static AudioMeta _readMp3(Uint8List bytes) {
    String? title, artist, album, lyrics;
    Uint8List? cover;
    // ID3v2
    if (bytes.length > 10 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      final major = bytes[3];
      final size = _synchsafe(bytes, 6);
      final tagEnd = 10 + size;
      final idLen = major == 2 ? 3 : 4;
      final synchFrame = major > 2; // v2.4 帧大小用 synchsafe
      var pos = 10;
      while (pos + idLen + 6 <= tagEnd && pos + idLen <= bytes.length) {
        var id = '';
        for (var i = 0; i < idLen; i++) {
          id += String.fromCharCode(bytes[pos + i]);
        }
        if (id == '\u0000' * idLen || id.isEmpty || id.contains('\u0000')) {
          break; // 进入 padding
        }
        final frameSize = major == 2
            ? _u24(bytes, pos + idLen)
            : (synchFrame
                ? _synchsafe(bytes, pos + idLen)
                : _u32(bytes, pos + idLen));
        if (frameSize <= 0) break;
        final dataStart = pos + idLen + (major == 2 ? 3 : 6);
        final dataEnd = dataStart + frameSize;
        if (dataEnd > bytes.length) break;
        final fdata = bytes.sublist(dataStart, dataEnd);
        if (id == 'APIC' || id == 'PIC') {
          cover ??= _parseApic(fdata);
        } else if (id == 'USLT' || id == 'ULT') {
          lyrics ??= _parseDescribedText(fdata);
        } else if (id == 'SYLT' || id == 'SLT') {
          lyrics ??= _parseSylt(fdata);
        } else if (id == 'TIT2' || id == 'TT2') {
          title ??= _parseTextField(fdata);
        } else if (id == 'TPE1' || id == 'TP1' || id == 'TPE2' || id == 'TP2') {
          artist ??= _parseTextField(fdata);
        } else if (id == 'TALB' || id == 'TAL') {
          album ??= _parseTextField(fdata);
        }
        pos = dataEnd;
      }
    }
    // ID3v1（尾部 128 字节 "TAG"）
    if (bytes.length > 128) {
      final tail = bytes.sublist(bytes.length - 128);
      if (tail[0] == 0x54 && tail[1] == 0x41 && tail[2] == 0x47) {
        title ??= _latin1Clean(tail, 3, 30);
        artist ??= _latin1Clean(tail, 33, 30);
        album ??= _latin1Clean(tail, 63, 30);
      }
    }
    if (title == null &&
        artist == null &&
        album == null &&
        lyrics == null &&
        cover == null) {
      return const AudioMeta();
    }
    return AudioMeta(
      title: title,
      artist: artist,
      album: album,
      lyrics: lyrics,
      coverBytes: cover,
    );
  }

  /// APIC/PIC：编码字节 + MIME(null 结尾) + 图片类型(1) + 描述(null 结尾) + 图片数据。
  static Uint8List? _parseApic(Uint8List d) {
    if (d.isEmpty) return null;
    final enc = d[0];
    var p = 1;
    final mimeEnd = _findNull(d, p, enc);
    if (mimeEnd < 0) return null;
    p = mimeEnd + 1;
    if (p >= d.length) return null;
    p += 1; // 跳过图片类型字节
    final descEnd = _findNull(d, p, enc);
    if (descEnd < 0) return null;
    p = enc == 1 || enc == 2 ? descEnd + 2 : descEnd + 1;
    if (p >= d.length) return null;
    return d.sublist(p);
  }

  /// USLT：编码(1) + 语言(3) + 描述(null 结尾) + 文本。
  static String? _parseDescribedText(Uint8List d) {
    if (d.length < 4) return null;
    final enc = d[0];
    var p = 4; // 跳过编码 + 语言
    final descEnd = _findNull(d, p, enc);
    if (descEnd < 0) return _decodeText(enc, d.sublist(4)).trim();
    p = enc == 1 || enc == 2 ? descEnd + 2 : descEnd + 1;
    if (p >= d.length) return null;
    final txt = _decodeText(enc, d.sublist(p));
    return txt.isEmpty ? null : txt;
  }

  /// SYLT（逐字时间戳歌词）：尽力抽取纯文本（去掉 2 字节时间戳）。
  static String? _parseSylt(Uint8List d) {
    if (d.length < 6) return null;
    final enc = d[0];
    var p = 6; // 编码(1)+语言(3)+时间戳格式(1)+内容类型(1)
    final descEnd = _findNull(d, p, enc);
    if (descEnd < 0) return null;
    p = enc == 1 || enc == 2 ? descEnd + 2 : descEnd + 1;
    final sb = StringBuffer();
    var guard = 0;
    while (p + 2 <= d.length && guard++ < 100000) {
      p += 2; // 跳过 2 字节时间戳
      if (p >= d.length) break;
      final end = _findNull(d, p, enc);
      if (end < 0) break;
      final frag = d.sublist(p, enc == 1 || enc == 2 ? end - 2 : end - 1);
      final txt = _decodeText(enc, frag);
      if (txt.isNotEmpty) {
        sb.write(txt);
        sb.write(' ');
      }
      p = end;
    }
    final res = sb.toString().trim();
    return res.isEmpty ? null : res;
  }

  static String? _parseTextField(Uint8List d) {
    if (d.isEmpty) return null;
    final enc = d[0];
    final txt = _decodeText(enc, d.sublist(1));
    return txt.isEmpty ? null : txt;
  }

  /// 找到编码相关的 null 终止位置（utf-16 为双字节 0x0000）。
  static int _findNull(Uint8List d, int start, int enc) {
    if (enc == 1 || enc == 2) {
      var i = start;
      while (i + 1 < d.length) {
        if (d[i] == 0 && d[i + 1] == 0) return i;
        i += 2;
      }
      return -1;
    }
    for (var i = start; i < d.length; i++) {
      if (d[i] == 0) return i;
    }
    return -1;
  }

  static String _latin1Clean(Uint8List b, int off, int len) {
    if (off + len > b.length) return '';
    return latin1
        .decode(b.sublist(off, off + len), allowInvalid: true)
        .replaceAll(RegExp(r'\u0000.*'), '')
        .trim();
  }

  // ===================== FLAC =====================

  static AudioMeta _readFlac(Uint8List bytes) {
    if (bytes.length < 4 ||
        bytes[0] != 0x66 ||
        bytes[1] != 0x4C ||
        bytes[2] != 0x61 ||
        bytes[3] != 0x43) {
      return const AudioMeta();
    }
    var pos = 4;
    String? title, artist, album, lyrics;
    Uint8List? cover;
    var last = false;
    while (!last && pos + 4 <= bytes.length) {
      final flags = bytes[pos];
      last = (flags & 0x80) != 0;
      final type = flags & 0x7F;
      final blockLen = _u24(bytes, pos + 1);
      final dataStart = pos + 4;
      final dataEnd = dataStart + blockLen;
      if (dataEnd > bytes.length) break;
      final blk = bytes.sublist(dataStart, dataEnd);
      if (type == 4) {
        // VORBIS_COMMENT
        final v = _parseVorbisComment(blk);
        title ??= v['TITLE'];
        artist ??= v['ARTIST'] ?? v['PERFORMER'];
        album ??= v['ALBUM'];
        lyrics ??= v['LYRICS'] ?? v['UNSYNCEDLYRICS'] ?? v['LYRIC'];
        if (cover == null && v.containsKey('METADATA_BLOCK_PICTURE')) {
          try {
            cover = _parseFlacPicture(
              Uint8List.fromList(base64Decode(v['METADATA_BLOCK_PICTURE']!)),
            );
          } catch (_) {}
        }
      } else if (type == 6) {
        cover ??= _parseFlacPicture(blk);
      }
      pos = dataEnd;
    }
    if (title == null &&
        artist == null &&
        album == null &&
        lyrics == null &&
        cover == null) {
      return const AudioMeta();
    }
    return AudioMeta(
      title: title,
      artist: artist,
      album: album,
      lyrics: lyrics,
      coverBytes: cover,
    );
  }

  static Map<String, String> _parseVorbisComment(Uint8List b) {
    final map = <String, String>{};
    if (b.length < 8) return map;
    var p = 0;
    final vendorLen = _u32(b, p);
    p += 4 + vendorLen;
    if (p + 4 > b.length) return map;
    final count = _u32(b, p);
    p += 4;
    for (var i = 0; i < count && p + 4 <= b.length; i++) {
      final len = _u32(b, p);
      p += 4;
      if (p + len > b.length) break;
      final entry = utf8.decode(b.sublist(p, p + len), allowMalformed: true);
      p += len;
      final eq = entry.indexOf('=');
      if (eq < 0) continue;
      final key = entry.substring(0, eq).toUpperCase();
      final val = entry.substring(eq + 1);
      map.putIfAbsent(key, () => val);
    }
    return map;
  }

  /// 解析 FLAC/METADATA_BLOCK_PICTURE 二进制块：取出末尾的图片数据。
  static Uint8List? _parseFlacPicture(Uint8List b) {
    if (b.length < 4) return null;
    var p = 4; // 图片类型(4)
    if (p + 4 > b.length) return null;
    final mimeLen = _u32(b, p);
    p += 4 + mimeLen;
    if (p + 4 > b.length) return null;
    final descLen = _u32(b, p);
    p += 4 + descLen;
    if (p + 16 > b.length) return null;
    p += 16; // width/height/depth/colors(各4)
    if (p + 4 > b.length) return null;
    final dataLen = _u32(b, p);
    p += 4;
    if (p + dataLen > b.length || dataLen <= 0) return null;
    return b.sublist(p, p + dataLen);
  }

  // ===================== M4A (ilst) =====================

  static AudioMeta _readM4a(Uint8List bytes) {
    final atoms = <String, List<int>>{};
    _collectIlst(bytes, 0, bytes.length, atoms);
    if (atoms.isEmpty) return const AudioMeta();
    final title = _m4aText(atoms['©nam']);
    final artist = _m4aText(atoms['©ART']) ?? _m4aText(atoms['aART']);
    final album = _m4aText(atoms['©alb']);
    final lyrics = _m4aText(atoms['©lyr']) ?? _m4aText(atoms['lyr']);
    final cover = atoms['covr'];
    if (title == null &&
        artist == null &&
        album == null &&
        lyrics == null &&
        cover == null) {
      return const AudioMeta();
    }
    return AudioMeta(
      title: title,
      artist: artist,
      album: album,
      lyrics: lyrics,
      coverBytes: cover == null ? null : Uint8List.fromList(cover),
    );
  }

  static void _collectIlst(Uint8List b, int start, int end,
      Map<String, List<int>> out) {
    var p = start;
    while (p + 8 <= end) {
      final size = _u32(b, p);
      if (size < 8 || p + size > end) break;
      final type = _fourcc(b, p + 4);
      final ds = p + 8;
      final de = p + size;
      if (type == 'ilst') {
        _parseIlst(b, ds, de, out);
      } else if (const {
        'moov',
        'trak',
        'udta',
        'mdia',
        'minf',
        'stbl',
        'dinf',
        'meta',
        'stsd'
      }.contains(type)) {
        var childStart = ds;
        if (type == 'meta' || type == 'stsd') childStart = ds + 4;
        _collectIlst(b, childStart, de, out);
      }
      p = de;
    }
  }

  static void _parseIlst(Uint8List b, int start, int end,
      Map<String, List<int>> out) {
    var p = start;
    while (p + 8 <= end) {
      final size = _u32(b, p);
      if (size < 8 || p + size > end) break;
      final type = _fourcc(b, p + 4);
      final ds = p + 8;
      final de = p + size;
      // 找子 'data' 原子：4(size)+4('data')+4(版本/标志)+4(类型)+值
      var dp = ds;
      while (dp + 8 <= de) {
        final dsize = _u32(b, dp);
        if (dsize < 8 || dp + dsize > de) break;
        final dtype = _fourcc(b, dp + 4);
        if (dtype == 'data') {
          final vstart = dp + 16;
          if (vstart < dp + dsize) {
            out[type] = b.sublist(vstart, dp + dsize);
          }
          break;
        }
        dp += dsize;
      }
      p = de;
    }
  }

  static String? _m4aText(List<int>? v) {
    if (v == null || v.isEmpty) return null;
    var data = v;
    // 去掉可能的 UTF-8 BOM
    if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
      data = data.sublist(3);
    }
    final txt = utf8.decode(data, allowMalformed: true).replaceAll('\u0000', '').trim();
    return txt.isEmpty ? null : txt;
  }

  // ===================== OGG / OPUS =====================

  static AudioMeta _readOgg(Uint8List bytes) {
    final packets = _oggPackets(bytes);
    if (packets.length < 2) return const AudioMeta();
    // 第二个 packet 为 Vorbis comment。
    final v = _parseVorbisComment(packets[1]);
    final title = v['TITLE'];
    final artist = v['ARTIST'] ?? v['PERFORMER'];
    final album = v['ALBUM'];
    final lyrics = v['LYRICS'] ?? v['UNSYNCEDLYRICS'] ?? v['LYRIC'];
    Uint8List? cover;
    if (v.containsKey('METADATA_BLOCK_PICTURE')) {
      try {
        cover = _parseFlacPicture(
          Uint8List.fromList(base64Decode(v['METADATA_BLOCK_PICTURE']!)),
        );
      } catch (_) {}
    }
    if (title == null &&
        artist == null &&
        album == null &&
        lyrics == null &&
        cover == null) {
      return const AudioMeta();
    }
    return AudioMeta(
      title: title,
      artist: artist,
      album: album,
      lyrics: lyrics,
      coverBytes: cover,
    );
  }

  /// 解析 OGG 页结构，拼接出完整 packet（lacing 重组）。只需前两个 packet。
  static List<Uint8List> _oggPackets(Uint8List b) {
    final packets = <Uint8List>[];
    var p = 0;
    Uint8List? partial;
    while (p + 27 <= b.length && packets.length < 3) {
      if (b[p] != 0x4F || b[p + 1] != 0x67 || b[p + 2] != 0x67 || b[p + 3] != 0x53) {
        break; // 非 'OggS'
      }
      p += 4;
      p += 1; // version
      final flags = b[p];
      p += 1;
      p += 8; // granule position
      p += 4; // bitstream serial
      p += 4; // page sequence
      p += 4; // checksum
      final segCount = b[p];
      p += 1;
      final segSizes = <int>[];
      var total = 0;
      for (var i = 0; i < segCount; i++) {
        final s = b[p + i];
        segSizes.add(s);
        total += s;
      }
      p += segCount;
      if (p + total > b.length) break;
      final pageData = b.sublist(p, p + total);
      p += total;
      var sp = 0;
      for (final s in segSizes) {
        final chunk = pageData.sublist(sp, sp + s);
        sp += s;
        partial = partial == null
            ? Uint8List.fromList(chunk)
            : Uint8List.fromList([...partial, ...chunk]);
        if (s < 255) {
          packets.add(partial);
          partial = null;
        }
      }
      if ((flags & 0x04) != 0) break; // 末页
    }
    if (partial != null) packets.add(partial);
    return packets;
  }
}

/// 标签缓存条目：解析出的元数据 + 文件 size/mtime（用于失效校验）。
class _TagCacheEntry {
  final AudioMeta meta;
  final int size;
  final int mtime;

  _TagCacheEntry(this.meta, this.size, this.mtime);
}
