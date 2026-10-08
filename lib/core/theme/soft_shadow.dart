import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A blurred rounded-rect shadow drawn from a small baked image: the blur is
/// rendered once, at a quarter of the size, and stretched (a shadow has no
/// detail to lose). A live blur under a 3D transform (the camera swap) or
/// over a full screen costs slower GPUs an extra full-size pass every frame.
///
/// Paints like `BoxShadow(color, blurRadius, offset)` round its own box.
class SoftShadow extends StatelessWidget {
  const SoftShadow({
    super.key,
    required this.color,
    required this.blurRadius,
    this.offset = Offset.zero,
    this.radius = 0,
  });

  final Color color;
  final double blurRadius;
  final Offset offset;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SoftShadowPainter(color, blurRadius, offset, radius), size: Size.infinite);
}

class _SoftShadowPainter extends CustomPainter {
  _SoftShadowPainter(this.color, this.blur, this.offset, this.radius);

  final Color color;
  final double blur;
  final Offset offset;
  final double radius;

  static const _scale = 0.25;
  static final _cache = <String, ui.Image>{};

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final pad = blur * 1.5;
    final key = '${size.width.round()}x${size.height.round()}/$blur/$radius/${color.toARGB32()}';
    final image = _cache[key] ??= _bake(size, pad);
    if (_cache.length > 8) _cache.remove(_cache.keys.first)?.dispose();
    final dst = Rect.fromLTWH(-pad, -pad, size.width + 2 * pad, size.height + 2 * pad).shift(offset);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  ui.Image _bake(Size size, double pad) {
    final w = ((size.width + 2 * pad) * _scale).ceil(), h = ((size.height + 2 * pad) * _scale).ceil();
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    final rect = Rect.fromLTWH(pad * _scale, pad * _scale, size.width * _scale, size.height * _scale);
    c.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius * _scale)),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, Shadow.convertRadiusToSigma(blur) * _scale),
    );
    return recorder.endRecording().toImageSync(w, h);
  }

  @override
  bool shouldRepaint(_SoftShadowPainter old) =>
      old.color != color || old.blur != blur || old.offset != offset || old.radius != radius;
}

/// A soft-edged shadow under a stroked [path] without a blur pass: a few
/// widening, fainter strokes (cheap under any transform).
void softStroke(Canvas canvas, Path path, double width, double blur, Color color) {
  const steps = 4;
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = color.withValues(alpha: color.a / steps);
  for (var i = 0; i < steps; i++) {
    canvas.drawPath(path, paint..strokeWidth = width + blur * 2 * (1 - i / steps));
  }
}
