import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/audio/sfx.dart';
import '../../../../core/theme/darkroom_mark.dart';
import '../../../../core/device/haptics.dart';

/// Start > Shut Down: the "shutting down" screen (sky, clouds and a pixel
/// rabbit, with a shutdown tune), then the monitor switching off: the
/// picture collapses into a bright line, the line into a dot, and the dot
/// fades out. Tap to skip ahead.
Future<void> showShutDownSequence(BuildContext context) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, _, _) => const _ShutDown(),
    transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
  ),
);

enum _Stage { shuttingDown, crt, off }

class _ShutDown extends StatefulWidget {
  const _ShutDown();

  @override
  State<_ShutDown> createState() => _ShutDownState();
}

class _ShutDownState extends State<_ShutDown> with SingleTickerProviderStateMixin {
  _Stage _stage = _Stage.shuttingDown;
  Timer? _next;

  /// Drives the CRT switching off (0 = full picture, 1 = glow gone).
  late final AnimationController _crt = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// The "shutting down" screen, taken once as a picture so the switch-off
  /// only ever draws an image (repainting the live screen and its blurred
  /// clouds every frame made it stutter).
  final _screenKey = GlobalKey();
  ui.Image? _still;

  @override
  void initState() {
    super.initState();
    Sfx.w98Shutdown.play();
    unawaited(Sfx.crtOff.preload());
    _next = Timer(const Duration(milliseconds: 3800), _toCrt);
  }

  @override
  void dispose() {
    _next?.cancel();
    _crt.dispose();
    _still?.dispose();
    super.dispose();
  }

  void _toCrt() {
    if (!mounted || _stage.index >= _Stage.crt.index) return;
    _next?.cancel();
    try {
      final boundary = _screenKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      _still = boundary?.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context));
    } catch (_) {
      _still = null;
    }
    setState(() => _stage = _Stage.crt);
    Sfx.crtOff.play();
    unawaited(Haptics.lightImpact());
    unawaited(
      _crt.forward().then((_) {
        if (!mounted) return;
        setState(() => _stage = _Stage.off);
        _next = Timer(const Duration(milliseconds: 200), () {
          if (mounted) Navigator.of(context).pop();
        });
      }),
    );
  }

  void _skip() => _toCrt();

  @override
  Widget build(BuildContext context) {
    final still = _still;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: ColoredBox(
        color: Colors.black,
        child: switch (_stage) {
          _Stage.shuttingDown => RepaintBoundary(key: _screenKey, child: const _ShuttingDownScreen()),
          _Stage.crt => CustomPaint(size: Size.infinite, painter: _CrtOffPainter(_crt, still)),
          _Stage.off => const SizedBox.expand(),
        },
      ),
    );
  }
}

/// A CRT losing power: the picture snaps into a white-hot line almost at
/// once (like the plug being pulled), the line pulls in to a dot, and the
/// dot's phosphor glow lingers for a second before it fades.
class _CrtOffPainter extends CustomPainter {
  _CrtOffPainter(this.t, this.still) : super(repaint: t);

  final Animation<double> t;
  final ui.Image? still;

  // Phases, as fractions of the 1.4 s run.
  static const _cut = 0.07, _line = 0.16;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    double seg(double a, double b) => ((v - a) / (b - a)).clamp(0.0, 1.0);
    final c = size.center(Offset.zero);
    const white = Color(0xFFF4F8FF);
    if (v < _cut) {
      // The picture collapses vertically and burns white on the way.
      final p = Curves.easeIn.transform(seg(0, _cut));
      final h = math.max(3.0, size.height * (1 - p));
      final dst = Rect.fromCenter(center: c, width: size.width, height: h);
      final img = still;
      if (img != null) {
        canvas.drawImageRect(
          img,
          Offset.zero & Size(img.width.toDouble(), img.height.toDouble()),
          dst,
          Paint()..filterQuality = FilterQuality.low,
        );
      }
      canvas.drawRect(dst, Paint()..color = white.withValues(alpha: 0.25 + 0.75 * p));
      return;
    }
    if (v < _line) {
      // The line pulls in to the middle.
      final p = Curves.easeInCubic.transform(seg(_cut, _line));
      final w = math.max(6.0, size.width * (1 - p));
      _glow(canvas, c, w / 2, 1.0);
      canvas.drawRect(Rect.fromCenter(center: c, width: w, height: 3), Paint()..color = white);
      return;
    }
    // The dot, fading slowly (phosphor afterglow).
    final p = seg(_line, 1);
    final a = math.pow(1 - p, 2.2).toDouble();
    _glow(canvas, c, 3 + 10 * (1 - p), a);
    canvas.drawCircle(c, 2.5 * (1 - p * 0.6), Paint()..color = white.withValues(alpha: a));
  }

  /// A soft blue-white halo around the beam, from gradients (no blur pass).
  void _glow(Canvas canvas, Offset c, double halfWidth, double alpha) {
    const r = 28.0;
    final colors = [
      const Color(0xFFB9D4FF).withValues(alpha: 0.55 * alpha),
      const Color(0xFF6E9BFF).withValues(alpha: 0.18 * alpha),
      const Color(0x006E9BFF),
    ];
    const stops = [0.0, 0.35, 1.0];
    if (halfWidth > r) {
      // Along a line: an even band above and below it.
      for (final dir in [-1.0, 1.0]) {
        final band = Rect.fromLTWH(c.dx - halfWidth, dir < 0 ? c.dy - r : c.dy, halfWidth * 2, r);
        canvas.drawRect(
          band,
          Paint()
            ..shader = LinearGradient(
              begin: dir < 0 ? Alignment.bottomCenter : Alignment.topCenter,
              end: dir < 0 ? Alignment.topCenter : Alignment.bottomCenter,
              colors: colors,
              stops: stops,
            ).createShader(band),
        );
      }
      return;
    }
    canvas.drawCircle(
      c,
      r + halfWidth,
      Paint()
        ..shader = RadialGradient(
          colors: colors,
          stops: stops,
        ).createShader(Rect.fromCircle(center: c, radius: r + halfWidth)),
    );
  }

  @override
  bool shouldRepaint(_CrtOffPainter old) => old.still != still;
}

/// "Darkroom is shutting down...": the sky with soft clouds and the rabbit.
class _ShuttingDownScreen extends StatelessWidget {
  const _ShuttingDownScreen();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2B5FB8), Color(0xFF6E9BDA), Color(0xFFA9C6EC)],
        ),
      ),
      child: CustomPaint(
        painter: const _Clouds(),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              const PixelRabbit(height: 132),
              const SizedBox(height: 18),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Darkroom'),
                    TextSpan(
                      text: '98',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(
                  fontFamily: 'W98',
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  decoration: TextDecoration.none,
                  shadows: [Shadow(color: Color(0x66000000), offset: Offset(2, 2))],
                ),
              ),
              const Spacer(flex: 3),
              const Text(
                'Darkroom is shutting down...',
                style: TextStyle(
                  fontFamily: 'W98',
                  color: Colors.white,
                  fontSize: 18,
                  decoration: TextDecoration.none,
                  shadows: [Shadow(color: Color(0x88000000), offset: Offset(1, 1))],
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _Clouds extends CustomPainter {
  const _Clouds();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(98);
    final paint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    for (var i = 0; i < 14; i++) {
      final c = Offset(rnd.nextDouble() * size.width, size.height * (0.15 + rnd.nextDouble() * 0.8));
      final w = size.width * (0.25 + rnd.nextDouble() * 0.35);
      paint.color = Colors.white.withValues(alpha: 0.18 + rnd.nextDouble() * 0.22);
      for (var j = 0; j < 4; j++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: c + Offset((j - 1.5) * w * 0.22, (rnd.nextDouble() - 0.5) * w * 0.08),
            width: w * 0.45,
            height: w * 0.2,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Clouds old) => false;
}

/// The rabbit as chunky, mis-converged pixel art (rendered tiny, then
/// blown up without smoothing), with a trail of loose pixels behind it like
/// the boot-screen logos of the day.
class PixelRabbit extends StatefulWidget {
  const PixelRabbit({super.key, this.height = 120});

  final double height;

  @override
  State<PixelRabbit> createState() => _PixelRabbitState();
}

class _PixelRabbitState extends State<PixelRabbit> {
  static const _h = 30, _w = 44; // the sprite, in pixels
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const glyphH = 24.0;
    const left = 16.0, top = 3.0;
    canvas.saveLayer(const Rect.fromLTWH(0, 0, _w * 1.0, _h * 1.0), Paint());
    for (final (c, dx) in [
      (const Color(0xFFFF0000), -1.0),
      (const Color(0xFF00FF00), 0.0),
      (const Color(0xFF0000FF), 1.0),
    ]) {
      canvas.saveLayer(const Rect.fromLTWH(0, 0, _w * 1.0, _h * 1.0), Paint()..blendMode = BlendMode.plus);
      canvas.translate(left + dx, top);
      DarkroomMarkPainter(color: c).paint(canvas, const Size(glyphH * DarkroomMark.aspect, glyphH));
      canvas.restore();
    }
    // Loose pixels trailing off to the left, thinning out.
    final rnd = math.Random(98);
    const trail = [Color(0xFFFF4040), Color(0xFF40FF40), Color(0xFF4060FF), Color(0xFFFFFFFF)];
    for (var x = 0; x < 15; x++) {
      for (var y = 8; y < 26; y++) {
        if (rnd.nextDouble() < x / 22) {
          canvas.drawRect(Rect.fromLTWH(x * 1.0, y * 1.0, 1, 1), Paint()..color = trail[rnd.nextInt(4)]);
        }
      }
    }
    canvas.restore();
    _image = rec.endRecording().toImageSync(_w, _h);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    return RawImage(
      image: _image,
      width: h * _w / _h,
      height: h,
      filterQuality: FilterQuality.none,
      fit: BoxFit.fill,
    );
  }
}
