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

/// The tail end of a developed reel, left hanging so you can hold it to the
/// light: a short Super 8 strip (one perforation per frame on the edge) with
/// the clip's opening frames on it.
class FilmTail extends StatelessWidget {
  const FilmTail({super.key, required this.frame, this.frames = 3});

  /// The picture on each frame (consecutive frames barely differ).
  final Widget frame;
  final int frames;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        // Super 8: 4.0 x 5.8 mm frame (landscape, portrait strip), wide edge
        // with the perforations.
        final edge = w * 0.2, picW = w - edge - w * 0.06, picH = picW * 4.0 / 5.8;
        final pitch = picH * 1.08;
        return SizedBox(
          width: w,
          height: pitch * frames + pitch * 0.4,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              // Developed reversal film: dense, slightly warm black between frames.
              color: Color(0xFF16100C),
              boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(2, 3))],
            ),
            child: Stack(
              children: [
                for (var i = 0; i < frames; i++) ...[
                  Positioned(
                    left: edge,
                    top: pitch * 0.2 + i * pitch,
                    width: picW,
                    height: picH,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(picW * 0.06),
                      child: ColorFiltered(
                        // Seen against the cork, not a lightbox: a touch dim and warm.
                        colorFilter: const ColorFilter.matrix([
                          0.92, 0, 0, 0, 6, //
                          0, 0.86, 0, 0, 2, //
                          0, 0, 0.78, 0, 0, //
                          0, 0, 0, 1, 0,
                        ]),
                        child: frame,
                      ),
                    ),
                  ),
                  Positioned(
                    left: edge * 0.32,
                    top: pitch * 0.2 + i * pitch + picH * 0.38,
                    width: edge * 0.38,
                    height: picH * 0.24,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFB9A88F),
                        borderRadius: BorderRadius.circular(edge * 0.08),
                      ),
                    ),
                  ),
                ],
                // Cut end: slightly ragged.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: pitch * 0.12,
                  child: const ColoredBox(color: Color(0x33FFFFFF)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A Super 8 reel developing in a daylight tank: the reel turns slowly in
/// the chemistry, and the stage changes as the clock runs down.
class DevelopingTankPainter extends CustomPainter {
  DevelopingTankPainter({required this.progress, required this.spin});

  /// 0..1 through development.
  final double progress;

  /// Agitation rotation (radians).
  final double spin;

  static const stages = ['DEV', 'BLEACH', 'FIX', 'WASH'];
  static const _liquids = [Color(0xFF2B3A1E), Color(0xFF5A2E14), Color(0xFF3B3B44), Color(0xFF1C3A4A)];

  static String stageFor(double p) => stages[(p * stages.length).floor().clamp(0, stages.length - 1)];

  /// The same stages in full, for the close-up.
  static const names = ['Developing', 'Bleaching', 'Fixing', 'Washing'];

  static String nameFor(double p) => names[(p * names.length).floor().clamp(0, names.length - 1)];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;
    final stage = (progress * stages.length).floor().clamp(0, stages.length - 1);
    // Tank body (black plastic) and its rim.
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0E0E0E));
    canvas.drawCircle(
      c,
      r * 0.97,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..color = const Color(0xFF3A3A3A),
    );
    // Chemistry for the current stage, with a slow swirl.
    final liquid = Rect.fromCircle(center: c, radius: r * 0.86);
    canvas.drawCircle(
      c,
      r * 0.86,
      Paint()
        ..shader = SweepGradient(
          transform: GradientRotation(spin * 0.6),
          colors: [_liquids[stage], Color.lerp(_liquids[stage], Colors.white, 0.18)!, _liquids[stage]],
        ).createShader(liquid),
    );
    // The spiral reel inside, turning with the agitation.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(spin);
    final spiral = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r * 0.035)
      ..color = const Color(0x99D8D8D8);
    final path = Path()..moveTo(r * 0.18, 0);
    for (var a = 0.0; a < math.pi * 8; a += 0.15) {
      final rr = r * (0.18 + 0.6 * a / (math.pi * 8));
      path.lineTo(math.cos(a) * rr, math.sin(a) * rr);
    }
    canvas.drawPath(path, spiral);
    canvas.drawCircle(Offset.zero, r * 0.15, Paint()..color = const Color(0xFF9EA3A8));
    canvas.drawCircle(Offset.zero, r * 0.06, Paint()..color = const Color(0xFF111111));
    canvas.restore();
    // Progress around the rim.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.97),
      -math.pi / 2,
      progress.clamp(0.0, 1.0) * math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFF6E40),
    );
  }

  @override
  bool shouldRepaint(DevelopingTankPainter old) => old.progress != progress || old.spin != spin;
}
