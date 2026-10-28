import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/sfx.dart';
import '../../../../core/device/haptics.dart';
import '../../../camera/application/camera_ui_state.dart' show win98MonitorProvider;
import 'win98_display.dart';
import 'win98_widgets.dart';

/// The beige monitor round the explorer: a moulded plastic bezel with a
/// recessed, slightly shadowed screen, a maker's badge and a green power
/// lamp on the chin. The bezel takes up the system's insets (status bar,
/// gesture strip, a camera cutout at the side), so the screen inside is all
/// Windows; turned to landscape its sides are wide enough to keep the
/// window's corners (the close button) off the phone's rounded corners.
///
/// Its [Win98Display] settings: a CRT's curved glass and scan lines (or a
/// flat panel), brightness and contrast knobs on the chin (on the right
/// side when turned) with an on-screen bar while they turn, the colour,
/// and on a CRT a degauss button: the picture wobbles and swims with
/// colour, with a thunk.
class ExplorerMonitor extends ConsumerStatefulWidget {
  const ExplorerMonitor({super.key, required this.child});

  static const bezel = 12.0;

  static EdgeInsets bezelOf(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.aspectRatio > 1) return const EdgeInsets.symmetric(horizontal: 24, vertical: 4);
    return EdgeInsets.fromLTRB(
      bezel,
      math.max(bezel, mq.padding.top + 4),
      bezel,
      math.max(bezel + 4, mq.padding.bottom + 4),
    );
  }

  final Widget child;

  @override
  ConsumerState<ExplorerMonitor> createState() => _ExplorerMonitorState();
}

class _ExplorerMonitorState extends ConsumerState<ExplorerMonitor> with SingleTickerProviderStateMixin {
  late final _degauss = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  /// The knob being turned and its value, while the on-screen bar shows.
  (String, double)? _osd;
  Timer? _osdTimer;

  @override
  void initState() {
    super.initState();
    // The saved settings, before anything on the monitor draws (no change
    // = no notification, so the next screen's monitor costs nothing).
    Win98Display.current.value = ref.read(win98DisplayProvider);
  }

  @override
  void dispose() {
    _degauss.dispose();
    _osdTimer?.cancel();
    super.dispose();
  }

  void _turn(bool brightness, double delta, {bool save = false}) {
    final d = Win98Display.current.value;
    final v = ((brightness ? d.brightness : d.contrast) + delta).clamp(0.0, 1.0);
    ref
        .read(win98DisplayProvider.notifier)
        .set(
          brightness ? d.copyWith(brightness: v) : d.copyWith(contrast: v),
          save: save,
        );
    setState(() => _osd = (brightness ? 'BRIGHTNESS' : 'CONTRAST', v));
    _osdTimer?.cancel();
    _osdTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _osd = null);
    });
  }

  void _degaussNow() {
    if (_degauss.isAnimating) return;
    Sfx.w98Degauss.play();
    unawaited(Haptics.heavyImpact());
    unawaited(_degauss.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    final bezel = ExplorerMonitor.bezelOf(context);
    final finish = MonitorFinish.byName(ref.watch(win98MonitorProvider));
    final d = ref.watch(win98DisplayProvider);
    final land = MediaQuery.sizeOf(context).aspectRatio > 1;
    final radius = d.crt ? 22.0 : 6.0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // status-bar icons that read on the plastic
      value: finish.darkIcons ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      // No fill of its own: the bezel paints the plastic, and while a
      // window zooms open on the screen the one below shows through.
      child: SizedBox.expand(
        child: LayoutBuilder(
          builder: (context, box) {
            final size = box.biggest;
            return Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: bezel,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: RepaintBoundary(
                      // A CRT's picture bulges (the scan lines with it).
                      child: CrtWarp(
                        on: d.crt,
                        child: Win98Glass(
                          screen: true,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AnimatedBuilder(
                                animation: _degauss,
                                // the insets are the monitor's; inside it is all screen
                                child: MediaQuery.removePadding(
                                  context: context,
                                  removeTop: true,
                                  removeBottom: true,
                                  removeLeft: true,
                                  removeRight: true,
                                  child: widget.child,
                                ),
                                // Always a Transform (identity at rest): swapping it
                                // in and out would rebuild the screen's state.
                                builder: (context, child) => Transform(
                                  alignment: Alignment.center,
                                  transform: _degauss.isAnimating
                                      ? _wobble(_degauss.value)
                                      : Matrix4.identity(),
                                  child: child,
                                ),
                              ),
                              IgnorePointer(
                                child: AnimatedBuilder(
                                  animation: _degauss,
                                  builder: (context, _) => _degauss.isAnimating
                                      ? CustomPaint(painter: _RainbowPainter(_degauss.value))
                                      : const SizedBox.shrink(),
                                ),
                              ),
                              if (_osd case (final label, final v))
                                IgnorePointer(
                                  child: _Osd(label: label, value: v),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: RepaintBoundary(child: CustomPaint(painter: _BezelPainter(bezel, finish, radius))),
                ),
                ..._controls(size, bezel, finish, d, land),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The knobs (and on a CRT the degauss button): along the chin left of
  /// the power lamp, or up the right side when turned.
  List<Widget> _controls(Size size, EdgeInsets bezel, MonitorFinish finish, Win98Display d, bool land) {
    final out = <Widget>[];
    void place(int i, double w, double h, Widget child) {
      final Offset c;
      if (land) {
        c = Offset(size.width - bezel.right / 2, size.height - 34 - i * 30);
      } else {
        final lamp = size.width - math.max(bezel.right, 12) - 14;
        c = Offset(lamp - 24 - i * 28, size.height - bezel.bottom / 2);
      }
      out.add(Positioned(left: c.dx - w / 2, top: c.dy - h / 2, width: w, height: h, child: child));
    }

    final knob = land ? 15.0 : (bezel.bottom - 6).clamp(10.0, 17.0);
    final hitW = land ? bezel.right : 26.0, hitH = land ? 28.0 : bezel.bottom;
    for (final (i, bright) in [(0, false), (1, true)]) {
      place(
        i,
        hitW,
        hitH,
        _Knob(
          size: knob,
          value: bright ? d.brightness : d.contrast,
          finish: finish,
          label: bright ? 'Brightness' : 'Contrast',
          onTurn: (delta) => _turn(bright, delta),
          onDone: () => _turn(bright, 0, save: true),
        ),
      );
    }
    if (d.crt) {
      place(2, hitW, hitH, _DegaussButton(finish: finish, size: knob, onPressed: _degaussNow));
    }
    return out;
  }

  /// The picture shaken by the degaussing coil: a quick wobble that dies away.
  static Matrix4 _wobble(double t) {
    final amp = math.pow(1 - t, 2).toDouble() * math.min(1, t * 12);
    return Matrix4.identity()
      ..translateByDouble(math.sin(t * 74) * 5 * amp, math.cos(t * 55) * 2.5 * amp, 0, 1)
      ..scaleByDouble(1 + 0.025 * amp * math.sin(t * 31), 1 + 0.018 * amp * math.cos(t * 27), 1, 1)
      ..setEntry(0, 1, 0.02 * amp * math.sin(t * 43));
  }
}

/// Degaussing: colour swimming across the tube, fading as the field dies.
class _RainbowPainter extends CustomPainter {
  const _RainbowPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final amp = math.pow(1 - t, 1.5).toDouble() * math.min(1, t * 10);
    final rect = Offset.zero & size;
    const hues = [
      Color(0xFFFF2A6D),
      Color(0xFFFFD02A),
      Color(0xFF2AFF7A),
      Color(0xFF2AC8FF),
      Color(0xFF9B2AFF),
      Color(0xFFFF2A6D),
    ];
    canvas.drawRect(
      rect,
      Paint()
        ..shader = SweepGradient(
          colors: [for (final c in hues) c.withValues(alpha: 0.42 * amp)],
          transform: GradientRotation(t * 14),
        ).createShader(rect),
    );
    // Blotches of the shadow mask pulled out of line, in the corners.
    for (final (a, c) in [
      (const Alignment(-1, -1), const Color(0xFFFF30C0)),
      (const Alignment(1, 1), const Color(0xFF30FFB0)),
      (const Alignment(1, -1), const Color(0xFF3080FF)),
    ]) {
      final o = a.alongSize(size);
      final r = size.shortestSide * (0.45 + 0.1 * math.sin(t * 20));
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              c.withValues(alpha: 0.5 * amp),
              c.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: o, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_RainbowPainter old) => old.t != t;
}

/// The monitor's own on-screen display: the setting and a bar of blocks.
class _Osd extends StatelessWidget {
  const _Osd({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF7CFF6B);
    final on = (value * 20).round();
    return Align(
      alignment: const Alignment(0, 0.72),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          border: Border.all(color: ink.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontFamily: 'W98', color: ink, fontSize: 13, letterSpacing: 2),
              textScaler: TextScaler.noScaling,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 20; i++)
                  Container(
                    width: 6,
                    height: 10,
                    margin: const EdgeInsets.only(right: 2),
                    color: i < on ? ink : ink.withValues(alpha: 0.15),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A brightness / contrast knob on the bezel: drag it (up or right turns it
/// up), or tap its left / right half for a notch down / up.
class _Knob extends StatelessWidget {
  const _Knob({
    required this.size,
    required this.value,
    required this.finish,
    required this.label,
    required this.onTurn,
    required this.onDone,
  });

  final double size;
  final double value;
  final MonitorFinish finish;
  final String label;
  final ValueChanged<double> onTurn;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    Offset? down;
    var moved = false;
    return Semantics(
      label: label,
      value: '${(value * 100).round()}%',
      increasedValue: '${(math.min(1.0, value + 0.05) * 100).round()}%',
      decreasedValue: '${(math.max(0.0, value - 0.05) * 100).round()}%',
      onIncrease: () {
        onTurn(0.05);
        onDone();
      },
      onDecrease: () {
        onTurn(-0.05);
        onDone();
      },
      // Claims the touch at once, so turning it never swipes the
      // explorer away.
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            EagerGestureRecognizer.new,
            (_) {},
          ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            down = e.localPosition;
            moved = false;
          },
          onPointerMove: (e) {
            final d = e.delta;
            if (!moved && (e.localPosition - (down ?? e.localPosition)).distance < 4) return;
            moved = true;
            onTurn((d.dx - d.dy) / 140);
          },
          onPointerUp: (e) {
            if (!moved) {
              final box = context.findRenderObject() as RenderBox?;
              final mid = (box?.size.width ?? size) / 2;
              onTurn(e.localPosition.dx < mid ? -0.05 : 0.05);
              Sfx.w98Click.play();
            }
            onDone();
          },
          onPointerCancel: (_) => onDone(),
          child: Center(
            child: CustomPaint(size: Size.square(size), painter: _KnobPainter(value, finish)),
          ),
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  const _KnobPainter(this.value, this.finish);

  final double value;
  final MonitorFinish finish;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    // Seated in a little well in the plastic.
    canvas.drawCircle(
      c + const Offset(0, 0.6),
      r + 1.2,
      Paint()..color = finish.lipShade.withValues(alpha: 0.7),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: [finish.edgeLit, finish.light, finish.dark, finish.edgeShade],
          stops: const [0, 0.35, 0.8, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Knurls round the rim.
    final knurl = Paint()
      ..color = finish.edgeShade.withValues(alpha: 0.55)
      ..strokeWidth = 0.7;
    for (var i = 0; i < 18; i++) {
      final a = i / 18 * math.pi * 2;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * r * 0.78, c + dir * r * 0.97, knurl);
    }
    // The pointer: -135 deg (min) .. +135 deg (max), 0 straight up.
    final a = (-135 + 270 * value) * math.pi / 180 - math.pi / 2;
    final dir = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(
      c + dir * r * 0.15,
      c + dir * r * 0.72,
      Paint()
        ..color = finish.badge
        ..strokeWidth = math.max(1.2, r * 0.22)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_KnobPainter old) => old.value != value || old.finish != finish;
}

/// The degauss push button (a little square key with the coil's symbol).
class _DegaussButton extends StatefulWidget {
  const _DegaussButton({required this.finish, required this.size, required this.onPressed});

  final MonitorFinish finish;
  final double size;
  final VoidCallback onPressed;

  @override
  State<_DegaussButton> createState() => _DegaussButtonState();
}

class _DegaussButtonState extends State<_DegaussButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Degauss',
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            EagerGestureRecognizer.new,
            (_) {},
          ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => setState(() => _down = true),
          onPointerUp: (_) {
            setState(() => _down = false);
            widget.onPressed();
          },
          onPointerCancel: (_) => setState(() => _down = false),
          child: Center(
            child: CustomPaint(
              size: Size(widget.size * 1.15, widget.size * 0.8),
              painter: _DegaussPainter(widget.finish, _down),
            ),
          ),
        ),
      ),
    );
  }
}

class _DegaussPainter extends CustomPainter {
  const _DegaussPainter(this.finish, this.down);

  final MonitorFinish finish;
  final bool down;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2));
    canvas.drawRRect(r.inflate(1), Paint()..color = finish.lipShade.withValues(alpha: 0.7));
    canvas.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: down ? [finish.dark, finish.mid] : [finish.edgeLit, finish.dark],
        ).createShader(Offset.zero & size),
    );
    // The coil: a little horseshoe magnet.
    final c = size.center(Offset(0, down ? 0.6 : 0));
    final m = size.height * 0.26;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: m),
      0,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, m * 0.45)
        ..color = finish.badge,
    );
    final p = Paint()
      ..color = finish.badge
      ..strokeWidth = math.max(1, m * 0.45);
    canvas.drawLine(c + Offset(-m, 0), c + Offset(-m, -m * 0.9), p);
    canvas.drawLine(c + Offset(m, 0), c + Offset(m, -m * 0.9), p);
  }

  @override
  bool shouldRepaint(_DegaussPainter old) => old.down != down || old.finish != finish;
}

class _BezelPainter extends CustomPainter {
  const _BezelPainter(this.insets, this.finish, this.radius);

  final EdgeInsets insets;
  final MonitorFinish finish;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    final screen = RRect.fromRectAndRadius(insets.deflateRect(outer), Radius.circular(radius));
    // The plastic: lit from above, a touch darker toward the bottom, with
    // a faint moulding texture.
    final frame = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(outer)
      ..addRRect(screen);
    canvas.drawPath(
      frame,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [finish.light, finish.mid, finish.dark],
          stops: const [0, 0.5, 1],
        ).createShader(outer),
    );
    // Rounded outer edge catching the light (left/top) and in shade (right/bottom).
    canvas.drawRect(
      outer.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [finish.edgeLit, finish.edgeShade],
        ).createShader(outer),
    );
    // The screen sits in a recess: a dark lip, a shadow cast inward.
    canvas.drawRRect(
      screen.inflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [finish.lipShade, finish.lipLit],
        ).createShader(outer),
    );
    canvas.save();
    canvas.clipRRect(screen);
    // The recess's inner shadow: gradients along each edge (no blur pass).
    const depth = 9.0, shade = Color(0x4D000000), clear = Color(0x00000000);
    final r = screen.outerRect;
    for (final (rect, begin, end) in [
      (Rect.fromLTWH(r.left, r.top, r.width, depth), Alignment.topCenter, Alignment.bottomCenter),
      (Rect.fromLTWH(r.left, r.bottom - depth, r.width, depth), Alignment.bottomCenter, Alignment.topCenter),
      (Rect.fromLTWH(r.left, r.top, depth, r.height), Alignment.centerLeft, Alignment.centerRight),
      (Rect.fromLTWH(r.right - depth, r.top, depth, r.height), Alignment.centerRight, Alignment.centerLeft),
    ]) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(begin: begin, end: end, colors: const [shade, clear]).createShader(rect),
      );
    }
    // A whisper of glass glare across the top-left.
    canvas.drawRect(
      screen.outerRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: const Alignment(0.2, 0.1),
          colors: [Colors.white.withValues(alpha: 0.07), Colors.white.withValues(alpha: 0)],
        ).createShader(screen.outerRect),
    );
    canvas.restore();
    // Power lamp on the chin (right) and the maker's badge (left).
    final t = insets.bottom;
    final y = size.height - t / 2;
    final lamp = Offset(size.width - math.max(insets.right, 12) - 14, y);
    canvas.drawCircle(lamp, 3.2, Paint()..color = const Color(0xFF3C6E3C));
    canvas.drawCircle(lamp, 2.4, Paint()..color = const Color(0xFF7CFF6B));
    canvas.drawCircle(
      lamp,
      7,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x667CFF6B), Color(0x007CFF6B)],
        ).createShader(Rect.fromCircle(center: lamp, radius: 7)),
    );
    final badge = TextPainter(
      text: TextSpan(
        text: 'DARKROOM',
        style: TextStyle(color: finish.badge, fontSize: 7.5, fontWeight: FontWeight.w800, letterSpacing: 2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    badge.paint(canvas, Offset(math.max(insets.left, 12) + 8, y - badge.height / 2));
  }

  @override
  bool shouldRepaint(_BezelPainter old) =>
      old.insets != insets || old.finish != finish || old.radius != radius;
}
