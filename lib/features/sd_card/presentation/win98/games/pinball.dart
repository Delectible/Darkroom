import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../../core/audio/sfx.dart';
import '../pixel_icons.dart';
import '../win98_widgets.dart';
import '../../../../../core/device/haptics.dart';

/// PINBALL.EXE: "Space Rabbit", a small space table in the spirit of the
/// one that came with the machine: a mission panel with your rank, three
/// attack bumpers, slingshots above the flippers, in- and outlanes, a bank
/// of FUEL targets, a wormhole, and R-A-B-B-I-T rollovers. Finish missions
/// to be promoted from Cadet to Admiral.
///
/// Hold the left or right half of the table for that flipper. With the ball
/// in the launch lane, hold anywhere to pull the plunger; let go to fire.
Future<void> showPinball(BuildContext context) => showWin98Window<void>(
  context,
  title: '3D Pinball for Darkroom - Space Rabbit',
  width: 300,
  icon: const PixelIconView(PixelIcon.rabbit),
  builder: (context) => Padding(
    padding: const EdgeInsets.all(6),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PinballGame(),
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
const _tableW = 280.0, _tableH = 440.0;
const _r = 5.0; // ball radius
const _gravity = 560.0;
const _lane = Offset(258, 428); // ball resting on the plunger

class _Seg {
  const _Seg(this.a, this.b, {this.kick = 0, this.thick = 1.5});
  final Offset a, b;

  /// Slingshot rubber: pushes the ball off this hard (px/s).
  final double kick;
  final double thick;
}

class _Bumper {
  _Bumper(this.c, this.radius);
  final Offset c;
  final double radius;
  double flash = 0;
}

class _Target {
  _Target(this.a, this.b);
  final Offset a, b;
  bool down = false;
}

class _Flipper {
  _Flipper(this.pivot, this.length, {required this.rest, required this.up});
  final Offset pivot;
  final double length;
  final double rest, up;
  double angle = 0;
  double omega = 0;
  bool held = false;

  Offset get tip => pivot + Offset(math.cos(angle), math.sin(angle)) * length;
}

class _Mission {
  const _Mission(this.name, this.goal, this.kind);
  final String name;
  final int goal;
  final String kind; // bumper, fuel, rabbit, warp
}

class PinballGame extends StatefulWidget {
  const PinballGame({super.key});

  @override
  State<PinballGame> createState() => _PinballGameState();
}

class _PinballGameState extends State<PinballGame> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _clock = 0;

  static List<_Seg> _poly(List<Offset> pts, {double kick = 0}) => [
    for (var i = 0; i < pts.length - 1; i++) _Seg(pts[i], pts[i + 1], kick: kick),
  ];

  // Outer shell, the launch lane, the inlane guides (outlanes outside them)
  // and the two slingshots.
  static final _walls = <_Seg>[
    ..._poly(const [
      Offset(12, 450),
      Offset(12, 110),
      Offset(24, 64),
      Offset(52, 30),
      Offset(96, 10),
      Offset(140, 5),
      Offset(186, 10),
      Offset(228, 28),
      Offset(254, 54),
      Offset(268, 90),
      Offset(268, 450),
    ]),
    const _Seg(Offset(248, 150), Offset(248, 450)),
    ..._poly(const [Offset(36, 318), Offset(36, 370), Offset(88, 404)]),
    ..._poly(const [Offset(224, 318), Offset(224, 370), Offset(172, 404)]),
    // Slingshots: the inner face is live rubber.
    const _Seg(Offset(52, 300), Offset(52, 352)),
    const _Seg(Offset(52, 352), Offset(80, 372)),
    const _Seg(Offset(52, 300), Offset(80, 372), kick: 300, thick: 2.5),
    const _Seg(Offset(208, 300), Offset(208, 352)),
    const _Seg(Offset(208, 352), Offset(180, 372)),
    const _Seg(Offset(208, 300), Offset(180, 372), kick: 300, thick: 2.5),
  ];

  static const _slings = [
    [Offset(52, 300), Offset(52, 352), Offset(80, 372)],
    [Offset(208, 300), Offset(208, 352), Offset(180, 372)],
  ];

  final _bumpers = [
    _Bumper(const Offset(98, 136), 16),
    _Bumper(const Offset(162, 128), 16),
    _Bumper(const Offset(130, 186), 17),
  ];

  final _fuel = [
    _Target(const Offset(214, 214), const Offset(214, 230)),
    _Target(const Offset(214, 236), const Offset(214, 252)),
    _Target(const Offset(214, 258), const Offset(214, 274)),
  ];
  double _fuelReset = 0;

  static const _hole = Offset(62, 250), _holeOut = Offset(196, 92);
  double _captured = 0; // seconds left inside the wormhole

  late final _left = _Flipper(const Offset(90, 406), 33, rest: 0.55, up: -0.42);
  late final _right = _Flipper(const Offset(170, 406), 33, rest: math.pi - 0.55, up: math.pi + 0.42);

  static const _letters = ['R', 'A', 'B', 'B', 'I', 'T'];
  final _lit = List<bool>.filled(6, false);
  static Offset _letterPos(int i) => Offset(70 + i * 25.0, 46);

  static const _ranks = ['Cadet', 'Ensign', 'Lieutenant', 'Captain', 'Commander', 'Admiral'];
  static const _missions = [
    _Mission('Launch training: hit 5 bumpers', 5, 'bumper'),
    _Mission('Refuel: knock down the 3 FUEL targets', 1, 'fuel'),
    _Mission('Spell R-A-B-B-I-T', 1, 'rabbit'),
    _Mission('Jump the wormhole twice', 2, 'warp'),
    _Mission('Bumper storm: hit 15 bumpers', 15, 'bumper'),
    _Mission('Refuel twice', 2, 'fuel'),
  ];
  int _rank = 0;
  int _mission = 0;
  int _progress = 0;

  Offset _ball = _lane;
  Offset _vel = Offset.zero;
  bool _inLane = true;
  double _pull = 0;
  bool _pulling = false;
  int _balls = 3;
  int _score = 0;
  String? _flash; // a message over the mission line for a moment
  double _flashFor = 0;
  bool _over = false;

  final Map<int, bool> _touches = {}; // pointer -> left half?

  @override
  void initState() {
    super.initState();
    _left.angle = _left.rest;
    _right.angle = _right.rest;
    Sfx.pinStart.play();
    for (final s in [Sfx.pinFlipper, Sfx.pinBumper, Sfx.pinChime, Sfx.pinSling, Sfx.pinDrop]) {
      unawaited(s.preload());
    }
    _say('Hold to pull the plunger');
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _say(String text, [double seconds = 2.5]) {
    _flash = text;
    _flashFor = seconds;
  }

  void _newBall() {
    _ball = _lane;
    _vel = Offset.zero;
    _inLane = true;
    _pull = 0;
  }

  void _newGame() {
    _balls = 3;
    _score = 0;
    _rank = 0;
    _mission = 0;
    _progress = 0;
    _over = false;
    _lit.fillRange(0, 6, false);
    for (final t in _fuel) {
      t.down = false;
    }
    _newBall();
    Sfx.pinStart.play();
    _say('Hold to pull the plunger');
  }

  void _progressOn(String kind, [int by = 1]) {
    final m = _missions[_mission % _missions.length];
    if (m.kind != kind) return;
    _progress += by;
    if (_progress < m.goal) return;
    _score += 5000 * (_rank + 1);
    _rank = math.min(_ranks.length - 1, _rank + 1);
    _mission++;
    _progress = 0;
    Sfx.gameWin.play();
    unawaited(Haptics.mediumImpact());
    _say('Mission complete! Promoted to ${_ranks[_rank]}', 3);
  }

  // ---- input -----------------------------------------------------------------

  void _down(PointerDownEvent e, Size size) {
    if (_over) {
      setState(_newGame);
      return;
    }
    if (_inLane && _vel == Offset.zero) {
      _pulling = true;
      return;
    }
    _touches[e.pointer] = e.localPosition.dx < size.width / 2;
    _setFlippers();
  }

  void _up(PointerEvent e) {
    if (_pulling && _inLane) {
      _pulling = false;
      _vel = Offset(0, -(680 + 340 * _pull));
      _pull = 0;
      Sfx.pinLaunch.play();
    }
    _touches.remove(e.pointer);
    _setFlippers();
  }

  void _setFlippers() {
    final l = _touches.values.any((v) => v), r = _touches.values.any((v) => !v);
    if (l && !_left.held || r && !_right.held) Sfx.pinFlipper.play();
    _left.held = l;
    _right.held = r;
  }

  // ---- physics ---------------------------------------------------------------

  void _tick(Duration now) {
    final dt = math.min(0.033, (now - _last).inMicroseconds / 1e6);
    _last = now;
    _clock += dt;
    if (_pulling) _pull = math.min(1, _pull + dt * 1.3);
    if (_flashFor > 0) _flashFor -= dt;
    for (final b in _bumpers) {
      b.flash = math.max(0, b.flash - dt * 4);
    }
    if (_fuelReset > 0) {
      _fuelReset -= dt;
      if (_fuelReset <= 0) {
        for (final t in _fuel) {
          t.down = false;
        }
      }
    }
    if (_captured > 0) {
      _captured -= dt;
      if (_captured <= 0) {
        _ball = _holeOut;
        _vel = const Offset(-170, 140);
      }
    } else if (!_over) {
      const steps = 6;
      for (var i = 0; i < steps; i++) {
        _step(dt / steps);
      }
    }
    setState(() {});
  }

  void _moveFlipper(_Flipper f, double h) {
    final target = f.held ? f.up : f.rest;
    const speed = 24.0;
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
      _ball = _lane + Offset(0, 10 * _pull);
      return;
    }
    var v = _vel + const Offset(0, _gravity) * h;
    var p = _ball + v * h;

    bool collide(
      Offset a,
      Offset b,
      double thick, {
      Offset Function(Offset at)? surface,
      double e = 0.5,
      double kick = 0,
    }) {
      final ab = b - a;
      final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / ab.distanceSquared).clamp(0.0, 1.0);
      final q = a + ab * t;
      final d = p - q;
      final dist = d.distance;
      if (dist >= _r + thick || dist == 0) return false;
      final n = d / dist;
      p = q + n * (_r + thick);
      final vs = surface?.call(q) ?? Offset.zero;
      var rel = v - vs;
      final vn = rel.dx * n.dx + rel.dy * n.dy;
      if (vn < 0) {
        rel = rel - n * ((1 + e) * vn);
        v = rel + vs + n * kick;
        return true;
      }
      return false;
    }

    for (final s in _walls) {
      if (collide(s.a, s.b, s.thick, kick: s.kick) && s.kick > 0) {
        _score += 50;
        Sfx.pinSling.play();
      }
    }
    for (final t in _fuel) {
      if (!t.down && collide(t.a, t.b, 2)) {
        t.down = true;
        _score += 500;
        Sfx.pinDrop.play();
        if (_fuel.every((t) => t.down)) {
          _score += 2500;
          _fuelReset = 2;
          Sfx.pinChime.play();
          _say('Fuel tanks full!');
          _progressOn('fuel');
        }
      }
    }
    for (final f in [_left, _right]) {
      collide(
        f.pivot,
        f.tip,
        3.5,
        e: 0.3,
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
        v = v - n * vn + n * math.max(340, -vn * 1.1);
        b.flash = 1;
        _score += 100;
        Sfx.pinBumper.play();
        _progressOn('bumper');
      }
    }
    for (var i = 0; i < 6; i++) {
      if (!_lit[i] && (p - _letterPos(i)).distance < 9) {
        _lit[i] = true;
        _score += 250;
        Sfx.pinChime.play();
        if (_lit.every((l) => l)) {
          _score += 5000;
          _lit.fillRange(0, 6, false);
          _say('R-A-B-B-I-T! +5000');
          unawaited(Haptics.mediumImpact());
          _progressOn('rabbit');
        }
      }
    }
    // The wormhole swallows a ball that isn't going too fast.
    if ((p - _hole).distance < 8 && v.distance < 750) {
      _captured = 1.0;
      _ball = const Offset(-50, -50);
      _vel = Offset.zero;
      _score += 1000;
      Sfx.pinWarp.play();
      _say('Wormhole! +1000');
      _progressOn('warp');
      return;
    }
    if (_inLane && p.dx < 248) _inLane = false;
    if (!_inLane && p.dx > 250 && p.dy > 300) _inLane = true;
    if (_inLane && p.dy >= _lane.dy && v.dy > 0) {
      p = _lane;
      v = Offset.zero;
    }
    final speed = v.distance;
    if (speed > 1000) v = v / speed * 1000;
    _ball = p;
    _vel = v;
    if (p.dy > _tableH + 20) {
      _balls--;
      Sfx.pinDrain.play();
      if (_balls > 0) {
        _say('$_balls balls left', 2);
        _newBall();
      } else {
        _over = true;
        _ball = const Offset(-50, -50);
        _vel = Offset.zero;
        _say('Game over: $_score. Tap to play again', 999);
      }
    }
  }

  // ---- drawing ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final m = _missions[_mission % _missions.length];
    final mission = _flashFor > 0 && _flash != null ? _flash! : '${m.name}  ($_progress/${m.goal})';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The mission panel, like the right-hand board of the original.
        Win98Bevel(
          style: BevelStyle.sunken,
          child: Container(
            color: const Color(0xFF00102A),
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
            child: DefaultTextStyle(
              style: W98.text.copyWith(color: const Color(0xFF7FE7FF), fontSize: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '$_score'.padLeft(8, '0'),
                        style: W98.text.copyWith(
                          color: const Color(0xFFFFD23F),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text('BALL ${math.max(0, 4 - _balls).clamp(1, 3)}'),
                    ],
                  ),
                  Text('Rank: ${_ranks[_rank]}'),
                  Text(
                    mission,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFFF9E5E)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Win98Bevel(
          style: BevelStyle.sunken,
          child: AspectRatio(
            aspectRatio: _tableW / _tableH,
            child: LayoutBuilder(
              builder: (context, box) {
                final size = box.biggest;
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _down(e, size),
                  onPointerUp: _up,
                  onPointerCancel: _up,
                  child: CustomPaint(size: size, painter: _TablePainter(this)),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TablePainter extends CustomPainter {
  _TablePainter(this.g);

  final _PinballGameState g;
  static final _stars = List.generate(90, (i) {
    final r = math.Random(i * 7 + 1);
    return (Offset(r.nextDouble() * _tableW, r.nextDouble() * _tableH), r.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _tableW, size.height / _tableH);
    const table = Rect.fromLTWH(0, 0, _tableW, _tableH);
    canvas.clipRect(table);
    canvas.drawRect(
      table,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF050A2A), Color(0xFF120A33), Color(0xFF04040F)],
        ).createShader(table),
    );
    // Nebulae and a ringed planet.
    for (final (c, r, col) in [
      (const Offset(70, 120), 90.0, const Color(0x332D6BFF)),
      (const Offset(200, 300), 110.0, const Color(0x33B23BFF)),
      (const Offset(120, 380), 80.0, const Color(0x2200D4FF)),
    ]) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [col, col.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
    for (final (s, b) in _stars) {
      canvas.drawCircle(s, 0.5 + b * 0.6, Paint()..color = Colors.white.withValues(alpha: 0.3 + 0.6 * b));
    }
    const planet = Offset(186, 330);
    canvas.drawCircle(
      planet,
      26,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.4),
          colors: [Color(0xFFE6A15C), Color(0xFF7A3B1E), Color(0xFF2A1208)],
        ).createShader(Rect.fromCircle(center: planet, radius: 26)),
    );
    canvas.save();
    canvas.translate(planet.dx, planet.dy);
    canvas.rotate(-0.35);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 80, height: 16),
      Paint()
        ..color = const Color(0x88E8C48A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.restore();

    // Glowing guides.
    final glow = Paint()
      ..color = const Color(0x664FA8FF)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final wall = Paint()
      ..color = const Color(0xFFA8CCFF)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    for (final s in _PinballGameState._walls) {
      if (s.kick > 0) continue;
      canvas.drawLine(s.a, s.b, glow);
      canvas.drawLine(s.a, s.b, wall);
    }
    // Slingshots: filled plastic with a lit rubber face.
    for (final tri in _PinballGameState._slings) {
      final path = Path()..addPolygon(tri, true);
      canvas.drawPath(path, Paint()..color = const Color(0xCC1E3A8A));
      canvas.drawLine(
        tri[0],
        tri[2],
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round,
      );
    }
    // Lane arrows on the inlanes.
    for (final x in [24.0, 236.0]) {
      final p = Path()
        ..moveTo(x - 5, 330)
        ..lineTo(x + 5, 330)
        ..lineTo(x, 340)
        ..close();
      canvas.drawPath(p, Paint()..color = const Color(0x99FFD23F));
    }
    // R-A-B-B-I-T rollovers.
    for (var i = 0; i < 6; i++) {
      final lit = g._lit[i];
      final c = _PinballGameState._letterPos(i);
      if (lit) {
        canvas.drawCircle(
          c,
          11,
          Paint()
            ..color = const Color(0x66FFD23F)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawCircle(c, 8, Paint()..color = lit ? const Color(0xFFFFD23F) : const Color(0x553A4A80));
      _text(canvas, _PinballGameState._letters[i], c, lit ? Colors.black : Colors.white60, 10);
    }
    // Attack bumpers.
    for (final b in g._bumpers) {
      final f = b.flash;
      canvas.drawCircle(
        b.c,
        b.radius + 4 * f,
        Paint()
          ..color = Color.lerp(const Color(0x00FF3B7A), const Color(0x88FF3B7A), f)!
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        b.c,
        b.radius,
        Paint()..color = Color.lerp(const Color(0xFFE0447A), Colors.white, f)!,
      );
      canvas.drawCircle(b.c, b.radius * 0.72, Paint()..color = const Color(0xFF3A0F2E));
      canvas.drawCircle(b.c, b.radius * 0.42, Paint()..color = const Color(0xFFFFB0CF));
    }
    // FUEL targets.
    for (var i = 0; i < g._fuel.length; i++) {
      final t = g._fuel[i];
      canvas.drawLine(
        t.a,
        t.b,
        Paint()
          ..color = t.down ? const Color(0x44FF8C1A) : const Color(0xFFFF8C1A)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
    _text(canvas, 'FUEL', const Offset(236, 244), const Color(0xAAFF8C1A), 8, vertical: true);
    // The wormhole, swirling.
    const hole = _PinballGameState._hole;
    canvas.drawCircle(hole, 13, Paint()..color = const Color(0xFF000000));
    final swirl = Paint()
      ..color = const Color(0xFFB07CFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var k = 0; k < 3; k++) {
      canvas.drawArc(
        Rect.fromCircle(center: hole, radius: 5.0 + k * 3),
        g._clock * 3 + k * 2.1,
        3.6,
        false,
        swirl,
      );
    }
    _text(canvas, 'WORMHOLE', hole + const Offset(0, 20), const Color(0xAAB07CFF), 7);
    // Plunger.
    canvas.drawRect(Rect.fromLTWH(252, 436 + 10 * g._pull, 12, 10), Paint()..color = const Color(0xFFC0C0C0));
    // Flippers: chrome with a red rubber edge.
    for (final f in [g._left, g._right]) {
      canvas.drawLine(
        f.pivot,
        f.tip,
        Paint()
          ..color = const Color(0xFFD02030)
          ..strokeWidth = 8.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        f.pivot,
        f.tip,
        Paint()
          ..color = const Color(0xFFE8ECF2)
          ..strokeWidth = 5.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(f.pivot, 2, Paint()..color = const Color(0xFF555A60));
    }
    // Ball.
    if (g._captured <= 0 && !g._over) {
      canvas.drawCircle(g._ball + const Offset(1.5, 2), _r, Paint()..color = Colors.black54);
      canvas.drawCircle(
        g._ball,
        _r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.4, -0.4),
            colors: [Colors.white, Color(0xFFB8BEC6), Color(0xFF4A4F55)],
          ).createShader(Rect.fromCircle(center: g._ball, radius: _r)),
      );
    }
    if (g._over) {
      _text(canvas, 'GAME OVER', const Offset(130, 250), const Color(0xFFFFD23F), 18);
      _text(canvas, 'tap to play again', const Offset(130, 272), Colors.white70, 10);
    } else if (g._inLane && g._vel == Offset.zero) {
      _text(canvas, 'HOLD TO PULL', const Offset(258, 404), Colors.white54, 6, vertical: true);
    }
  }

  void _text(Canvas canvas, String s, Offset c, Color color, double size, {bool vertical = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: W98.text.copyWith(color: color, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (vertical) canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TablePainter old) => true;
}
