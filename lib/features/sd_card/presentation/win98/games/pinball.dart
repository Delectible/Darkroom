import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../../core/audio/sfx.dart';
import '../pixel_icons.dart';
import '../win98_widgets.dart';

/// PINBALL.EXE: "Space Rabbit", a small space table. Hold the left or right
/// half of the table for that flipper; with the ball in the launch lane,
/// hold anywhere to pull the plunger and let go to fire. Light R-A-B-B-I-T
/// for a bonus. Three balls.
Future<void> showPinball(BuildContext context) => showWin98Window<void>(
  context,
  title: 'Space Rabbit Pinball',
  width: 300,
  icon: const PixelIconView(PixelIcon.rabbit),
  builder: (context) => Padding(
    padding: const EdgeInsets.all(6),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Win98Bevel(
          style: BevelStyle.sunken,
          child: AspectRatio(aspectRatio: _tableW / _tableH, child: PinballGame()),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Win98Button(
            minWidth: 76,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
      ],
    ),
  ),
);

// Table units (scaled to the widget).
const _tableW = 280.0, _tableH = 420.0;
const _r = 5.0; // ball radius
const _gravity = 540.0;

class _Seg {
  const _Seg(this.a, this.b);
  final Offset a, b;
}

class _Bumper {
  _Bumper(this.c, this.radius);
  final Offset c;
  final double radius;
  double flash = 0;
}

class _Flipper {
  _Flipper(this.pivot, this.length, {required this.rest, required this.up, required this.left});
  final Offset pivot;
  final double length;
  final double rest, up; // angles (radians, screen coordinates)
  final bool left;
  double angle = 0;
  double omega = 0; // angular velocity this step
  bool held = false;

  Offset get tip => pivot + Offset(math.cos(angle), math.sin(angle)) * length;
}

class PinballGame extends StatefulWidget {
  const PinballGame({super.key});

  @override
  State<PinballGame> createState() => _PinballGameState();
}

class _PinballGameState extends State<PinballGame> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  // Outer walls, the launch lane and the slopes down to the flippers.
  static final _walls = <_Seg>[
    ..._poly(const [
      Offset(14, 330),
      Offset(14, 90),
      Offset(30, 50),
      Offset(60, 24),
      Offset(100, 10),
      Offset(140, 6),
      Offset(185, 10),
      Offset(228, 26),
      Offset(256, 52),
      Offset(270, 90),
      Offset(270, 420),
    ]),
    const _Seg(Offset(250, 140), Offset(250, 420)), // launch lane, inner wall
    const _Seg(Offset(14, 330), Offset(92, 382)), // left slope to the flipper
    const _Seg(Offset(250, 330), Offset(188, 382)), // right slope
    // Little guides above the slopes (slingshot-ish).
    const _Seg(Offset(46, 300), Offset(70, 336)),
    const _Seg(Offset(218, 300), Offset(194, 336)),
  ];

  static List<_Seg> _poly(List<Offset> pts) => [
    for (var i = 0; i < pts.length - 1; i++) _Seg(pts[i], pts[i + 1]),
  ];

  final _bumpers = [
    _Bumper(const Offset(90, 140), 16),
    _Bumper(const Offset(168, 130), 16),
    _Bumper(const Offset(128, 200), 17),
  ];

  late final _left = _Flipper(const Offset(92, 384), 42, rest: 0.52, up: -0.42, left: true);
  late final _right = _Flipper(
    const Offset(188, 384),
    42,
    rest: math.pi - 0.52,
    up: math.pi + 0.42,
    left: false,
  );

  // R-A-B-B-I-T rollovers across the top.
  static const _letters = ['R', 'A', 'B', 'B', 'I', 'T'];
  final _lit = List<bool>.filled(6, false);
  static Offset _letterPos(int i) => Offset(66 + i * 30.0, 58);

  Offset _ball = const Offset(260, 400);
  Offset _vel = Offset.zero;
  bool _inLane = true;
  double _pull = 0; // plunger, 0..1
  bool _pulling = false;
  int _balls = 3;
  int _score = 0;
  String? _banner = 'Hold to pull the plunger';

  // Touches: which halves are held (several fingers at once).
  final Map<int, bool> _touches = {}; // pointer -> isLeft

  @override
  void initState() {
    super.initState();
    _left.angle = _left.rest;
    _right.angle = _right.rest;
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _newBall() {
    _ball = const Offset(260, 400);
    _vel = Offset.zero;
    _inLane = true;
    _pull = 0;
  }

  void _down(PointerDownEvent e, Size size) {
    if (_balls <= 0) {
      setState(() {
        _balls = 3;
        _score = 0;
        _lit.fillRange(0, 6, false);
        _newBall();
        _banner = 'Hold to pull the plunger';
      });
      return;
    }
    if (_inLane) {
      if (_vel == Offset.zero) _pulling = true;
      return;
    }
    final isLeft = e.localPosition.dx < size.width / 2;
    _touches[e.pointer] = isLeft;
    _setFlippers();
  }

  void _up(PointerEvent e) {
    if (_pulling && _inLane) {
      _pulling = false;
      // Fire: a stronger pull, a faster ball.
      // Even a light pull clears the lane; a full one rattles round the top.
      _vel = Offset(0, -(660 + 340 * _pull));
      _pull = 0;
      _banner = null;
      Sfx.w98Click.play();
    }
    _touches.remove(e.pointer);
    _setFlippers();
  }

  void _setFlippers() {
    final l = _touches.values.any((v) => v), r = _touches.values.any((v) => !v);
    if (l && !_left.held || r && !_right.held) Sfx.keyDown.play();
    _left.held = l;
    _right.held = r;
  }

  void _tick(Duration now) {
    final dt = math.min(0.033, (now - _last).inMicroseconds / 1e6);
    _last = now;
    if (_pulling) _pull = math.min(1, _pull + dt * 1.2);
    for (final b in _bumpers) {
      b.flash = math.max(0, b.flash - dt * 4);
    }
    const steps = 6;
    for (var i = 0; i < steps; i++) {
      _step(dt / steps);
    }
    setState(() {});
  }

  void _moveFlipper(_Flipper f, double h) {
    final target = f.held ? f.up : f.rest;
    const speed = 22.0; // rad/s
    final before = f.angle;
    final d = target - f.angle;
    final stepMax = speed * h;
    f.angle += d.clamp(-stepMax, stepMax);
    f.omega = (f.angle - before) / h;
  }

  void _step(double h) {
    _moveFlipper(_left, h);
    _moveFlipper(_right, h);
    if (_inLane && _vel == Offset.zero) {
      _ball = Offset(260, 400 + 12 * _pull);
      return;
    }
    var v = _vel + const Offset(0, _gravity) * h;
    var p = _ball + v * h;

    void collideSeg(
      Offset a,
      Offset b,
      double thick, {
      Offset Function(Offset at)? surface,
      double e = 0.55,
    }) {
      final ab = b - a;
      final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / ab.distanceSquared).clamp(0.0, 1.0);
      final q = a + ab * t;
      final d = p - q;
      final dist = d.distance;
      if (dist >= _r + thick || dist == 0) return;
      final n = d / dist;
      p = q + n * (_r + thick);
      final vs = surface?.call(q) ?? Offset.zero;
      var rel = v - vs;
      final vn = rel.dx * n.dx + rel.dy * n.dy;
      if (vn < 0) {
        rel = rel - n * ((1 + e) * vn);
        v = rel + vs;
      }
    }

    for (final s in _walls) {
      collideSeg(s.a, s.b, 1.5);
    }
    for (final f in [_left, _right]) {
      collideSeg(
        f.pivot,
        f.tip,
        3.5,
        e: 0.35,
        // A point on a turning flipper moves at omega x r.
        surface: (at) {
          final r = at - f.pivot;
          return Offset(-r.dy, r.dx) * f.omega;
        },
      );
    }
    for (final b in _bumpers) {
      final d = p - b.c;
      final dist = d.distance;
      if (dist < b.radius + _r && dist > 0) {
        final n = d / dist;
        p = b.c + n * (b.radius + _r);
        final vn = v.dx * n.dx + v.dy * n.dy;
        // Bumpers kick: always send the ball away fast.
        v = v - n * vn + n * math.max(320, -vn * 1.1);
        b.flash = 1;
        _score += 100;
        Sfx.w98Click.play();
      }
    }
    for (var i = 0; i < 6; i++) {
      if (!_lit[i] && (p - _letterPos(i)).distance < 9) {
        _lit[i] = true;
        _score += 250;
        if (_lit.every((l) => l)) {
          _score += 5000;
          _lit.fillRange(0, 6, false);
          Sfx.w98Ding.play();
          unawaited(HapticFeedback.mediumImpact());
        }
      }
    }
    // Leaving the lane at the top; falling back into it re-arms the plunger.
    if (_inLane && p.dx < 250) _inLane = false;
    if (!_inLane && p.dx > 252 && p.dy > 300) _inLane = true;
    if (_inLane && p.dy >= 400 && v.dy > 0) {
      p = const Offset(260, 400);
      v = Offset.zero;
    }
    final speed = v.distance;
    if (speed > 950) v = v / speed * 950;
    _ball = p;
    _vel = v;
    if (p.dy > _tableH + 20) {
      _balls--;
      Sfx.w98Ding.play();
      if (_balls > 0) {
        _banner = '$_balls ball${_balls == 1 ? '' : 's'} left';
        _newBall();
      } else {
        _banner = 'Game over: $_score. Tap to play again';
        _ball = const Offset(-50, -50);
        _vel = Offset.zero;
        _inLane = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _down(e, size),
          onPointerUp: _up,
          onPointerCancel: _up,
          child: CustomPaint(
            size: size,
            painter: _TablePainter(this),
            child: _banner == null
                ? null
                : Align(
                    alignment: const Alignment(0, 0.15),
                    child: Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(_banner!, style: W98.text.copyWith(color: Colors.white)),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _TablePainter extends CustomPainter {
  _TablePainter(this.g);

  final _PinballGameState g;
  static final _stars = List.generate(60, (i) {
    final r = math.Random(i * 7 + 1);
    return Offset(r.nextDouble() * _tableW, r.nextDouble() * _tableH);
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _tableW, size.height / _tableH);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _tableW, _tableH),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1033), Color(0xFF1B0F3A), Color(0xFF07071A)],
        ).createShader(const Rect.fromLTWH(0, 0, _tableW, _tableH)),
    );
    final star = Paint()..color = Colors.white70;
    for (final s in _stars) {
      canvas.drawCircle(s, 0.7, star);
    }
    // A big faint planet.
    canvas.drawCircle(const Offset(200, 250), 46, Paint()..color = const Color(0x22FF8C1A));
    final wall = Paint()
      ..color = const Color(0xFF8FB8FF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final s in _PinballGameState._walls) {
      canvas.drawLine(s.a, s.b, wall);
    }
    // Rollover letters.
    for (var i = 0; i < 6; i++) {
      final lit = g._lit[i];
      final c = _PinballGameState._letterPos(i);
      canvas.drawCircle(c, 8, Paint()..color = lit ? const Color(0xFFFFD23F) : const Color(0x553A4A80));
      final tp = TextPainter(
        text: TextSpan(
          text: _PinballGameState._letters[i],
          style: W98.text.copyWith(color: lit ? Colors.black : Colors.white60, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
    for (final b in g._bumpers) {
      final glow = b.flash;
      canvas.drawCircle(
        b.c,
        b.radius + 3 * glow,
        Paint()..color = Color.lerp(const Color(0xFFE0447A), Colors.white, glow)!,
      );
      canvas.drawCircle(b.c, b.radius * 0.6, Paint()..color = const Color(0xFF2A0E2E));
    }
    // Plunger.
    final pull = g._pull;
    canvas.drawRect(Rect.fromLTWH(254, 407 + 12 * pull, 12, 13), Paint()..color = const Color(0xFFC0C0C0));
    // Flippers.
    final flip = Paint()
      ..color = const Color(0xFFFFD23F)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    for (final f in [g._left, g._right]) {
      canvas.drawLine(f.pivot, f.tip, flip);
    }
    // Ball.
    canvas.drawCircle(
      g._ball,
      _r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0xFF8A8A8A)],
        ).createShader(Rect.fromCircle(center: g._ball - const Offset(1.5, 1.5), radius: _r * 1.4)),
    );
    // Score.
    final tp = TextPainter(
      text: TextSpan(
        text: '${g._score}'.padLeft(7, '0'),
        style: W98.text.copyWith(color: const Color(0xFFFF8C1A), fontSize: 14, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(_tableW / 2 - tp.width / 2, 22));
    final balls = TextPainter(
      text: TextSpan(
        text: 'BALL',
        style: W98.text.copyWith(color: Colors.white70, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    balls.paint(canvas, const Offset(20, 400));
    for (var i = 0; i < g._balls; i++) {
      canvas.drawCircle(
        Offset(20 + balls.width + 8 + i * 9, 400 + balls.height / 2),
        3,
        Paint()..color = Colors.white70,
      );
    }
  }

  @override
  bool shouldRepaint(_TablePainter old) => true;
}
