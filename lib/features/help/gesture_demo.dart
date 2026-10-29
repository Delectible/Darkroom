import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app's main moves, shown on a little phone: a fingertip does the
/// gesture and the screen answers, on a loop. Drawn, not video, so it costs
/// nothing to ship and keeps the app's colours.
enum GestureMove {
  pickFilm('Swipe up', 'Pick a film or camera'),
  corkboard('Swipe right', 'Your prints, on the corkboard'),
  computer('Swipe left', 'Your digital shots, on the computer'),
  swap('Drag the camera', 'Swap film and digital'),
  shutter('Volume button', 'Takes the picture'),
  print('Tap a print', 'Look closer, save or share');

  const GestureMove(this.title, this.caption);

  final String title;
  final String caption;
}

class GestureDemo extends StatefulWidget {
  const GestureDemo({super.key, required this.move, this.size = 96, this.t});

  final GestureMove move;

  /// The phone's width (it's 2:1 tall).
  final double size;

  /// A fixed moment of the loop (0..1) instead of playing; for tests.
  final double? t;

  static const period = Duration(milliseconds: 2600);

  @override
  State<GestureDemo> createState() => _GestureDemoState();
}

class _GestureDemoState extends State<GestureDemo> with SingleTickerProviderStateMixin {
  late final _loop = AnimationController(vsync: this, duration: GestureDemo.period);

  @override
  void initState() {
    super.initState();
    if (widget.t == null) _loop.repeat();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _loop,
        builder: (context, _) => CustomPaint(
          size: Size(widget.size, widget.size * 2),
          painter: _DemoPainter(widget.move, widget.t ?? _loop.value),
        ),
      ),
    );
  }
}

// The colours of the app's world.
const _phone = Color(0xFF15151A);
const _screen = Color(0xFF0E0E12);
const _filmBody = Color(0xFF2A2522);
const _digitalBody = Color(0xFFC9CCD2);
const _accent = Color(0xFFF05A47);
const _cork = Color(0xFFB98C5E);
const _beige = Color(0xFFDCD5C4);
const _teal = Color(0xFF2E7D7A);
const _paper = Color(0xFFF2EDE2);

double _ease(double t) => t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

class _DemoPainter extends CustomPainter {
  _DemoPainter(this.move, this.t);

  final GestureMove move;
  final double t;

  // The loop: finger lands (0-0.15), moves (0.15-0.55), lifts (0.55-0.65),
  // the result holds (to 0.85), everything settles back (to 1).
  double get _press => (t / 0.15).clamp(0.0, 1.0);
  double get _move => _ease(((t - 0.15) / 0.4).clamp(0.0, 1.0));
  double get _lift => ((t - 0.55) / 0.1).clamp(0.0, 1.0);
  double get _back => _ease(((t - 0.85) / 0.15).clamp(0.0, 1.0));

  /// How far the screen's answer has got (0..1, and back at the end).
  double get _progress => _move * (1 - _back);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // the phone
    final body = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(w * 0.16));
    canvas.drawRRect(body, Paint()..color = _phone);
    final scr = Rect.fromLTWH(w * 0.06, w * 0.06, w * 0.88, h - w * 0.12);
    final screen = RRect.fromRectAndRadius(scr, Radius.circular(w * 0.11));
    canvas.save();
    canvas.clipRRect(screen);
    canvas.drawRect(scr, Paint()..color = _screen);
    switch (move) {
      case GestureMove.pickFilm:
        _camera(canvas, scr, film: true);
        _carousel(canvas, scr, _progress);
      case GestureMove.corkboard:
        _camera(canvas, scr, film: true);
        _corkboard(canvas, scr, _progress);
      case GestureMove.computer:
        _camera(canvas, scr, film: false);
        _monitor(canvas, scr, _progress);
      case GestureMove.swap:
        _swap(canvas, scr, _progress);
      case GestureMove.shutter:
        _camera(canvas, scr, film: true, flash: _flash);
      case GestureMove.print:
        _printZoom(canvas, scr, _progress);
    }
    canvas.restore();
    // the side buttons; the volume key presses in for the shutter
    final key = Paint()..color = const Color(0xFF2C2C33);
    final pressed = move == GestureMove.shutter ? _keyPress : 0.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w - 1 - w * 0.03 * (1 - pressed), h * 0.24, w * 0.05, h * 0.12),
        Radius.circular(w * 0.02),
      ),
      key,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w - 1, h * 0.4, w * 0.04, h * 0.08), Radius.circular(w * 0.02)),
      key,
    );
    _finger(canvas, scr, size);
  }

  double get _keyPress => math.sin(math.pi * ((t - 0.2) / 0.25).clamp(0.0, 1.0));
  double get _flash => (1 - ((t - 0.32) / 0.25).abs() * 4).clamp(0.0, 1.0);

  /// A camera body filling the screen: viewfinder, shutter, a strip of
  /// controls.
  void _camera(
    Canvas canvas,
    Rect s, {
    required bool film,
    double flash = 0,
    double dx = 0,
    double tilt = 0,
  }) {
    canvas.save();
    canvas.translate(dx, 0);
    if (tilt != 0) {
      canvas.translate(s.center.dx, s.center.dy);
      canvas.transform(
        (Matrix4.identity()
              ..setEntry(3, 0, -tilt * 0.004)
              ..scaleByDouble(1 - tilt.abs() * 0.12, 1 - tilt.abs() * 0.12, 1, 1))
            .storage,
      );
      canvas.translate(-s.center.dx, -s.center.dy);
    }
    final bodyCol = film ? _filmBody : _digitalBody;
    canvas.drawRect(s, Paint()..color = bodyCol);
    final vf = Rect.fromLTWH(s.left + s.width * 0.1, s.top + s.height * 0.14, s.width * 0.8, s.height * 0.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(vf, Radius.circular(s.width * 0.04)),
      Paint()..color = const Color(0xFF101014),
    );
    // a little scene in the viewfinder: sky, sun, hills
    canvas.save();
    canvas.clipRect(vf.deflate(2));
    canvas.drawRect(
      vf,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5B6E96), Color(0xFFE7A27A)],
        ).createShader(vf),
    );
    canvas.drawCircle(
      Offset(vf.left + vf.width * 0.66, vf.top + vf.height * 0.55),
      vf.width * 0.1,
      Paint()..color = const Color(0xFFFFD9A0),
    );
    final hills = Path()..moveTo(vf.left, vf.bottom);
    for (var i = 0; i <= 12; i++) {
      final x = vf.left + vf.width * i / 12;
      hills.lineTo(x, vf.top + vf.height * (0.7 + 0.08 * math.sin(i * 1.3)));
    }
    hills
      ..lineTo(vf.right, vf.bottom)
      ..close();
    canvas.drawPath(hills, Paint()..color = const Color(0xFF3F4E3A));
    if (flash > 0) canvas.drawRect(vf, Paint()..color = Colors.white.withValues(alpha: flash * 0.9));
    canvas.restore();
    // the shutter and two controls under the viewfinder
    final cy = s.top + s.height * 0.82;
    canvas.drawCircle(
      Offset(s.center.dx, cy),
      s.width * 0.12,
      Paint()..color = film ? const Color(0xFFD7D9DD) : _accent,
    );
    canvas.drawCircle(
      Offset(s.center.dx, cy),
      s.width * 0.08,
      Paint()..color = film ? const Color(0xFFB9BCC2) : const Color(0xFFC7463A),
    );
    for (final x in [0.2, 0.8]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(s.left + s.width * x, cy),
            width: s.width * 0.18,
            height: s.width * 0.12,
          ),
          Radius.circular(s.width * 0.03),
        ),
        Paint()..color = film ? const Color(0xFF45403B) : const Color(0xFFA5A9B1),
      );
    }
    canvas.restore();
  }

  /// The film picker rising from the bottom: three canisters.
  void _carousel(Canvas canvas, Rect s, double p) {
    final top = s.bottom - s.height * 0.62 * p;
    final sheet = Rect.fromLTRB(s.left, top, s.right, s.bottom);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        sheet,
        topLeft: Radius.circular(s.width * 0.08),
        topRight: Radius.circular(s.width * 0.08),
      ),
      Paint()..color = const Color(0xFF1C1B20),
    );
    for (final (i, col) in [(0, const Color(0xFFE0B14E)), (1, _paper), (2, const Color(0xFFD94B3B))]) {
      final cx = s.left + s.width * (0.22 + i * 0.28);
      final c = Rect.fromCenter(
        center: Offset(cx, top + s.height * 0.22),
        width: s.width * 0.2,
        height: s.height * 0.16,
      );
      final scale = i == 1 ? 1.15 : 0.9;
      canvas.save();
      canvas.translate(c.center.dx, c.center.dy);
      canvas.scale(scale);
      canvas.translate(-c.center.dx, -c.center.dy);
      canvas.drawRRect(RRect.fromRectAndRadius(c, Radius.circular(s.width * 0.03)), Paint()..color = col);
      canvas.drawRect(
        Rect.fromLTWH(c.left, c.top + c.height * 0.55, c.width, c.height * 0.2),
        Paint()..color = const Color(0x55000000),
      );
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(c.center.dx, c.top - s.width * 0.02),
          width: c.width * 0.3,
          height: s.width * 0.05,
        ),
        Paint()..color = const Color(0xFF2B2B2B),
      );
      canvas.restore();
    }
  }

  /// The corkboard sliding in from the left in its wooden frame, prints pinned.
  void _corkboard(Canvas canvas, Rect s, double p) {
    final x = s.left - s.width + s.width * p;
    final b = Rect.fromLTWH(x, s.top, s.width, s.height);
    canvas.drawRect(b, Paint()..color = const Color(0xFF6B4527));
    final inner = b.deflate(s.width * 0.05);
    canvas.drawRect(inner, Paint()..color = _cork);
    final r = math.Random(4);
    for (var i = 0; i < 4; i++) {
      final col = i % 2, row = i ~/ 2;
      final pr = Rect.fromLTWH(
        inner.left + inner.width * (0.1 + col * 0.46),
        inner.top + inner.height * (0.08 + row * 0.42),
        inner.width * 0.36,
        inner.height * 0.32,
      );
      canvas.save();
      canvas.translate(pr.center.dx, pr.center.dy);
      canvas.rotate((r.nextDouble() - 0.5) * 0.18);
      canvas.translate(-pr.center.dx, -pr.center.dy);
      canvas.drawRect(pr, Paint()..color = _paper);
      canvas.drawRect(
        pr.deflate(pr.width * 0.08),
        Paint()
          ..color = [
            const Color(0xFF6F86A8),
            const Color(0xFFD99A6C),
            const Color(0xFF7C9A6A),
            const Color(0xFF9A7BA8),
          ][i],
      );
      canvas.drawCircle(
        Offset(pr.center.dx, pr.top + pr.height * 0.06),
        s.width * 0.025,
        Paint()
          ..color = [_accent, const Color(0xFF3A7BD5), const Color(0xFF3DAA5C), const Color(0xFFE5B93A)][i],
      );
      canvas.restore();
    }
  }

  /// The beige monitor sliding in from the right, a desktop window on it.
  void _monitor(Canvas canvas, Rect s, double p) {
    final x = s.right - s.width * p;
    final m = Rect.fromLTWH(x, s.top, s.width, s.height);
    canvas.drawRect(m, Paint()..color = _beige);
    final glass = Rect.fromLTRB(
      m.left + s.width * 0.06,
      m.top + s.width * 0.08,
      m.right - s.width * 0.06,
      m.bottom - s.width * 0.14,
    );
    canvas.drawRect(glass, Paint()..color = _teal);
    final win = Rect.fromLTRB(
      glass.left + 3,
      glass.top + 3,
      glass.right - 3,
      glass.bottom - glass.height * 0.1,
    );
    canvas.drawRect(win, Paint()..color = const Color(0xFFC0C0C0));
    canvas.drawRect(
      Rect.fromLTWH(win.left, win.top, win.width, win.height * 0.07),
      Paint()..color = const Color(0xFF000080),
    );
    for (var i = 0; i < 6; i++) {
      final ix = win.left + win.width * (0.12 + (i % 3) * 0.3),
          iy = win.top + win.height * (0.2 + (i ~/ 3) * 0.3);
      canvas.drawRect(
        Rect.fromLTWH(ix, iy, win.width * 0.18, win.width * 0.14),
        Paint()..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromLTWH(ix + 2, iy + 2, win.width * 0.18 - 4, win.width * 0.14 - 4),
        Paint()..color = [const Color(0xFF6F86A8), const Color(0xFF7C9A6A), const Color(0xFFD99A6C)][i % 3],
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(glass.left, glass.bottom - glass.height * 0.08, glass.width, glass.height * 0.08),
      Paint()..color = const Color(0xFFC0C0C0),
    );
  }

  /// One body tossed aside as the other comes in.
  void _swap(Canvas canvas, Rect s, double p) {
    _camera(canvas, s, film: true, dx: -s.width * 1.1 * p, tilt: p);
    if (p > 0) _camera(canvas, s, film: false, dx: s.width * 1.1 * (1 - p), tilt: -(1 - p));
  }

  /// A print on the board growing to fill the screen.
  void _printZoom(Canvas canvas, Rect s, double p) {
    canvas.drawRect(s, Paint()..color = _cork);
    final small = Rect.fromCenter(
      center: Offset(s.center.dx, s.top + s.height * 0.42),
      width: s.width * 0.5,
      height: s.width * 0.6,
    );
    final big = Rect.fromCenter(center: s.center, width: s.width * 0.92, height: s.width * 1.1);
    final r = Rect.lerp(small, big, p)!;
    if (p > 0) canvas.drawRect(s, Paint()..color = Colors.black.withValues(alpha: 0.55 * p));
    canvas.drawRect(r.shift(const Offset(2, 3)), Paint()..color = const Color(0x55000000));
    canvas.drawRect(r, Paint()..color = _paper);
    canvas.drawRect(
      r.deflate(r.width * 0.07),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5B6E96), Color(0xFFE7A27A)],
        ).createShader(r),
    );
    canvas.drawCircle(
      Offset(r.left + r.width * 0.5, r.top + r.width * 0.07),
      s.width * 0.03 * (1 - p),
      Paint()..color = _accent,
    );
    // Save / Share appear under it once it's open
    if (p > 0.6) {
      final a = ((p - 0.6) / 0.4).clamp(0.0, 1.0);
      for (final x in [0.3, 0.5, 0.7]) {
        canvas.drawCircle(
          Offset(s.left + s.width * x, s.bottom - s.height * 0.08),
          s.width * 0.07,
          Paint()..color = Colors.white.withValues(alpha: 0.25 * a),
        );
      }
    }
  }

  /// The fingertip: a soft round touch with a ring as it presses, and a
  /// fading trail along the way it went.
  void _finger(Canvas canvas, Rect s, Size size) {
    Offset at(double p) {
      final (Offset a, Offset b) = switch (move) {
        GestureMove.pickFilm => (
          Offset(s.center.dx, s.top + s.height * 0.9),
          Offset(s.center.dx, s.top + s.height * 0.45),
        ),
        GestureMove.corkboard => (
          Offset(s.left + s.width * 0.15, s.center.dy),
          Offset(s.left + s.width * 0.85, s.center.dy),
        ),
        GestureMove.computer => (
          Offset(s.left + s.width * 0.85, s.center.dy),
          Offset(s.left + s.width * 0.15, s.center.dy),
        ),
        GestureMove.swap => (
          Offset(s.left + s.width * 0.75, s.top + s.height * 0.4),
          Offset(s.left + s.width * 0.05, s.top + s.height * 0.44),
        ),
        GestureMove.shutter => (
          Offset(size.width + size.width * 0.18, size.height * 0.3),
          Offset(size.width + size.width * 0.06, size.height * 0.3),
        ),
        GestureMove.print => (
          Offset(s.center.dx, s.top + s.height * 0.45),
          Offset(s.center.dx, s.top + s.height * 0.45),
        ),
      };
      return Offset.lerp(a, b, p)!;
    }

    final shown = (_press * (1 - _lift)).clamp(0.0, 1.0);
    if (shown <= 0) return;
    final p = move == GestureMove.shutter
        ? _ease(((t - 0.15) / 0.12).clamp(0.0, 1.0)) * (1 - _ease(((t - 0.42) / 0.12).clamp(0.0, 1.0)))
        : _move;
    final pos = at(p);
    final r = size.width * 0.11;
    // the trail
    if (move != GestureMove.shutter && move != GestureMove.print && p > 0.02) {
      final trail = Path()..moveTo(at(0).dx, at(0).dy);
      for (var i = 1; i <= 20; i++) {
        final q = at(p * i / 20);
        trail.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(
        trail,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * 0.9
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.35 * shown),
            ],
          ).createShader(Rect.fromPoints(at(0), pos).inflate(1)),
      );
    }
    // the touch ring as it presses, then the fingertip
    final ring =
        (1 - _press) + (move == GestureMove.print ? math.max(0, 1 - ((t - 0.35) / 0.15).abs() * 3) : 0);
    if (ring > 0) {
      canvas.drawCircle(
        pos,
        r * (1.2 + ring * 0.8),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.5 * ring.clamp(0.0, 1.0) * shown),
      );
    }
    canvas.drawCircle(pos, r, Paint()..color = Colors.white.withValues(alpha: 0.85 * shown));
    canvas.drawCircle(
      pos,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.black.withValues(alpha: 0.25 * shown),
    );
  }

  @override
  bool shouldRepaint(_DemoPainter old) => old.t != t || old.move != move;
}

/// A demo with its title and one line under it.
class GestureCard extends StatelessWidget {
  const GestureCard({
    super.key,
    required this.move,
    this.size = 72,
    this.ink = Colors.white,
    this.muted = Colors.white70,
    this.t,
  });

  final GestureMove move;
  final double size;
  final Color ink, muted;

  /// Fixes the loop at this moment (tests).
  final double? t;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDemo(move: move, size: size, t: t),
        const SizedBox(height: 8),
        Text(
          move.title,
          textAlign: TextAlign.center,
          style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 2),
        Text(
          move.caption,
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12, height: 1.25),
        ),
      ],
    );
  }
}
