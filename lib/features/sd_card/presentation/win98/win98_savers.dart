import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/device/upright.dart';
import 'win98_monitor.dart';
import 'win98_display.dart';

/// Darkroom 98's screen savers (Tools > Options > Screen Saver): 3D Pipes,
/// Starfield and 3D Text, all drawn live (no assets). They start after
/// [Win98Display.saverWait] minutes without a touch ([Win98SaverWatch]) and
/// any touch puts them away.

/// Shows [saver] full screen on the monitor until the next touch.
Future<void> showScreenSaver(BuildContext context, Win98Display d) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    settings: UprightApp.landscape,
    transitionDuration: const Duration(milliseconds: 500),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    // The same bezel over the one below: only the screen fades.
    pageBuilder: (context, _, _) => UprightPage(child: ExplorerMonitor(child: _SaverScreen(d))),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ),
);

class _SaverScreen extends StatefulWidget {
  const _SaverScreen(this.d);

  final Win98Display d;

  @override
  State<_SaverScreen> createState() => _SaverScreenState();
}

class _SaverScreenState extends State<_SaverScreen> {
  bool _woken = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        if (_woken) return;
        _woken = true;
        Navigator.of(context).pop();
      },
      child: ScreenSaverView(saver: widget.d.saver, text: widget.d.saverText),
    );
  }
}

/// Starts the screen saver after the monitor has sat untouched for its
/// wait; wraps the explorer (lives as long as Darkroom 98 is open).
class Win98SaverWatch extends StatefulWidget {
  const Win98SaverWatch({super.key, required this.child});

  final Widget child;

  @override
  State<Win98SaverWatch> createState() => _Win98SaverWatchState();
}

class _Win98SaverWatchState extends State<Win98SaverWatch> {
  Timer? _timer;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    Win98Idle.listen();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  Future<void> _check() async {
    final d = Win98Display.current.value;
    if (_showing || !mounted || d.saver == Win98Saver.none) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    if (DateTime.now().difference(Win98Idle.last) < Duration(minutes: d.saverWait)) return;
    // Only over Darkroom 98's own screens (not the tour, not a share sheet).
    if (!UprightApp.observer.allowed.value) return;
    _showing = true;
    await showScreenSaver(context, d);
    _showing = false;
    Win98Idle.poke();
  }

  @override
  void dispose() {
    _timer?.cancel();
    Win98Idle.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One screen saver, running, filling its box (the monitor's screen or the
/// little preview in Options).
class ScreenSaverView extends StatefulWidget {
  const ScreenSaverView({super.key, required this.saver, this.text = 'Darkroom 98', this.seed});

  final Win98Saver saver;
  final String text;

  /// Fixed for tests; random otherwise.
  final int? seed;

  @override
  State<ScreenSaverView> createState() => _ScreenSaverViewState();
}

class _ScreenSaverViewState extends State<ScreenSaverView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  late math.Random _rng;
  late final _Pipes _pipes;
  late final _Stars _stars;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _rng = math.Random(widget.seed);
    _pipes = _Pipes(_rng);
    _stars = _Stars(_rng);
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final dt = math.min(0.1, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    switch (widget.saver) {
      case Win98Saver.pipes:
        _pipes.advance(dt);
      case Win98Saver.stars:
        _stars.advance(dt);
      case Win98Saver.text || Win98Saver.none:
        break;
    }
    _time.value = elapsed.inMicroseconds / 1e6;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: ClipRect(
        child: switch (widget.saver) {
          Win98Saver.pipes => CustomPaint(painter: _PipesPainter(_pipes, _time), size: Size.infinite),
          Win98Saver.stars => CustomPaint(painter: _StarsPainter(_stars, _time), size: Size.infinite),
          Win98Saver.text => _Text3d(text: widget.text, time: _time),
          Win98Saver.none => const SizedBox.expand(),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3D Pipes: three pipes at a time racing through a box of space, each its
// own colour, turning at random with a ball joint at every bend, crossing
// in front of and behind each other; when one gets boxed in another starts
// somewhere free; once the screen is busy it fades and starts again.
// ---------------------------------------------------------------------------

class _V3 {
  const _V3(this.x, this.y, this.z);

  final int x, y, z;

  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);

  @override
  bool operator ==(Object o) => o is _V3 && o.x == x && o.y == y && o.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);
}

class _Seg {
  _Seg(this.a, this.b, this.colour);

  final _V3 a, b;
  final Color colour;
}

class _Pipe {
  _Pipe(this.at, this.colour);

  _V3 at;
  _V3? dir;
  final Color colour;
  _Seg? tip;
  bool alive = true;
}

class _Pipes {
  _Pipes(this.rng) {
    _reset();
  }

  final math.Random rng;
  /// The box of space, cells across, up and deep: shaped like the screen.
  int nx = 16, ny = 12, nz = 12;
  static const lanes = 3, perScreen = 21, steps = 18.0;
  static const _dirs = [
    _V3(1, 0, 0),
    _V3(-1, 0, 0),
    _V3(0, 1, 0),
    _V3(0, -1, 0),
    _V3(0, 0, 1),
    _V3(0, 0, -1),
  ];
  static const _colours = [
    Color(0xFFD8261C),
    Color(0xFF1E64E0),
    Color(0xFF22B22E),
    Color(0xFFF0C21A),
    Color(0xFFC02CD0),
    Color(0xFF1CC8C8),
    Color(0xFFF07818),
    Color(0xFFD8D8D8),
  ];

  final segs = <_Seg>[];
  final joints = <(_V3, Color)>[];
  final pipes = <_Pipe>[];
  final _used = <_V3>{};
  int _started = 0;
  int _colour = 0;

  /// 0..1 along the step every live pipe is taking now.
  double grow = 0;

  /// Fading out before starting over (1 -> 0).
  double fade = 1;
  bool _clearing = false;

  /// Shapes the box like a [size] screen (starts over if that changes it).
  void fit(Size size) {
    final tall = size.height > size.width * 1.2, wide = size.width > size.height * 1.2;
    final (x, y) = tall ? (11, 19) : (wide ? (19, 11) : (15, 15));
    if (x == nx && y == ny) return;
    nx = x;
    ny = y;
    _reset();
  }

    bool _free(_V3 p) =>
      p.x >= 0 && p.x < nx && p.y >= 0 && p.y < ny && p.z >= 0 && p.z < nz && !_used.contains(p);

  void _reset() {
    segs.clear();
    joints.clear();
    pipes.clear();
    _used.clear();
    _started = 0;
    _colour = rng.nextInt(_colours.length);
    fade = 1;
    _clearing = false;
    for (var i = 0; i < lanes; i++) {
      _spawn();
    }
  }

  void _spawn() {
    if (_started >= perScreen) return;
    for (var tries = 0; tries < 60; tries++) {
      final p = _V3(rng.nextInt(nx), rng.nextInt(ny), rng.nextInt(nz));
      if (!_free(p)) continue;
      _used.add(p);
      _colour = (_colour + 1 + rng.nextInt(2)) % _colours.length;
      pipes.add(_Pipe(p, _colours[_colour]));
      _started++;
      return;
    }
  }

  void _step(_Pipe pipe) {
    final options = [
      for (final d in _dirs)
        if (_free(pipe.at + d)) d,
    ];
    if (options.isEmpty) {
      pipe.alive = false;
      return;
    }
    // Mostly straight on; a bend now and then, with a ball joint.
    final d = pipe.dir != null && options.contains(pipe.dir) && rng.nextDouble() < 0.7
        ? pipe.dir!
        : options[rng.nextInt(options.length)];
    if (pipe.dir != null && d != pipe.dir) joints.add((pipe.at, pipe.colour));
    pipe.dir = d;
    final next = pipe.at + d;
    _used.add(next);
    final seg = _Seg(pipe.at, next, pipe.colour);
    segs.add(seg);
    pipe.tip = seg;
    pipe.at = next;
  }

  void advance(double dt) {
    if (_clearing) {
      fade -= dt * 1.6;
      if (fade <= 0) _reset();
      return;
    }
    grow += dt * steps;
    while (grow >= 1) {
      grow -= 1;
      for (final pipe in [...pipes]) {
        if (pipe.alive) _step(pipe);
      }
      final live = pipes.where((p) => p.alive).length;
      for (var i = live; i < lanes; i++) {
        _spawn();
      }
      if (pipes.every((p) => !p.alive) || _used.length > nx * ny * nz * 0.5) {
        _clearing = true;
        break;
      }
    }
  }
}

class _PipesPainter extends CustomPainter {
  _PipesPainter(this.p, Listenable time) : super(repaint: time);

  final _Pipes p;

  @override
  void paint(Canvas canvas, Size size) {
    p.fit(size);
    final nx = p.nx, ny = p.ny, nz = p.nz;
    // A fixed camera a little above and to the side of the box.
    final scale = math.min(size.width / (nx + 1), size.height / (ny + 1)) * 1.02;
    const yaw = 0.36, pitch = 0.24;
    final cy = math.cos(yaw), sy = math.sin(yaw), cp = math.cos(pitch), sp = math.sin(pitch);
    final centre = size.center(Offset.zero);
    (Offset, double, double) project(double x, double y, double z) {
      x -= (nx - 1) / 2;
      y -= (ny - 1) / 2;
      z -= (nz - 1) / 2;
      final x1 = x * cy - z * sy, z1 = x * sy + z * cy;
      final y1 = y * cp - z1 * sp, z2 = y * sp + z1 * cp;
      final k = 1 / (1 + z2 * 0.04);
      return (centre + Offset(x1, -y1) * scale * k, k, z2);
    }

    final r = scale * 0.24;
    final alpha = p.fade.clamp(0.0, 1.0);
    // Everything far to near, so pipes pass in front of and behind each other.
    final items = <(double, void Function())>[];
    final growing = {
      for (final pipe in p.pipes)
        if (pipe.alive && pipe.tip != null) pipe.tip!,
    };
    for (final s in p.segs) {
      final t = growing.contains(s) ? p.grow : 1.0;
      final (a, ka, za) = project(s.a.x.toDouble(), s.a.y.toDouble(), s.a.z.toDouble());
      final (b, kb, zb) = project(
        s.a.x + (s.b.x - s.a.x) * t,
        s.a.y + (s.b.y - s.a.y) * t,
        s.a.z + (s.b.z - s.a.z) * t,
      );
      items.add(((za + zb) / 2, () => _tube(canvas, a, b, r * (ka + kb) / 2, s.colour, alpha)));
    }
    for (final (j, c) in p.joints) {
      final (o, k, z) = project(j.x.toDouble(), j.y.toDouble(), j.z.toDouble());
      // a hair nearer than the pipes meeting there, so it sits over both
      items.add((z - 0.01, () => _ball(canvas, o, r * k * 1.32, c, alpha)));
    }
    items.sort((x, y) => y.$1.compareTo(x.$1));
    for (final (_, draw) in items) {
      draw();
    }
  }

  /// A shiny tube: dark rims, the body, a broad light and a specular streak
  /// along the side facing the light (up-left).
  static void _tube(Canvas canvas, Offset a, Offset b, double r, Color c, double alpha) {
    final d = b - a;
    final len = d.distance;
    if (len < 0.5) return;
    var n = Offset(-d.dy, d.dx) / len;
    if (n.dy > 0 || (n.dy == 0 && n.dx > 0)) n = -n;
    // Overlap the next segment a touch, so no seam shows where they meet.
    final u = d / len * 1.2;
    a -= u;
    b += u;
    final paint = Paint()..strokeCap = StrokeCap.butt;
    void line(Color col, double w, double off) {
      paint
        ..color = col.withValues(alpha: alpha * col.a)
        ..strokeWidth = w;
      canvas.drawLine(a + n * off, b + n * off, paint);
    }

    line(Color.lerp(c, Colors.black, 0.62)!, r * 2, 0);
    line(Color.lerp(c, Colors.black, 0.3)!, r * 1.7, r * 0.06);
    line(c, r * 1.3, r * 0.14);
    line(Color.lerp(c, Colors.white, 0.28)!, r * 0.7, r * 0.36);
    line(Colors.white.withValues(alpha: 0.85), r * 0.16, r * 0.5);
  }

  static void _ball(Canvas canvas, Offset o, double r, Color c, double alpha) {
    canvas.drawCircle(
      o,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.38, -0.42),
          radius: 0.95,
          colors: [
            Colors.white.withValues(alpha: alpha),
            Color.lerp(c, Colors.white, 0.3)!.withValues(alpha: alpha),
            c.withValues(alpha: alpha),
            Color.lerp(c, Colors.black, 0.65)!.withValues(alpha: alpha),
          ],
          stops: const [0, 0.14, 0.5, 1],
        ).createShader(Rect.fromCircle(center: o, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_PipesPainter old) => old.p != p;
}

// ---------------------------------------------------------------------------
// Starfield: flying through space, stars streaking past.
// ---------------------------------------------------------------------------

class _Stars {
  _Stars(this.rng) {
    for (var i = 0; i < count; i++) {
      xs[i] = rng.nextDouble() * 2 - 1;
      ys[i] = rng.nextDouble() * 2 - 1;
      zs[i] = rng.nextDouble();
      pz[i] = zs[i];
    }
  }

  final math.Random rng;
  static const count = 260;
  final xs = List<double>.filled(count, 0);
  final ys = List<double>.filled(count, 0);
  final zs = List<double>.filled(count, 0);

  /// Last frame's depth (for the streak).
  final pz = List<double>.filled(count, 0);
  double speed = 0.35;
  double _t = 0;

  void advance(double dt) {
    _t += dt;
    // Now and then a surge, like a jump.
    speed = 0.3 + 0.25 * math.pow(math.max(0, math.sin(_t * 0.23)), 6).toDouble();
    for (var i = 0; i < count; i++) {
      pz[i] = zs[i];
      zs[i] -= dt * speed;
      if (zs[i] <= 0.015) {
        xs[i] = rng.nextDouble() * 2 - 1;
        ys[i] = rng.nextDouble() * 2 - 1;
        zs[i] = 1;
        pz[i] = 1;
      }
    }
  }
}

class _StarsPainter extends CustomPainter {
  _StarsPainter(this.s, Listenable time) : super(repaint: time);

  final _Stars s;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final k = math.max(size.width, size.height) * 0.5;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < _Stars.count; i++) {
      final z = s.zs[i];
      final p = c + Offset(s.xs[i] / z, s.ys[i] / z) * k * 0.35;
      if (!(Offset.zero & size).inflate(4).contains(p)) continue;
      final q = c + Offset(s.xs[i] / s.pz[i], s.ys[i] / s.pz[i]) * k * 0.35;
      final near = (1 - z).clamp(0.0, 1.0);
      final v = (40 + 215 * near * near).round();
      paint
        ..color = Color.fromARGB(255, v, v, math.min(255, v + 20))
        ..strokeWidth = 0.8 + near * 2.6;
      canvas.drawLine(q, p, paint);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => old.s != s;
}

// ---------------------------------------------------------------------------
// 3D Text: the user's words, extruded, turning slowly and drifting round
// the screen, colour cycling.
// ---------------------------------------------------------------------------

class _Text3d extends StatelessWidget {
  const _Text3d({required this.text, required this.time});

  final String text;
  final ValueNotifier<double> time;

  static const layers = 12;

  @override
  Widget build(BuildContext context) {
    final words = text.trim().isEmpty ? 'Darkroom 98' : text.trim();
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final font = (size.width / (words.length * 0.75 + 2)).clamp(10.0, size.height * 0.22);
        final depth = font * 0.035;
        return ValueListenableBuilder<double>(
          valueListenable: time,
          builder: (context, t, _) {
            // Drift: two slow bounces that never line up.
            double tri(double v) => (v % 2 - 1).abs() * 2 - 1;
            final at = Offset(tri(t * 0.045 + 0.3) * 0.55, tri(t * 0.037 + 0.7) * 0.6);
            final m = Matrix4.identity()
              ..setEntry(3, 2, 0.0016)
              ..rotateX(math.sin(t * 0.43) * 0.42)
              ..rotateY(math.sin(t * 0.61) * 0.85)
              ..rotateZ(math.sin(t * 0.29) * 0.12);
            final hue = (t * 24) % 360;
            final face = HSVColor.fromAHSV(1, hue, 0.7, 1).toColor();
            final side = HSVColor.fromAHSV(1, (hue + 18) % 360, 0.85, 0.5).toColor();
            final style = TextStyle(
              fontSize: font,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: font * 0.02,
            );
            return Align(
              alignment: Alignment(at.dx, at.dy),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Back to front: each slice its own full matrix (Flutter
                  // flattens nested 3D transforms).
                  for (var i = layers; i >= 0; i--)
                    Transform(
                      alignment: Alignment.center,
                      transform: m.clone()..translateByDouble(0, 0, i * depth, 1),
                      child: Text(
                        words,
                        maxLines: 1,
                        softWrap: false,
                        style: style.copyWith(
                          color: i == 0 ? face : Color.lerp(side, Colors.black, i / layers * 0.6),
                          shadows: i == 0
                              ? [
                                  Shadow(
                                    color: Colors.white.withValues(alpha: 0.35),
                                    offset: Offset(-font * 0.02, -font * 0.02),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
