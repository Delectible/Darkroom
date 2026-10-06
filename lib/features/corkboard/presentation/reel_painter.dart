import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small Super 8 projection reel: pressed-metal flange with three windows
/// showing the wound film, a hub, and a strip of label tape.
class ReelPainter extends CustomPainter {
  ReelPainter({
    required this.rotation,
    required this.label,
    required this.duration,
    this.saved = false,
    this.spin = 0,
  });

  final double rotation;
  final String label;
  final String duration;
  final bool saved;

  /// Extra rotation (radians) for the projector's turning reels.
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) * 0.46;

    // Soft shadow on the cork.
    final sh = Rect.fromCircle(center: c + Offset(r * 0.06, r * 0.1), radius: r * 1.08);
    canvas.drawCircle(
      sh.center,
      sh.width / 2,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x88000000), Color(0x00000000)],
          stops: [0.75, 1],
        ).createShader(sh),
    );

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rotation + spin);

    // Wound film seen through the windows.
    canvas.drawCircle(Offset.zero, r * 0.80, Paint()..color = const Color(0xFF2A1A12));
    final rings = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, r * 0.006)
      ..color = const Color(0x22FFFFFF);
    for (var k = 0.30; k < 0.80; k += 0.045) {
      canvas.drawCircle(Offset.zero, r * k, rings);
    }
    canvas.drawCircle(Offset.zero, r * 0.30, Paint()..color = const Color(0xFF151515));

    // Flange with three windows.
    final disc = Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r));
    var windows = Path();
    for (var i = 0; i < 3; i++) {
      final a0 = i * 2 * math.pi / 3 + 0.35, sweep = 1.25;
      final w = Path()
        ..arcTo(Rect.fromCircle(center: Offset.zero, radius: r * 0.84), a0, sweep, true)
        ..arcTo(Rect.fromCircle(center: Offset.zero, radius: r * 0.36), a0 + sweep, -sweep, false)
        ..close();
      windows = Path.combine(PathOperation.union, windows, w);
    }
    final flange = Path.combine(PathOperation.difference, disc, windows);
    final metal = Rect.fromCircle(center: Offset.zero, radius: r);
    canvas.drawPath(
      flange,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-1, -1),
          end: Alignment(1, 1),
          colors: [Color(0xFFE6E8EA), Color(0xFF9EA3A8), Color(0xFFD5D8DB), Color(0xFF7D8287)],
          stops: [0, 0.4, 0.62, 1],
        ).createShader(metal),
    );
    // Pressed ribs and rim.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r * 0.03);
    canvas.drawCircle(Offset.zero, r * 0.985, stroke..color = const Color(0x55000000));
    canvas.drawCircle(Offset.zero, r * 0.93, stroke..color = const Color(0x40FFFFFF));
    canvas.drawPath(
      windows,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, r * 0.025)
        ..color = const Color(0x66000000),
    );

    // Hub.
    canvas.drawCircle(
      Offset.zero,
      r * 0.22,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFF2F2F2), Color(0xFF8E9398)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 0.22)),
    );
    canvas.drawCircle(Offset.zero, r * 0.085, Paint()..color = const Color(0xFF111111));
    for (var i = 0; i < 3; i++) {
      final a = i * 2 * math.pi / 3;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(math.cos(a), math.sin(a)) * r * 0.1,
          width: r * 0.05,
          height: r * 0.05,
        ),
        Paint()..color = const Color(0xFF111111),
      );
    }
    canvas.restore();

    // Label tape (does not spin with the reel on the projector).
    if (label.isNotEmpty) {
      canvas.save();
      canvas.translate(c.dx, c.dy + r * 0.62);
      canvas.rotate(rotation * 0.3 - 0.05);
      final tape = Rect.fromCenter(center: Offset.zero, width: r * 1.15, height: r * 0.34);
      canvas.drawRect(tape.shift(const Offset(1.5, 2)), Paint()..color = const Color(0x33000000));
      canvas.drawRect(tape, Paint()..color = const Color(0xFFF6F0DC));
      final tp = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        text: TextSpan(
          children: [
            TextSpan(
              text: label,
              style: TextStyle(
                color: const Color(0xFF1F2A5A),
                fontSize: r * 0.15,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: '  $duration${saved ? '  ✓' : ''}',
              style: TextStyle(color: const Color(0xFF5B5B5B), fontSize: r * 0.12),
            ),
          ],
        ),
      )..layout(maxWidth: tape.width - 6);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ReelPainter old) =>
      old.rotation != rotation ||
      old.label != label ||
      old.saved != saved ||
      old.spin != spin ||
      old.duration != duration;
}
