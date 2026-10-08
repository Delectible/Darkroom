import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The Darkroom rabbit (the app icon's drawing, tool/icon/make_icons.py):
/// two ears, a round head and X'd-out eyes. Flat [color], or [rgbSplit] for
/// the icon's mis-converged red / green / blue look. Used sparingly: the lab
/// stamp on the back of prints, the camera bodies' badge, the projector.
class DarkroomMark extends StatelessWidget {
  const DarkroomMark({super.key, this.size = 24, required this.color, this.rgbSplit = false});

  /// Height of the head-and-ears glyph.
  final double size;
  final Color color;
  final bool rgbSplit;

  /// Width / height of the glyph.
  static const aspect = (157 - 52) / (158 - 29);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * aspect, size),
      painter: DarkroomMarkPainter(color: color, rgbSplit: rgbSplit),
    );
  }
}

class DarkroomMarkPainter extends CustomPainter {
  DarkroomMarkPainter({required this.color, this.rgbSplit = false});

  final Color color;
  final bool rgbSplit;

  // Glyph bounds on the icon's 192 design grid.
  static const _x0 = 52.0, _y0 = 29.0, _y1 = 158.0;

  void _glyph(Canvas canvas, double s, Offset o, Color c) {
    canvas.save();
    canvas.translate(o.dx - _x0 * s, o.dy - _y0 * s);
    canvas.scale(s);
    final p = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(const Offset(80, 104), const Offset(70, 40), p); // straight ear
    canvas.drawPath(
      Path()
        ..moveTo(110, 100)
        ..lineTo(120, 48)
        ..lineTo(146, 60),
      p,
    ); // folded ear
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(94, 122), width: 84, height: 72),
      Paint()..color = c,
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / (_y1 - _y0);
    // Room round the glyph: the split copies and round caps reach past it.
    final layer = (Offset.zero & size).inflate(size.height * 0.15);
    // The glyph's parts overlap (ears into the head): draw them opaque and
    // apply the colour's transparency once, to the whole mark, so the
    // overlaps aren't darker.
    canvas.saveLayer(layer, Paint()..color = Color.fromRGBO(0, 0, 0, color.a));
    if (rgbSplit) {
      final d = 5 * s;
      for (final (c, dx) in [
        (const Color(0xFFFF0000), -d),
        (const Color(0xFF00FF00), 0.0),
        (const Color(0xFF0000FF), d),
      ]) {
        canvas.saveLayer(layer, Paint()..blendMode = BlendMode.plus);
        _glyph(canvas, s, Offset(dx, 0), c);
        canvas.restore();
      }
    } else {
      _glyph(canvas, s, Offset.zero, color.withValues(alpha: 1));
    }
    // X'd-out eyes, cut through.
    final eye = Paint()
      ..blendMode = BlendMode.clear
      ..strokeWidth = math.max(1, 5.5 * s)
      ..strokeCap = StrokeCap.round;
    for (final (ex, ey) in [(80.0, 118.0), (108.0, 118.0)]) {
      Offset at(double x, double y) => Offset((x - _x0) * s, (y - _y0) * s);
      canvas.drawLine(at(ex - 7, ey - 7), at(ex + 7, ey + 7), eye);
      canvas.drawLine(at(ex + 7, ey - 7), at(ex - 7, ey + 7), eye);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DarkroomMarkPainter old) => old.color != color || old.rgbSplit != rgbSplit;
}
