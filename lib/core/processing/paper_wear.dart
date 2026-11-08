import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// What a real print's paper does that a drawn rectangle doesn't: corners a
/// touch round, edges not quite straight, the sheet bowed so the light
/// falls off across it, and (handled) worn corners, a thumbprint, a little
/// yellowing. Each print keeps its own ([seed]); [level] 0 is the drawn
/// rectangle, 1 a new print, 2 one that's been about (in between: on its
/// way).
class PaperWear {
  const PaperWear({required this.seed, this.level = 1});

  /// A print's paper by its age: fresh from the darkroom (1), handled
  /// after [agesIn] (2).
  factory PaperWear.of(String id, DateTime developed, {DateTime? now}) {
    final days = (now ?? DateTime.now()).difference(developed).inHours / 24;
    return PaperWear(seed: id.hashCode, level: 1 + (days / agesIn.inDays).clamp(0.0, 1.0));
  }

  static const agesIn = Duration(days: 21);

  final int seed;
  final double level;

  bool get on => level > 0;

  /// How handled, 0 (new) .. 1.
  double get _handled => (level - 1).clamp(0.0, 1.0);

  /// The same print's paper in steps a saved file can be kept by (remade
  /// only when the print has visibly aged).
  String get key => '${seed.toUnsigned(32)}_${(level * 4).round()}';

  /// The sheet's outline in [size]: rounded corners, the edges wandering a
  /// hair (a guillotine cut, not a ruler).
  ///
  /// [corner]: the print's own corner radius (a snapshot's round corners),
  /// as a fraction of its short side.
  Path outline(Size size, {double corner = 0}) {
    final w = size.width, h = size.height;
    final u = math.min(w, h);
    if (!on) {
      return Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * corner)));
    }
    final r = math.Random(seed);
    final amp = u * (0.0009 + 0.0007 * _handled);
    // corners: rounded, one wearing rounder as it's handled
    final worn = r.nextInt(4);
    final radii = [
      for (var i = 0; i < 4; i++)
        u * math.max(corner, 0.006 + r.nextDouble() * 0.003 + (i == worn ? 0.014 * _handled : 0)),
    ];
    double wave(double t, double p1, double p2) =>
        amp * (0.6 * math.sin(t * math.pi * 2 * 1.3 + p1) + 0.4 * math.sin(t * math.pi * 2 * 3.1 + p2));
    final ph = [for (var i = 0; i < 8; i++) r.nextDouble() * math.pi * 2];
    final p = Path();
    const n = 24;
    // each edge inset by its wave (never past the box), corner to corner
    p.moveTo(radii[0], wave(0, ph[0], ph[1]).abs());
    for (var i = 1; i <= n; i++) {
      final t = i / n;
      p.lineTo(radii[0] + (w - radii[0] - radii[1]) * t, wave(t, ph[0], ph[1]).abs());
    }
    p.arcToPoint(Offset(w, radii[1]), radius: Radius.circular(radii[1]));
    for (var i = 1; i <= n; i++) {
      final t = i / n;
      p.lineTo(w - wave(t, ph[2], ph[3]).abs(), radii[1] + (h - radii[1] - radii[2]) * t);
    }
    p.arcToPoint(Offset(w - radii[2], h), radius: Radius.circular(radii[2]));
    for (var i = 1; i <= n; i++) {
      final t = i / n;
      p.lineTo(w - radii[2] - (w - radii[2] - radii[3]) * t, h - wave(t, ph[4], ph[5]).abs());
    }
    p.arcToPoint(Offset(0, h - radii[3]), radius: Radius.circular(radii[3]));
    for (var i = 1; i <= n; i++) {
      final t = i / n;
      p.lineTo(wave(t, ph[6], ph[7]).abs(), h - radii[3] - (h - radii[3] - radii[0]) * t);
    }
    p.arcToPoint(Offset(radii[0], wave(0, ph[0], ph[1]).abs()), radius: Radius.circular(radii[0]));
    return p..close();
  }

  /// Over the whole sheet (clipped to [outline]): the light across the
  /// bowed paper, the cut edge, and the handling.
  void paintOver(Canvas canvas, Size size, {double corner = 0}) {
    if (!on) return;
    final rect = Offset.zero & size;
    final u = math.min(size.width, size.height);
    final r = math.Random(seed * 31 + 7);
    final h = _handled;
    // The bow: a sheet curls along one axis, its two edges a shade darker
    // than its middle; the light comes a little from one side.
    final across = r.nextBool();
    final bow = 0.045 + 0.03 * h;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: across ? Alignment.centerLeft : Alignment.topCenter,
          end: across ? Alignment.centerRight : Alignment.bottomCenter,
          colors: [
            Color.fromRGBO(0, 0, 0, bow),
            const Color(0x00000000),
            const Color(0x00000000),
            Color.fromRGBO(0, 0, 0, bow * 0.7),
          ],
          stops: const [0, 0.22, 0.7, 1],
        ).createShader(rect),
    );
    final lightFrom = Alignment(r.nextDouble() * 2 - 1, -1);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: lightFrom,
          end: -lightFrom,
          colors: const [Color(0x14FFFFFF), Color(0x00FFFFFF), Color(0x0A000000)],
        ).createShader(rect),
    );
    if (h > 0.02) {
      // a little yellowing, deepest at the edges
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.multiply
          ..shader = RadialGradient(
            radius: 0.85,
            colors: [
              const Color(0xFFFFFFFF),
              Color.lerp(const Color(0xFFFFFFFF), const Color(0xFFFFFCF5), h)!,
              Color.lerp(const Color(0xFFFFFFFF), const Color(0xFFF7EEDC), h)!,
            ],
            stops: const [0, 0.6, 1],
          ).createShader(rect),
      );
      // worn corners: the fibres show, lighter
      for (var i = 0; i < 2; i++) {
        final c = [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft][r.nextInt(4)];
        final rad = u * (0.03 + r.nextDouble() * 0.03);
        canvas.drawCircle(
          c,
          rad,
          Paint()
            ..shader = RadialGradient(
              colors: [Color.fromRGBO(255, 255, 255, 0.33 * h), const Color(0x00FFFFFF)],
            ).createShader(Rect.fromCircle(center: c, radius: rad)),
        );
      }
      // a thumbprint, where a print is held
      final at = Offset(size.width * (0.7 + r.nextDouble() * 0.2), size.height * (0.82 + r.nextDouble() * 0.12));
      final ridge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.0022
        ..color = Color.fromRGBO(0, 0, 0, 0.055 * h);
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(r.nextDouble() * math.pi);
      for (var k = 1; k <= 11; k++) {
        final rr = u * 0.0062 * k;
        canvas.drawArc(
          Rect.fromCenter(center: Offset.zero, width: rr * 1.5, height: rr * 2),
          -math.pi * (0.9 + r.nextDouble() * 0.2),
          math.pi * (1.4 + r.nextDouble() * 0.4),
          false,
          ridge,
        );
      }
      canvas.restore();
    }
    // the cut edge: a fine dark line, the light catching just inside it
    final edge = outline(size, corner: corner);
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, u * 0.0025)
        ..color = const Color(0x2A000000),
    );
    canvas.save();
    canvas.translate(0, math.max(0.5, u * 0.002));
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, u * 0.0015)
        ..color = const Color(0x22FFFFFF),
    );
    canvas.restore();
  }

  /// Over an instant print's picture [rect]: its corners a little round
  /// (the frame's mask), sunk a hair below the paper, and the developer's
  /// edge where the paste spread up from the strip and didn't quite reach
  /// the top evenly.
  void paintWindow(Canvas canvas, Rect rect, Color paper) {
    if (!on) return;
    final s = rect.width;
    final r = math.Random(seed * 17 + 3);
    // the developer's edge along the top: a pale, uneven sliver
    final depth = s * (0.009 + 0.009 * _handled);
    final creep = Path()..moveTo(rect.left, rect.top);
    const n = 30;
    final p1 = r.nextDouble() * 6, p2 = r.nextDouble() * 6;
    final bump = r.nextDouble();
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      var d = depth * (0.35 + 0.35 * math.sin(t * 7.3 + p1) * math.sin(t * 2.1 + p2) + 0.3);
      // one place where it fell well short
      d += depth * 1.4 * math.exp(-math.pow((t - bump) * 9, 2));
      creep.lineTo(rect.left + s * t, rect.top + d.clamp(0, depth * 2.4));
    }
    creep
      ..lineTo(rect.right, rect.top)
      ..close();
    canvas.drawPath(
      creep,
      Paint()
        ..color = Color.lerp(paper, const Color(0xFFBFD3D0), 0.35)!.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.4, s * 0.0015)),
    );
    // sunk below the paper: a soft shadow just inside the top and left
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, s, s * 0.02),
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.topLeft + Offset(0, s * 0.02), const [
          Color(0x2E000000),
          Color(0x00000000),
        ]),
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, s * 0.014, rect.height),
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.topLeft + Offset(s * 0.014, 0), const [
          Color(0x22000000),
          Color(0x00000000),
        ]),
    );
    // round inner corners: the paper's mask over the picture's corners
    final rad = s * 0.016;
    final fill = Paint()..color = paper;
    for (final (c, dx, dy) in [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomRight, -1.0, -1.0),
      (rect.bottomLeft, 1.0, -1.0),
    ]) {
      final corner = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + dx * rad, c.dy)
        ..arcToPoint(Offset(c.dx, c.dy + dy * rad), radius: Radius.circular(rad), clockwise: dx * dy < 0)
        ..close();
      canvas.drawPath(corner, fill);
    }
  }
}

/// Draws a whole print (by [content], into [size] at the canvas origin) as
/// [WornSheet] shows it, for a saved file: the sheet on a dark scanner bed.
void paintWornSheet(
  Canvas canvas,
  Size size,
  PaperWear wear,
  void Function(Canvas canvas) content, {
  Rect? window,
  Color paper = const Color(0xFFE9E8E4),
  double corner = 0,
}) {
  final rect = Offset.zero & size;
  canvas.drawRect(rect, Paint()..color = const Color(0xFF26231F));
  canvas.save();
  canvas.clipPath(wear.outline(size, corner: corner));
  content(canvas);
  if (window != null) wear.paintWindow(canvas, window, paper);
  wear.paintOver(canvas, size, corner: corner);
  canvas.restore();
}

/// [child] (a whole print) as a real sheet: cut to [PaperWear.outline], the
/// light and handling over it, its own shadow from that outline (lifted a
/// little more at one end: the curl). [window]: an instant print's picture
/// rect in a given size, for its mask and developer's edge, on [paper].
class WornSheet extends StatelessWidget {
  const WornSheet({
    super.key,
    required this.wear,
    required this.child,
    this.window,
    this.paper = const Color(0xFFE9E8E4),
    this.shadow = true,
    this.corner = 0,
  });

  final PaperWear wear;
  final Widget child;
  final Rect Function(Size size)? window;
  final Color paper;
  final bool shadow;

  /// The print's own corner radius (see [PaperWear.outline]).
  final double corner;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      final shape = wear.outline(size, corner: corner);
      return CustomPaint(
        painter: shadow ? _SheetShadow(shape, wear.seed) : null,
        child: ClipPath(
          clipper: _PathClip(shape),
          child: CustomPaint(
            foregroundPainter: _Over(wear, window?.call(size), paper, corner),
            child: child,
          ),
        ),
      );
    },
  );
}

class _PathClip extends CustomClipper<Path> {
  _PathClip(this.path);
  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_PathClip old) => old.path != path;
}

class _Over extends CustomPainter {
  _Over(this.wear, this.window, this.paper, this.corner);
  final PaperWear wear;
  final Rect? window;
  final Color paper;
  final double corner;

  @override
  void paint(Canvas canvas, Size size) {
    if (window case final w?) wear.paintWindow(canvas, w, paper);
    wear.paintOver(canvas, size, corner: corner);
  }

  @override
  bool shouldRepaint(_Over old) =>
      old.wear.seed != wear.seed ||
      old.wear.level != wear.level ||
      old.window != window ||
      old.paper != paper ||
      old.corner != corner;
}

class _SheetShadow extends CustomPainter {
  _SheetShadow(this.shape, this.seed);
  final Path shape;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final u = math.min(size.width, size.height);
    // One soft shadow from the sheet's own outline, falling a little
    // further at one end (the curl lifts it). One blur: a board holds many.
    final lift = math.Random(seed).nextBool();
    final m = Matrix4.identity()
      ..translateByDouble(u * 0.01, u * 0.02, 0, 1)
      ..scaleByDouble(1, lift ? 1.01 : 0.997, 1, 1);
    canvas.drawPath(
      shape.transform(m.storage),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(2, u * 0.02)),
    );
  }

  @override
  bool shouldRepaint(_SheetShadow old) => old.shape != shape;
}
