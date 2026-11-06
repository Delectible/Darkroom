import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/haptics.dart';
import '../../cameras/domain/camera_spec.dart';
import '../application/exposure_controller.dart';
import '../application/lens_controller.dart';
import '../application/multi_exposure_controller.dart';
import '../application/zoom_controller.dart';
import 'viewfinder_shut.dart';
import 'viewport.dart' show CameraNote;

/// The film viewfinder's controls, drawn into the viewfinder itself:
///
/// * a zoom ring along the bottom edge: the top of a lens barrel, marked in
///   mm, turned by dragging sideways. It brightens under the finger, clicks
///   past each mark, coasts when let go and stops hard (with a little give)
///   at the ends of this camera's lens;
/// * an exposure scale up the right edge, dragged up (brighter) or down,
///   stepping as the camera does (thirds, halves, the instant's darken /
///   lighten wheel).
///
/// Faint at rest, so the picture stays the picture; they come up smoothly
/// when touched and settle back a moment after. Drawn, not built from
/// widgets: one paint per frame while moving, nothing at rest.
class FilmDials extends ConsumerStatefulWidget {
  const FilmDials({super.key, required this.spec});

  final CameraSpec spec;

  @override
  ConsumerState<FilmDials> createState() => _FilmDialsState();
}

class _FilmDialsState extends ConsumerState<FilmDials> with TickerProviderStateMixin {
  /// The lens tray is open.
  bool _tray = false;

  // How lit each control is (0 at rest, 1 in use).
  late final _zoomLit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 650),
  );
  late final _evLit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 650),
  );
  Timer? _zoomRest, _evRest;

  /// The ring's position (log of the focal length, mm): may run a little
  /// past the lens's ends while held or bouncing back.
  double? _ring;
  late final Ticker _coast = createTicker(_onCoast);
  Simulation? _sim;
  Duration _simStart = Duration.zero;
  bool _dragging = false;

  // exposure drag: the finger's position in steps
  double _evDrag = 0;

  /// Repaints (cheaper than setState: only the painter redraws).
  final _paint = ValueNotifier<int>(0);

  double get _wide => widget.spec.zoom?.wideMm ?? 28;

  (double, double) _bounds(ZoomState z) {
    final lo = math.log(_wide * z.min), hi = math.log(_wide * math.max(z.min, z.max));
    return (lo, hi);
  }

  @override
  void dispose() {
    _zoomRest?.cancel();
    _evRest?.cancel();
    _coast.dispose();
    _zoomLit.dispose();
    _evLit.dispose();
    _paint.dispose();
    super.dispose();
  }

  // ---- zoom -----------------------------------------------------------------

  void _light(AnimationController c, Timer? Function() get, void Function(Timer?) set, bool on) {
    get()?.cancel();
    if (on) {
      c.forward();
    } else {
      // (lingers a moment, then fades)
      set(
        Timer(const Duration(milliseconds: 700), () {
          if (mounted) c.reverse();
        }),
      );
    }
  }

  void _zoomOn(bool on) => _light(_zoomLit, () => _zoomRest, (t) => _zoomRest = t, on);
  void _evOn(bool on) => _light(_evLit, () => _evRest, (t) => _evRest = t, on);

  /// Ring travel per pixel dragged: the whole lens over most of the width.
  double _perPx(double width, ZoomState z) {
    final (lo, hi) = _bounds(z);
    return math.max(0.05, hi - lo) / (width * 0.78);
  }

  void _zoomStart(DragStartDetails _) {
    final z = ref.read(zoomProvider);
    if (!z.canZoom) return;
    _coast.stop();
    _sim = null;
    _dragging = true;
    _ring ??= math.log(_wide * z.level);
    _zoomOn(true);
  }

  void _zoomUpdate(DragUpdateDetails d, double width) {
    if (!_dragging) return;
    final z = ref.read(zoomProvider);
    final (lo, hi) = _bounds(z);
    // dragging left turns the long end under the notch (zooms in)
    var delta = -d.delta.dx * _perPx(width, z);
    final r = _ring!;
    // past an end: stiff, and never far
    if ((r <= lo && delta < 0) || (r >= hi && delta > 0)) {
      final over = r < lo ? lo - r : r - hi;
      delta *= math.max(0, 0.35 - over * 3);
    }
    _move(r + delta, lo, hi);
  }

  void _zoomEnd(DragEndDetails d, double width) {
    if (!_dragging) return;
    _dragging = false;
    final z = ref.read(zoomProvider);
    final (lo, hi) = _bounds(z);
    final v = -(d.primaryVelocity ?? 0) * _perPx(width, z);
    final r = _ring!;
    if (r < lo || r > hi) {
      _run(SpringSimulation(_spring, r, r < lo ? lo : hi, v));
    } else if (v.abs() > 0.15) {
      _run(FrictionSimulation(0.06, r, v));
    } else {
      _finish();
    }
  }

  static const _spring = SpringDescription(mass: 1, stiffness: 260, damping: 26);

  void _run(Simulation s) {
    _sim = s;
    _simStart = Duration.zero;
    _coast
      ..stop()
      ..start();
  }

  void _onCoast(Duration t) {
    final s = _sim;
    if (s == null) return;
    if (_simStart == Duration.zero) _simStart = t;
    final secs = (t - _simStart).inMicroseconds / 1e6;
    final z = ref.read(zoomProvider);
    final (lo, hi) = _bounds(z);
    final x = s.x(secs);
    // coasting into an end: it bounces back off the stop
    if (s is FrictionSimulation && (x < lo || x > hi)) {
      _move(x, lo, hi);
      return _run(SpringSimulation(_spring, x, x < lo ? lo : hi, s.dx(secs) * 0.4));
    }
    _move(x, lo, hi);
    if (s.isDone(secs)) {
      _coast.stop();
      _sim = null;
      _finish();
    }
  }

  void _move(double r, double lo, double hi) {
    final before = _ring;
    _ring = r;
    final clamped = r.clamp(lo, hi);
    ref.read(zoomProvider.notifier).setLevel(math.exp(clamped) / _wide);
    // a click for each mark the notch passes
    if (before != null) {
      final a = math.exp(before.clamp(lo, hi)), b = math.exp(clamped);
      for (final m in _marks(math.exp(lo), math.exp(hi))) {
        if ((a < m && b >= m) || (a > m && b <= m)) {
          unawaited(Haptics.selectionClick());
          break;
        }
      }
    }
    _paint.value++;
  }

  void _finish() {
    ref.read(zoomProvider.notifier).settle();
    _zoomOn(false);
  }

  /// The focal lengths the ring is marked with (and clicks at).
  static List<double> _marks(double lo, double hi) => [
    for (final m in const [9, 12, 15, 18, 24, 28, 32, 35, 40, 48, 50, 60, 70, 85, 100, 116, 135, 150, 175])
      if (m >= lo - 0.5 && m <= hi + 0.5) m.toDouble(),
  ];

  // ---- exposure ---------------------------------------------------------------

  void _evStart(DragStartDetails _) {
    final e = widget.spec.exposure;
    if (e == null) return;
    _evDrag = (ref.read(exposureCompProvider) - e.min) / e.step;
    _evOn(true);
  }

  void _evUpdate(DragUpdateDetails d, double scaleHeight) {
    final e = widget.spec.exposure;
    if (e == null) return;
    // the whole scale is the whole range; up is brighter
    _evDrag = (_evDrag - d.delta.dy / (scaleHeight / e.steps)).clamp(-0.4, e.steps + 0.4);
    final v = e.snap(e.min + _evDrag.round() * e.step);
    if (v != ref.read(exposureCompProvider)) {
      ref.read(exposureCompProvider.notifier).set(v);
      unawaited(Haptics.selectionClick());
    }
  }

  void _evEnd(DragEndDetails _) => _evOn(false);

  // ---- the special ----------------------------------------------------------

  void _special() {
    switch (widget.spec.special) {
      case CameraSpecial.multipleExposure:
        final n = ref.read(multiExposureProvider.notifier);
        final was = ref.read(multiExposureProvider);
        n.toggle();
        unawaited(Haptics.lightImpact());
        CameraNote.show(
          was.armed
              ? (was.holding ? 'Double exposure cancelled' : 'Multiple exposure off')
              : 'Multiple exposure: the next two shots share a frame',
        );
      case null:
        break;
    }
  }

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final z = ref.watch(zoomProvider);
    final ev = ref.watch(exposureCompProvider);
    final me = ref.watch(multiExposureProvider);
    final lens = ref.watch(filmLensProvider);
    ref.listen(multiExposureProvider, (was, now) {
      if (now.holding && !(was?.holding ?? false)) CameraNote.show('First exposure in. Now the second');
    });
    // the ring follows the lens when it moves by itself (a new stock starts
    // wide)
    if (!_dragging && _sim == null) _ring = z.canZoom ? math.log(_wide * z.level) : null;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final band = math.max(64.0, h * 0.3);
        final scaleTop = h * 0.24, scaleBottom = h - band - h * 0.06;
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _DialsPainter(
                    repaint: Listenable.merge([_paint, _zoomLit, _evLit, ViewfinderShutter.shut]),
                    ring: () => _ring,
                    zoom: z,
                    special: widget.spec.special,
                    lens: widget.spec.lenses.length > 1 ? lens : null,
                    me: me,
                    wide: _wide,
                    marks: _marks,
                    exposure: widget.spec.exposure,
                    ev: ev,
                    zoomLit: _zoomLit,
                    evLit: _evLit,
                    scaleTop: scaleTop,
                    scaleBottom: scaleBottom,
                  ),
                ),
              ),
            ),
            if (z.canZoom)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: band,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: _zoomStart,
                  onHorizontalDragUpdate: (d) => _zoomUpdate(d, w),
                  onHorizontalDragEnd: (d) => _zoomEnd(d, w),
                  onHorizontalDragCancel: () => _zoomEnd(DragEndDetails(), w),
                ),
              ),
            // the lens ring (top left) and its tray of caps
            if (widget.spec.lenses.length > 1) ...[
              Positioned(
                left: 4,
                top: 4,
                width: 52,
                height: 52,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    unawaited(Haptics.selectionClick());
                    setState(() => _tray = !_tray);
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 52,
                height: 74,
                child: IgnorePointer(
                  ignoring: !_tray,
                  child: AnimatedSlide(
                    offset: _tray ? Offset.zero : const Offset(0, -0.12),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _tray ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            for (final l in lensesFor(widget.spec, ref.watch(ultraWideProvider)))
                              _LensCap(
                                lens: l,
                                on: l == lens,
                                onTap: () {
                                  unawaited(Haptics.lightImpact());
                                  if (l != lens) LensChange.request(ref, l);
                                  CameraNote.show(l.label);
                                  Future<void>.delayed(const Duration(milliseconds: 180), () {
                                    if (mounted) setState(() => _tray = false);
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            // the button that changes per camera: its special, or blank
            Positioned(
              right: 4,
              top: 4,
              width: 52,
              height: 52,
              child: GestureDetector(
                behavior: widget.spec.special == null ? HitTestBehavior.translucent : HitTestBehavior.opaque,
                onTap: widget.spec.special == null ? null : _special,
              ),
            ),
            if (widget.spec.exposure != null)
              Positioned(
                right: 0,
                top: 0,
                bottom: band,
                width: math.max(56.0, w * 0.2),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: _evStart,
                  onVerticalDragUpdate: (d) => _evUpdate(d, scaleBottom - scaleTop),
                  onVerticalDragEnd: _evEnd,
                  onVerticalDragCancel: () => _evEnd(DragEndDetails()),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DialsPainter extends CustomPainter {
  _DialsPainter({
    required Listenable repaint,
    required this.ring,
    required this.zoom,
    required this.wide,
    required this.marks,
    required this.exposure,
    required this.ev,
    required this.zoomLit,
    required this.evLit,
    required this.scaleTop,
    required this.scaleBottom,
    required this.special,
    required this.me,
    required this.lens,
  }) : super(repaint: repaint);

  final double? Function() ring;
  final ZoomState zoom;
  final double wide;
  final List<double> Function(double lo, double hi) marks;
  final ExposureSpec? exposure;
  final double ev;
  final Animation<double> zoomLit, evLit;
  final double scaleTop, scaleBottom;
  final CameraSpecial? special;
  final MultiExposureState me;

  /// The lens on (null: the camera takes no other).
  final LensKind? lens;

  static const _ink = Color(0xFFF5EEE2);
  static const _amber = Color(0xFFE6A83F);
  static const _shade = Color(0xFF000000);

  // (text is laid out once per string)
  static final _texts = <String, TextPainter>{};
  static TextPainter _text(String s, double size, {bool bold = false}) => _texts.putIfAbsent(
    '$s|$size|$bold',
    () => TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: _ink,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          letterSpacing: 0.3,
          fontFeatures: const [FontFeature.tabularFigures()],
          shadows: const [Shadow(color: Color(0x99000000), blurRadius: 2, offset: Offset(0, 0.8))],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(),
  );

  /// Text centred at [c], at [alpha] (a small layer of its own when not
  /// opaque; inside a control's layer it's drawn straight).
  void _label(
    Canvas canvas,
    String s,
    Offset c,
    double size,
    double alpha, {
    double angle = 0,
    bool bold = false,
  }) {
    if (alpha <= 0.01) return;
    final tp = _text(s, size, bold: bold);
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(angle);
    final o = Offset(-tp.width / 2, -tp.height / 2);
    if (alpha < 0.99) {
      canvas.saveLayer((o & tp.size).inflate(3), Paint()..color = _ink.withValues(alpha: alpha));
      tp.paint(canvas, o);
      canvas.restore();
    } else {
      tp.paint(canvas, o);
    }
    canvas.restore();
  }

  void _stroke(Canvas canvas, Offset a, Offset b, double alpha, double width, {Color color = _ink}) {
    if (alpha <= 0.01) return;
    canvas.drawLine(
      a + const Offset(0, 0.7),
      b + const Offset(0, 0.7),
      Paint()
        ..color = _shade.withValues(alpha: alpha * 0.45)
        ..strokeWidth = width + 1.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // (gone while the viewfinder is shut)
    final shown = 1 - Curves.easeOut.transform(ViewfinderShutter.shut.value.clamp(0.0, 1.0));
    if (shown <= 0.01) return;
    final w = size.width, h = size.height;
    final zl = Curves.easeOut.transform(zoomLit.value), el = Curves.easeOut.transform(evLit.value);

    // ---- the zoom ring ----
    final r = ring();
    if (zoom.canZoom && r != null) {
      final lo = math.log(wide * zoom.min), hi = math.log(wide * math.max(zoom.min, zoom.max));
      if (zl > 0.01) {
        // a soft shade under the ring while it's in use
        final band = Rect.fromLTWH(0, h * 0.62, w, h * 0.38);
        canvas.drawRect(
          band,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _shade.withValues(alpha: 0),
                _shade.withValues(alpha: 0.42 * zl * shown),
              ],
            ).createShader(band),
        );
      }
      final a = (0.34 + 0.6 * zl) * shown;
      // (the ring as one layer at its brightness; inside, relative alphas)
      canvas.saveLayer(Rect.fromLTWH(0, h * 0.5, w, h * 0.5), Paint()..color = _ink.withValues(alpha: a));
      final radius = w * 1.35;
      final top = h - math.max(30.0, h * 0.11);
      final centre = Offset(w / 2, top + radius);
      // the lens's whole range over ~78% of the width
      final perLog = (w * 0.78 / radius) / math.max(0.05, hi - lo);
      final unit = (w / 360).clamp(0.85, 1.4);
      Offset on(double ang, double out) => centre + Offset(math.sin(ang), -math.cos(ang)) * (radius + out);
      final shown0 = math.exp(lo) * 0.7, shown1 = math.exp(hi) * 1.4;
      final step = (math.exp(hi) - math.exp(lo)) > 40 ? 5.0 : 1.0;
      final labelled = marks(math.exp(lo), math.exp(hi)).toSet()
        ..add(math.exp(lo).roundToDouble())
        ..add(math.exp(hi).roundToDouble());
      for (var m = (shown0 / step).ceil() * step; m <= shown1; m += step) {
        final ang = (math.log(m) - r) * perLog;
        final p = on(ang, 0);
        if (p.dx < -24 || p.dx > w + 24) continue;
        final inLens = m >= math.exp(lo) - 0.01 && m <= math.exp(hi) + 0.01;
        final big = labelled.contains(m);
        final ta = inLens ? 1.0 : 0.25;
        _stroke(canvas, p, on(ang, (big ? 11 : 5.5) * unit), ta, (big ? 1.4 : 1.0) * unit);
        if (big) {
          _label(canvas, m.round().toString(), on(ang, 21 * unit), 10.5 * unit, ta, angle: ang);
        }
      }
      // the ends of the lens
      for (final end in [lo, hi]) {
        final ang = (end - r) * perLog;
        final p = on(ang, -4 * unit);
        if (p.dx < -8 || p.dx > w + 8) continue;
        canvas.drawCircle(p, 2.3 * unit, Paint()..color = _amber);
      }
      // the notch the ring turns under
      final n = on(0, -6 * unit);
      final notch = Path()
        ..moveTo(n.dx, n.dy - 6 * unit)
        ..lineTo(n.dx - 5 * unit, n.dy + 2.5 * unit)
        ..lineTo(n.dx + 5 * unit, n.dy + 2.5 * unit)
        ..close();
      canvas
        ..drawPath(notch, Paint()..color = _amber)
        ..restore();
      // what it's at, while in use
      final mm = math.exp(r.clamp(lo, hi)).round();
      _label(canvas, '$mm mm', on(0, 44 * unit), 13 * unit, zl * shown, bold: true);
    }

    // ---- the lens ring (top left) ----
    if (lens case final l?) {
      final unit = (w / 360).clamp(0.85, 1.4);
      const c = Offset(30, 30);
      final rad = 14.5 * unit;
      final on = l != LensKind.standard;
      final a = (on ? 0.95 : 0.42) * shown;
      canvas.drawCircle(
        c,
        rad + 0.8,
        Paint()
          ..color = _shade.withValues(alpha: a * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );
      // a lens ring: two rims
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 1.8 : 1.3
        ..color = (on ? _amber : _ink).withValues(alpha: a);
      canvas
        ..drawCircle(c, rad, rim)
        ..drawCircle(c, rad - 3.5 * unit, rim..strokeWidth = 0.8);
      _label(canvas, l.mark, c, 7.5 * unit, a, bold: true);
    }

    // ---- the changing button (top right) ----
    {
      final unit = (w / 360).clamp(0.85, 1.4);
      final c = Offset(w - 30, 30);
      final rad = 14.5 * unit;
      final on = special != null && me.armed;
      final a = (special == null ? 0.22 : (on ? 0.95 : 0.42)) * shown;
      canvas.drawCircle(
        c,
        rad + 0.8,
        Paint()
          ..color = _shade.withValues(alpha: a * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = on ? 1.8 : 1.3
          ..color = (on ? _amber : _ink).withValues(alpha: a),
      );
      if (on && me.holding) {
        // the first exposure is in: the ring fills a little
        canvas.drawCircle(c, rad - 3, Paint()..color = _amber.withValues(alpha: 0.28 * shown));
      }
      if (special != null) _label(canvas, special!.mark, c, 10.5 * unit, a, bold: true);
    }

    // ---- the exposure scale ----
    final e = exposure;
    if (e != null) {
      if (el > 0.01) {
        final band = Rect.fromLTWH(w * 0.7, 0, w * 0.3, h);
        canvas.drawRect(
          band,
          Paint()
            ..shader = LinearGradient(
              colors: [
                _shade.withValues(alpha: 0),
                _shade.withValues(alpha: 0.4 * el * shown),
              ],
            ).createShader(band),
        );
      }
      final a = (0.32 + 0.6 * el) * shown;
      final unit = (w / 360).clamp(0.85, 1.4);
      final x = w - 14 * unit;
      canvas.saveLayer(Rect.fromLTWH(w * 0.6, 0, w * 0.4, h), Paint()..color = _ink.withValues(alpha: a));
      final steps = e.steps;
      double yOf(double v) => scaleBottom - (scaleBottom - scaleTop) * (v - e.min) / (e.max - e.min);
      for (var i = 0; i <= steps; i++) {
        final v = e.min + i * e.step;
        final whole = (v - v.roundToDouble()).abs() < 1e-6 || e.labels != null;
        final y = yOf(v);
        _stroke(canvas, Offset(x, y), Offset(x - (whole ? 10 : 5) * unit, y), 1, (whole ? 1.4 : 1.0) * unit);
        if (whole) {
          final s = e.labels != null ? e.labels![i] : (v > 0 ? '+${v.round()}' : '${v.round()}');
          _label(canvas, s, Offset(x - 20 * unit, y), 10 * unit, 1);
        }
      }
      // the pointer
      final y = yOf(ev);
      final p = Path()
        ..moveTo(x + 2 * unit, y)
        ..lineTo(x + 9 * unit, y - 5 * unit)
        ..lineTo(x + 9 * unit, y + 5 * unit)
        ..close();
      canvas
        ..drawPath(p, Paint()..color = _amber)
        ..restore();
      if (el > 0.01 && e.labels == null) {
        _label(canvas, _stops(ev), Offset(x - 50 * unit, y), 13 * unit, el * shown, bold: true);
      }
    }
  }

  /// +1⅓, −⅔, ±0
  static String _stops(double v) {
    if (v.abs() < 1e-6) return '±0';
    final sign = v > 0 ? '+' : '−';
    final a = v.abs(), whole = a.floor(), part = a - whole;
    final frac = (part - 1 / 3).abs() < 0.05
        ? '⅓'
        : (part - 2 / 3).abs() < 0.05
        ? '⅔'
        : (part - 0.5).abs() < 0.05
        ? '½'
        : '';
    return '$sign${whole == 0 && frac.isNotEmpty ? '' : whole}$frac';
  }

  @override
  bool shouldRepaint(_DialsPainter old) =>
      old.zoom != zoom ||
      old.me != me ||
      old.lens != lens ||
      old.special != special ||
      old.ev != ev ||
      old.exposure != exposure ||
      old.wide != wide;
}

/// A lens cap in the tray: dark glass in a rim, its name under it.
class _LensCap extends StatelessWidget {
  const _LensCap({required this.lens, required this.on, required this.onTap});

  final LensKind lens;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    label: '${lens.label} lens',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(42, 42),
              painter: _CapPainter(lens: lens, on: on),
            ),
            const SizedBox(height: 5),
            Text(
              lens.mark,
              style: TextStyle(
                color: on ? const Color(0xFFE6A83F) : const Color(0xE6F5EEE2),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 3)],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CapPainter extends CustomPainter {
  const _CapPainter({required this.lens, required this.on});

  final LensKind lens;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide / 2;
    // its barrel
    canvas.drawCircle(c, r, Paint()..color = const Color(0xF0151518));
    // the glass: tinted a little by what it is
    final tint = switch (lens) {
      LensKind.plastic => const Color(0xFF6B5A2A),
      LensKind.soft => const Color(0xFF7A6E66),
      LensKind.pinhole => const Color(0xFF111111),
      _ => const Color(0xFF3A4656),
    };
    final glass = Rect.fromCircle(center: c, radius: r - 5);
    canvas.drawCircle(
      c,
      r - 5,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(tint, const Color(0xFFFFFFFF), 0.35)!, tint, const Color(0xFF0A0B0D)],
          stops: const [0, 0.45, 1],
        ).createShader(glass),
    );
    if (lens == LensKind.pinhole) canvas.drawCircle(c, 1.6, Paint()..color = const Color(0xFFE8E2D6));
    if (lens == LensKind.fisheye) {
      canvas.drawCircle(c.translate(-3, -3), 4, Paint()..color = const Color(0x66FFFFFF));
    }
    // the rim
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 2.2 : 1.4
        ..color = on ? const Color(0xFFE6A83F) : const Color(0x80F5EEE2),
    );
  }

  @override
  bool shouldRepaint(_CapPainter old) => old.lens != lens || old.on != on;
}
