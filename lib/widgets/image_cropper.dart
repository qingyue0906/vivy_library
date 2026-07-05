import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/translations.dart';

class ImageCropper extends StatefulWidget {
  final String imagePath;
  final double width;
  final double height;

  const ImageCropper({
    super.key,
    required this.imagePath,
    this.width = 400,
    this.height = 300,
  });

  @override
  State<ImageCropper> createState() => ImageCropperState();
}

class ImageCropperState extends State<ImageCropper> {
  ui.Image? _image;
  Rect _cropRect = Rect.zero;
  bool _loading = true;
  String? _dragHandle;

  static const double _handleSize = 16;
  static const double _minCrop = 40;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      setState(() {
        _image = img;
        _loading = false;
        _initCropRect(img.width, img.height);
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _initCropRect(int imgW, int imgH) {
    final mw = widget.width - 20;
    final mh = widget.height - 20;
    final scale = (mw / imgW).clamp(0.0, mh / imgH);
    final dw = imgW * scale;
    final dh = imgH * scale;
    final dx = (widget.width - dw) / 2;
    final dy = (widget.height - dh) / 2;
    _cropRect = Rect.fromLTWH(dx, dy, dw, dh);
  }

  void _clampCropToImage() {
    final imgRect = _imageDisplayRect();
    _cropRect = Rect.fromLTRB(
      _cropRect.left.clamp(imgRect.left, imgRect.right - _minCrop),
      _cropRect.top.clamp(imgRect.top, imgRect.bottom - _minCrop),
      _cropRect.right.clamp(imgRect.left + _minCrop, imgRect.right),
      _cropRect.bottom.clamp(imgRect.top + _minCrop, imgRect.bottom),
    );
  }

  Rect _imageDisplayRect() {
    if (_image == null) return Rect.zero;
    final mw = widget.width - 20;
    final mh = widget.height - 20;
    final scale = (mw / _image!.width).clamp(0.0, mh / _image!.height);
    final dw = _image!.width * scale;
    final dh = _image!.height * scale;
    final dx = (widget.width - dw) / 2;
    final dy = (widget.height - dh) / 2;
    return Rect.fromLTWH(dx, dy, dw, dh);
  }

  String? _hitTest(Offset pos) {
    for (final corner in _corners) {
      if ((pos - _cropRectPoint(corner)).distance < _handleSize) return corner;
    }
    for (final edge in _edges) {
      if (_distToEdge(pos, edge) < _handleSize / 2) return edge;
    }
    if (_cropRect.contains(pos)) return 'body';
    return null;
  }

  List<String> get _corners => ['tl', 'tr', 'bl', 'br'];
  List<String> get _edges => ['t', 'r', 'b', 'l'];

  Offset _cropRectPoint(String handle) {
    return switch (handle) {
      'tl' => Offset(_cropRect.left, _cropRect.top),
      'tr' => Offset(_cropRect.right, _cropRect.top),
      'bl' => Offset(_cropRect.left, _cropRect.bottom),
      'br' => Offset(_cropRect.right, _cropRect.bottom),
      't' => Offset(_cropRect.center.dx, _cropRect.top),
      'b' => Offset(_cropRect.center.dx, _cropRect.bottom),
      'l' => Offset(_cropRect.left, _cropRect.center.dy),
      'r' => Offset(_cropRect.right, _cropRect.center.dy),
      _ => Offset.zero,
    };
  }

  double _distToEdge(Offset pos, String edge) {
    final (p1, p2) = switch (edge) {
      't' => (Offset(_cropRect.left, _cropRect.top), Offset(_cropRect.right, _cropRect.top)),
      'b' => (Offset(_cropRect.left, _cropRect.bottom), Offset(_cropRect.right, _cropRect.bottom)),
      'l' => (Offset(_cropRect.left, _cropRect.top), Offset(_cropRect.left, _cropRect.bottom)),
      'r' => (Offset(_cropRect.right, _cropRect.top), Offset(_cropRect.right, _cropRect.bottom)),
      _ => (Offset.zero, Offset.zero),
    };
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final len = (dx * dx + dy * dy);
    if (len == 0) return (pos - p1).distance;
    final t = ((pos.dx - p1.dx) * dx + (pos.dy - p1.dy) * dy) / len;
    final tClamped = t.clamp(0.0, 1.0);
    final proj = Offset(p1.dx + tClamped * dx, p1.dy + tClamped * dy);
    return (pos - proj).distance;
  }

  Rect _dragCrop(Offset delta, String handle, Rect current) {
    double l = current.left, t = current.top, r = current.right, b = current.bottom;
    switch (handle) {
      case 'tl': l += delta.dx; t += delta.dy;
      case 'tr': r += delta.dx; t += delta.dy;
      case 'bl': l += delta.dx; b += delta.dy;
      case 'br': r += delta.dx; b += delta.dy;
      case 't': t += delta.dy;
      case 'b': b += delta.dy;
      case 'l': l += delta.dx;
      case 'r': r += delta.dx;
    }
    if (r - l < _minCrop) { if (handle == 'tr' || handle == 'r' || handle == 'br') r = l + _minCrop; else l = r - _minCrop; }
    if (b - t < _minCrop) { if (handle == 'br' || handle == 'b' || handle == 'bl') b = t + _minCrop; else t = b - _minCrop; }
    return Rect.fromLTRB(l, t, r, b);
  }

  Future<Uint8List> cropImage() async {
    if (_image == null) throw Exception('No image loaded');
    final displayRect = _imageDisplayRect();
    final scaleX = _image!.width / displayRect.width;
    final scaleY = _image!.height / displayRect.height;
    final srcRect = Rect.fromLTWH(
      (_cropRect.left - displayRect.left) * scaleX,
      (_cropRect.top - displayRect.top) * scaleY,
      _cropRect.width * scaleX,
      _cropRect.height * scaleY,
    ).intersect(Rect.fromLTWH(0, 0, _image!.width.toDouble(), _image!.height.toDouble()));

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, srcRect.width, srcRect.height));
    canvas.drawImageRect(_image!, srcRect, Rect.fromLTWH(0, 0, srcRect.width, srcRect.height), Paint());
    final picture = recorder.endRecording();
    final img = await picture.toImage(srcRect.width.toInt(), srcRect.height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return SizedBox(
        width: widget.width, height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_image == null) {
      return SizedBox(
        width: widget.width, height: widget.height,
        child: Center(child: Text(Strings.t('imageLoadFailed'))),
      );
    }
    return SizedBox(
      width: widget.width, height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: GestureDetector(
          onPanStart: (d) => _dragHandle = _hitTest(d.localPosition),
          onPanUpdate: (d) {
            if (_dragHandle == 'body') {
              setState(() {
                _cropRect = _cropRect.shift(d.delta);
                _clampCropToImage();
              });
            } else if (_dragHandle != null) {
              setState(() {
                _cropRect = _dragCrop(d.delta, _dragHandle!, _cropRect);
                _clampCropToImage();
              });
            }
          },
          onPanEnd: (_) => _dragHandle = null,
          child: CustomPaint(
            painter: _CropPainter(
              image: _image!,
              displayRect: _imageDisplayRect(),
              cropRect: _cropRect,
              handleSize: _handleSize,
              gridColor: cs.primary,
              overlayColor: Colors.black.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect displayRect;
  final Rect cropRect;
  final double handleSize;
  final Color gridColor;
  final Color overlayColor;

  _CropPainter({
    required this.image,
    required this.displayRect,
    required this.cropRect,
    required this.handleSize,
    required this.gridColor,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      displayRect,
      Paint(),
    );

    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = overlayColor);

    final paint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(cropRect, paint);

    for (final corner in ['tl', 'tr', 'bl', 'br']) {
      final pos = switch (corner) {
        'tl' => Offset(cropRect.left, cropRect.top),
        'tr' => Offset(cropRect.right, cropRect.top),
        'bl' => Offset(cropRect.left, cropRect.bottom),
        'br' => Offset(cropRect.right, cropRect.bottom),
        _ => Offset.zero,
      };
      canvas.drawCircle(pos, handleSize / 2, Paint()..color = gridColor);
      canvas.drawCircle(pos, handleSize / 2 - 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.displayRect != displayRect || old.cropRect != cropRect;
}