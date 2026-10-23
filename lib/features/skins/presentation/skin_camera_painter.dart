import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/skins/camera_skins.dart';
import '../../cameras/domain/camera_spec.dart';

/// A camera seen from the front in a skin's colours: a rangefinder for
/// film, a compact for digital. Drawn with a few layers of detail (plates,
/// dials, windows, a lens with its rings) so it reads like a real camera
/// at the counter's size and still holds together on the shelf.
class SkinCameraPainter extends CustomPainter {
  SkinCameraPainter(this.skin, {this.dim = false});

  final CameraSkin skin;

  /// Locked: drawn in shadow.
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final film = skin.mode == AppMode.film;
    final bodyH = math.min(h * 0.74, w / 1.8);
    final bodyW = bodyH * 1.8;
    final body = Rect.fromCenter(center: Offset(w / 2, h * 0.58), width: bodyW, height: bodyH);
    // contact shadow on the pad / shelf
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, body.bottom + bodyH * 0.03),
        width: bodyW * 1.02,
        height: bodyH * 0.14,
      ),
      Paint()
        ..shader = RadialGradient(colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent])
            .createShader(
              Rect.fromCenter(center: Offset(w / 2, body.bottom), width: bodyW, height: bodyH * 0.14),
            ),
    );
    canvas.saveLayer(Offset.zero & size, Paint());
    if (film) {
      _film(canvas, body);
    } else {
      _digital(canvas, body);
    }
    if (dim) {
      canvas.drawPaint(
        Paint()
          ..color = const Color(0xFF0E0A07).withValues(alpha: 0.62)
          ..blendMode = BlendMode.srcATop,
      );
    }
    canvas.restore();
  }

  // ------------------------------------------------------------------ film

  void _film(Canvas canvas, Rect b) {
    final u = b.height; // one body height
    final r = Radius.circular(u * 0.09);
    final shape = RRect.fromRectAndRadius(b, r);
    // shell: the body's ends showing as a darker rim, with strap lugs
    canvas.drawRRect(shape.inflate(u * 0.015), Paint()..color = _shade(skin.shell, -0.2));
    for (final x in [b.left - u * 0.035, b.right + u * 0.005]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, b.top + u * 0.3, u * 0.03, u * 0.12),
          Radius.circular(u * 0.01),
        ),
        _metal(Rect.fromLTWH(x, b.top + u * 0.3, u * 0.03, u * 0.12), const Color(0xFFCFD1D4)),
      );
    }
    // leatherette
    canvas.drawRRect(shape, Paint()..color = skin.covering);
    final plateH = u * 0.26;
    final top = Rect.fromLTWH(b.left, b.top, b.width, plateH);
    final bottom = Rect.fromLTWH(b.left, b.bottom - u * 0.12, b.width, u * 0.12);
    final leather = Rect.fromLTRB(b.left, top.bottom, b.right, bottom.top);
    _pebbles(canvas, leather, skin.covering, u);
    // soft light across the leather
    canvas.drawRect(
      leather,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.07), Colors.black.withValues(alpha: 0.18)],
        ).createShader(leather),
    );
    // plates
    _plate(canvas, top, topCorners: r);
    _plate(canvas, bottom, bottomCorners: r);
    if (skin.id == 'brassed') _brassWear(canvas, top, bottom, u);
    // top deck: rewind knob, hot shoe, shutter dial, release, advance lever
    final deck = top.top;
    _knob(canvas, Rect.fromLTWH(b.left + b.width * 0.08, deck - u * 0.1, b.width * 0.12, u * 0.11));
    canvas.drawRect(
      Rect.fromLTWH(b.center.dx - u * 0.1, deck - u * 0.04, u * 0.2, u * 0.04),
      _metal(Rect.fromLTWH(b.center.dx - u * 0.1, deck - u * 0.04, u * 0.2, u * 0.04), skin.trim),
    );
    _knob(canvas, Rect.fromLTWH(b.left + b.width * 0.66, deck - u * 0.12, b.width * 0.14, u * 0.13));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(b.left + b.width * 0.83, deck - u * 0.07, u * 0.09, u * 0.07),
        Radius.circular(u * 0.02),
      ),
      _metal(
        Rect.fromLTWH(b.left + b.width * 0.83, deck - u * 0.07, u * 0.09, u * 0.07),
        const Color(0xFFDADCDF),
      ),
    );
    // windows: viewfinder (bright frame), rangefinder spot, frame-line window
    _window(
      canvas,
      Rect.fromLTWH(b.left + b.width * 0.07, top.top + plateH * 0.22, b.width * 0.18, plateH * 0.5),
      u,
    );
    _window(
      canvas,
      Rect.fromLTWH(b.left + b.width * 0.78, top.top + plateH * 0.26, b.width * 0.1, plateH * 0.42),
      u,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(b.left + b.width * 0.31, top.top + plateH * 0.3, b.width * 0.11, plateH * 0.36),
        Radius.circular(u * 0.01),
      ),
      Paint()..color = const Color(0xFFE8E2D2).withValues(alpha: 0.9),
    );
    // name plate in ink that reads on the plate
    _label(
      canvas,
      'DARKROOM',
      Offset(b.left + b.width * 0.6, top.top + plateH * 0.52),
      plateH * 0.3,
      _inkOn(skin.trim),
    );
    // self-timer lever beside the lens
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(b.left + b.width * 0.18, leather.top + leather.height * 0.18, u * 0.06, u * 0.14),
        Radius.circular(u * 0.02),
      ),
      _metal(
        Rect.fromLTWH(b.left + b.width * 0.18, leather.top, u * 0.06, u * 0.14),
        const Color(0xFFCFD1D4),
      ),
    );
    _lens(canvas, Offset(b.center.dx, leather.center.dy + u * 0.02), u * 0.36, focusScale: true);
  }

  void _plate(
    Canvas canvas,
    Rect plate, {
    Radius topCorners = Radius.zero,
    Radius bottomCorners = Radius.zero,
  }) {
    final shape = RRect.fromRectAndCorners(
      plate,
      topLeft: topCorners,
      topRight: topCorners,
      bottomLeft: bottomCorners,
      bottomRight: bottomCorners,
    );
    canvas.drawRRect(shape, _metal(plate, skin.trim));
    // fine brushing
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;
    for (var y = plate.top + 1.5; y < plate.bottom - 1; y += 1.6) {
      canvas.drawLine(Offset(plate.left + 2, y), Offset(plate.right - 2, y), line);
    }
    // an engraved edge where it meets the leather
    final edgeY = topCorners != Radius.zero ? plate.bottom - 0.6 : plate.top + 0.6;
    canvas.drawLine(
      Offset(plate.left, edgeY),
      Offset(plate.right, edgeY),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..strokeWidth = 1,
    );
  }

  void _brassWear(Canvas canvas, Rect top, Rect bottom, double u) {
    final brass = Paint()..color = const Color(0xFFB8913F);
    final rnd = math.Random(7);
    for (final plate in [top, bottom]) {
      final y = plate == top ? plate.bottom - u * 0.025 : plate.top;
      var x = plate.left + u * 0.05;
      while (x < plate.right - u * 0.05) {
        final len = u * (0.05 + rnd.nextDouble() * 0.12);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, len, u * 0.025), Radius.circular(u * 0.01)),
          brass,
        );
        x += len + u * (0.04 + rnd.nextDouble() * 0.14);
      }
    }
    // the corners, worn round
    for (final c in [top.topLeft, top.topRight]) {
      canvas.drawCircle(c + Offset(c.dx < top.center.dx ? u * 0.05 : -u * 0.05, u * 0.04), u * 0.035, brass);
    }
  }

  void _knob(Canvas canvas, Rect r) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(r.height * 0.2)),
      _metal(r, const Color(0xFFD5D7DA)),
    );
    // knurling
    final tick = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 0.6;
    for (var x = r.left + 1.5; x < r.right - 1; x += math.max(1.4, r.width / 14)) {
      canvas.drawLine(Offset(x, r.top + 1), Offset(x, r.bottom - 1), tick);
    }
  }

  void _window(Canvas canvas, Rect r, double u) {
    final frame = RRect.fromRectAndRadius(r.inflate(u * 0.012), Radius.circular(u * 0.02));
    canvas.drawRRect(frame, Paint()..color = const Color(0xFF2A2B2E));
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(u * 0.015)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B6C80), Color(0xFF1A2230), Color(0xFF2E3C52)],
          stops: [0, 0.55, 1],
        ).createShader(r),
    );
    canvas.drawLine(
      r.topLeft + Offset(r.width * 0.15, r.height * 0.75),
      r.topLeft + Offset(r.width * 0.55, r.height * 0.2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = math.max(0.8, u * 0.012),
    );
  }

  // --------------------------------------------------------------- digital

  void _digital(Canvas canvas, Rect b) {
    final u = b.height;
    final r = Radius.circular(u * 0.16);
    final shape = RRect.fromRectAndRadius(b, r);
    canvas.drawRRect(shape.inflate(u * 0.015), Paint()..color = _shade(skin.shell, -0.15));
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_shade(skin.covering, 0.22), skin.covering, _shade(skin.covering, -0.22)],
          stops: const [0, 0.45, 1],
        ).createShader(b),
    );
    // brushing
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.6;
    for (var y = b.top + 3; y < b.bottom - 2; y += 2) {
      canvas.drawLine(Offset(b.left + 4, y), Offset(b.right - 4, y), line);
    }
    // trim: a grip on the left, or a band across the top
    if (skin.id == 'grip') {
      final grip = Rect.fromLTWH(b.left, b.top, b.width * 0.2, b.height);
      canvas.drawRRect(RRect.fromRectAndCorners(grip, topLeft: r, bottomLeft: r), Paint()..color = skin.trim);
      _pebbles(canvas, grip.deflate(2), skin.trim, u);
    } else {
      final band = Rect.fromLTWH(b.left, b.top, b.width, u * 0.17);
      canvas.drawRRect(RRect.fromRectAndCorners(band, topLeft: r, topRight: r), _metal(band, skin.trim));
    }
    // top: shutter button and power button
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(b.left + b.width * 0.12, b.top - u * 0.06, u * 0.2, u * 0.07),
        Radius.circular(u * 0.03),
      ),
      _metal(
        Rect.fromLTWH(b.left + b.width * 0.12, b.top - u * 0.06, u * 0.2, u * 0.07),
        const Color(0xFFE0E2E5),
      ),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(b.left + b.width * 0.34, b.top - u * 0.035, u * 0.1, u * 0.04),
        Radius.circular(u * 0.02),
      ),
      Paint()..color = const Color(0xFF2A2C30),
    );
    // flash, AF lamp, viewfinder window
    final flash = Rect.fromLTWH(b.left + b.width * 0.27, b.top + u * 0.26, b.width * 0.17, u * 0.14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(flash.inflate(1), Radius.circular(u * 0.02)),
      Paint()..color = const Color(0xFF3A3C40),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(flash, Radius.circular(u * 0.02)),
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFFF8F6EE), Color(0xFFCFCAB8)]).createShader(flash),
    );
    for (var i = 1; i < 5; i++) {
      final x = flash.left + flash.width * i / 5;
      canvas.drawLine(
        Offset(x, flash.top + 1),
        Offset(x, flash.bottom - 1),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.12)
          ..strokeWidth = 0.6,
      );
    }
    canvas.drawCircle(
      Offset(b.left + b.width * 0.5, b.top + u * 0.33),
      u * 0.035,
      Paint()..color = const Color(0xFFD4892E),
    );
    _window(canvas, Rect.fromLTWH(b.left + b.width * 0.08, b.top + u * 0.27, b.width * 0.12, u * 0.12), u);
    // label, in ink that reads on the front
    // label between the grip (if any) and the lens, in ink that reads on the front
    final from = b.left + b.width * (skin.id == 'grip' ? 0.23 : 0.06);
    final to = b.left + b.width * 0.72 - u * 0.44;
    final mid = (from + to) / 2;
    _label(
      canvas,
      'DARKROOM',
      Offset(mid, b.bottom - u * 0.2),
      u * 0.11,
      _inkOn(skin.covering),
      fit: to - from,
    );
    _label(
      canvas,
      '3x ZOOM',
      Offset(mid, b.bottom - u * 0.09),
      u * 0.07,
      _inkOn(skin.covering).withValues(alpha: 0.7),
      fit: to - from,
    );
    // the lens barrel: a stepped ring out to the glass
    final c = Offset(b.left + b.width * 0.72, b.center.dy + u * 0.03);
    canvas.drawCircle(
      c,
      u * 0.4,
      _metal(Rect.fromCircle(center: c, radius: u * 0.4), _shade(skin.covering, -0.08)),
    );
    canvas.drawCircle(
      c,
      u * 0.4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.3),
    );
    _lens(canvas, c, u * 0.31);
  }

  // ---------------------------------------------------------------- shared

  void _lens(Canvas canvas, Offset c, double radius, {bool focusScale = false}) {
    // outer barrel
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xFF8E9298),
            Color(0xFFEDEEF0),
            Color(0xFF6E7278),
            Color(0xFFD9DBDE),
            Color(0xFF8E9298),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: radius)),
    );
    if (focusScale) {
      // focus ring ridges and the scale's ticks
      final ridge = Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..strokeWidth = 0.7;
      for (var i = 0; i < 48; i++) {
        final a = i / 48 * math.pi * 2;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(c + d * radius * 0.9, c + d * radius * 0.99, ridge);
      }
    }
    canvas.drawCircle(c, radius * 0.86, Paint()..color = const Color(0xFF17181A));
    // the name ring
    canvas.drawCircle(
      c,
      radius * 0.78,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, radius * 0.03)
        ..color = Colors.white.withValues(alpha: 0.18),
    );
    // glass: deep blue-violet coating, a green rim, two highlights
    final glass = Rect.fromCircle(center: c, radius: radius * 0.66);
    canvas.drawCircle(
      c,
      radius * 0.66,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.3),
          colors: [Color(0xFF4A3F78), Color(0xFF14182A), Color(0xFF0A0C12), Color(0xFF1F4A3A)],
          stops: [0, 0.45, 0.85, 1],
        ).createShader(glass),
    );
    canvas.drawCircle(c, radius * 0.26, Paint()..color = const Color(0xFF07080B));
    canvas.drawCircle(
      c + Offset(-radius * 0.25, -radius * 0.25),
      radius * 0.13,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      c + Offset(radius * 0.22, radius * 0.2),
      radius * 0.05,
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );
  }

  void _pebbles(Canvas canvas, Rect area, Color base, double u) {
    if (area.isEmpty) return;
    final light = Paint()..color = _shade(base, 0.14).withValues(alpha: 0.6);
    final dark = Paint()..color = _shade(base, -0.3).withValues(alpha: 0.5);
    final rnd = math.Random(area.width.round() * 31 + area.height.round());
    final step = math.max(1.6, u * 0.035);
    final r = step * 0.42;
    for (var y = area.top + step / 2; y < area.bottom; y += step) {
      for (var x = area.left + step / 2; x < area.right; x += step) {
        final p = Offset(
          x + (rnd.nextDouble() - 0.5) * step * 0.6,
          y + (rnd.nextDouble() - 0.5) * step * 0.6,
        );
        canvas.drawCircle(p + Offset(r * 0.25, r * 0.25), r, dark);
        canvas.drawCircle(p, r * 0.8, light);
      }
    }
  }

  void _label(Canvas canvas, String text, Offset centre, double size, Color color, {double? fit}) {
    var tp = _labelPainter(text, size, color);
    if (fit != null && tp.width > fit) {
      size *= fit / tp.width;
      tp = _labelPainter(text, size, color);
    }
    if (size < 3.5) return;
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  static TextPainter _labelPainter(String text, double size, Color color) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontFamily: 'Roboto',
          fontSize: size,
          fontWeight: FontWeight.w900,
          letterSpacing: size * 0.22,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// A metal surface of [base]: lit from above, a bright band, darker
  /// toward the bottom.
  static Paint _metal(Rect r, Color base) => Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_shade(base, 0.3), base, _shade(base, 0.12), _shade(base, -0.28)],
      stops: const [0, 0.4, 0.55, 1],
    ).createShader(r);

  /// Ink that reads on [background]: near-black on light, cream on dark.
  static Color _inkOn(Color background) =>
      background.computeLuminance() > 0.3 ? const Color(0xFF151515) : const Color(0xFFF2EEE4);

  static Color _shade(Color c, double amount) =>
      amount >= 0 ? Color.lerp(c, Colors.white, amount)! : Color.lerp(c, Colors.black, -amount)!;

  @override
  bool shouldRepaint(SkinCameraPainter old) => old.skin != skin || old.dim != dim;
}
