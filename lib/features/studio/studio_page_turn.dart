import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Pages you turn like paper: drag from anywhere and the page folds back
/// along a line under your finger, its back showing, a shadow in the fold
/// and on the page beneath. Let go past halfway (or flick) and it goes
/// over; else it falls back. [PageTurnState.next] / [PageTurnState.previous]
/// turn one for you.
class PageTurn extends StatefulWidget {
  const PageTurn({
    super.key,
    required this.count,
    required this.page,
    required this.builder,
    required this.back,
    required this.onPage,
  });

  final int count;
  final int page;
  final Widget Function(BuildContext context, int page) builder;

  /// The back of a page (plain paper).
  final Widget back;
  final ValueChanged<int> onPage;

  @override
  State<PageTurn> createState() => PageTurnState();
}

class PageTurnState extends State<PageTurn> with SingleTickerProviderStateMixin {
  // p: where the turning page's corner is, in page widths: 1 flat, -1 over
  late final AnimationController _p = AnimationController(
    vsync: this,
    lowerBound: -1,
    upperBound: 1,
    value: 1,
  )..addListener(() => setState(() {}));

  bool? _forward; // turning: forward (this page over) or back (the last one back)
  bool _bottom = true; // the corner taken: bottom or top
  Offset _start = Offset.zero;
  double _drift = 0, _driftAt = 0; // the finger's up/down, eased out on release
  double _p0 = 1;

  bool get turning => _forward != null;

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  /// Turns to the next page, if there is one.
  void next() => _auto(true);

  void previous() => _auto(false);

  void _auto(bool forward) {
    if (turning) return;
    if (forward ? widget.page >= widget.count - 1 : widget.page <= 0) return;
    setState(() {
      _forward = forward;
      _bottom = true;
      _drift = 0;
      _p.value = forward ? 1 : -1;
    });
    _finish(forward ? -1 : 1, const Duration(milliseconds: 650));
  }

  void _dragStart(DragStartDetails d) {
    if (turning) return;
    _start = d.localPosition;
    _forward = null;
  }

  void _dragUpdate(DragUpdateDetails d, Size size) {
    if (_p.isAnimating) return;
    final dx = d.localPosition.dx - _start.dx;
    if (_forward == null) {
      if (dx.abs() < 4) return;
      final forward = dx < 0;
      if (forward ? widget.page >= widget.count - 1 : widget.page <= 0) return;
      _forward = forward;
      _bottom = _start.dy > size.height / 2;
    }
    final p = (_forward! ? 1 + 2 * dx / size.width : -1 + 2 * dx / size.width).clamp(-1.0, 1.0);
    _drift = (d.localPosition.dy - _start.dy) * 0.4;
    _p.value = p;
  }

  void _dragEnd(DragEndDetails d, Size size) {
    if (_forward == null || _p.isAnimating) return;
    final v = d.velocity.pixelsPerSecond.dx;
    final p = _p.value;
    final over = _forward! ? (p < 0.1 || v < -500) && v < 300 : (p > -0.1 || v > 500) && v > -300;
    final target = _forward! == over ? -1.0 : 1.0;
    _finish(target, Duration(milliseconds: (120 + 260 * (target - p).abs() / 2).round()));
  }

  void _finish(double target, Duration time) {
    _p0 = _p.value;
    _driftAt = _drift;
    _p.animateTo(target, duration: time, curve: Curves.easeOutCubic).whenComplete(() {
      if (!mounted) return;
      final f = _forward;
      setState(() {
        _forward = null;
        _p.value = 1;
      });
      // (landed over: forward, the next page; back, the last)
      if (f == true && target < 0) widget.onPage(widget.page + 1);
      if (f == false && target > 0) widget.onPage(widget.page - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        return GestureDetector(
          onHorizontalDragStart: _dragStart,
          onHorizontalDragUpdate: (d) => _dragUpdate(d, size),
          onHorizontalDragEnd: (d) => _dragEnd(d, size),
          child: _forward == null ? widget.builder(context, widget.page) : _turning(context, size),
        );
      },
    );
  }

  Widget _turning(BuildContext context, Size size) {
    final forward = _forward!;
    final top = forward ? widget.page : widget.page - 1; // the page that turns
    final under = forward ? widget.page + 1 : widget.page;
    final p = _p.value;
    final w = size.width, h = size.height;
    // the corner, and where it's been brought to: a curl lifts it a little
    final corner = Offset(w, _bottom ? h : 0);
    final settled = _p.isAnimating && (_p0 - _p.value).abs() > 0 ? 1 - (p - _p0).abs() / 2 : 1.0;
    final drift = _p.isAnimating ? _driftAt * settled.clamp(0.0, 1.0) : _drift;
    final lift = (_bottom ? -1 : 1) * h * 0.09 * math.sin(math.pi * (1 - p) / 2) + drift;
    final fold = _Fold(corner, Offset(p * w, corner.dy + lift), size);
    if (fold.flat) return widget.builder(context, top);
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        widget.builder(context, under),
        CustomPaint(painter: _Shade(fold, _ShadeKind.under)),
        ClipPath(clipper: _PolyClip(fold.kept), child: widget.builder(context, top)),
        CustomPaint(painter: _Shade(fold, _ShadeKind.flapShadow)),
        Transform(
          transform: fold.mirror,
          child: ClipPath(clipper: _PolyClip(fold.folded), child: widget.back),
        ),
        CustomPaint(painter: _Shade(fold, _ShadeKind.flapGloss)),
      ],
    );
  }
}

/// The fold: the line halfway between the page's corner and where it's
/// been brought to; the part beyond it turns over (mirrored across it).
class _Fold {
  _Fold(Offset corner, Offset to, this.size) : mid = (corner + to) / 2 {
    final d = corner - to;
    final len = d.distance;
    flat = len < 1;
    n = flat ? const Offset(1, 0) : d / len;
    final page = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    kept = _cut(page, false);
    folded = _cut(page, true);
    mirrored = [for (final q in folded) reflect(q)];
  }

  final Size size;
  final Offset mid;
  late final bool flat;
  late final Offset n; // from the fold towards the corner
  late final List<Offset> kept, folded, mirrored;

  double side(Offset q) => (q.dx - mid.dx) * n.dx + (q.dy - mid.dy) * n.dy;

  Offset reflect(Offset q) => q - n * (2 * side(q));

  /// The flap's place: the page mirrored across the fold.
  Matrix4 get mirror {
    final a = 1 - 2 * n.dx * n.dx, d = 1 - 2 * n.dy * n.dy, b = -2 * n.dx * n.dy;
    final t = n * (2 * (mid.dx * n.dx + mid.dy * n.dy));
    return Matrix4(a, b, 0, 0, b, d, 0, 0, 0, 0, 1, 0, t.dx, t.dy, 0, 1);
  }

  // The page cut by the fold: the corner's side or the other.
  List<Offset> _cut(List<Offset> poly, bool cornerSide) {
    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final sa = side(a) * (cornerSide ? 1 : -1), sb = side(b) * (cornerSide ? 1 : -1);
      if (sa >= 0) out.add(a);
      if ((sa >= 0) != (sb >= 0)) out.add(Offset.lerp(a, b, sa / (sa - sb))!);
    }
    return out;
  }
}

class _PolyClip extends CustomClipper<Path> {
  const _PolyClip(this.poly);

  final List<Offset> poly;

  @override
  Path getClip(Size size) => poly.length < 3 ? Path() : (Path()..addPolygon(poly, true));

  @override
  bool shouldReclip(_PolyClip old) => true;
}

enum _ShadeKind { under, flapShadow, flapGloss }

class _Shade extends CustomPainter {
  const _Shade(this.fold, this.kind);

  final _Fold fold;
  final _ShadeKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final f = fold;
    if (f.folded.length < 3) return;
    // how far the flap reaches past the fold
    final reach = f.folded.fold<double>(0, (m, q) => math.max(m, f.side(q)));
    switch (kind) {
      case _ShadeKind.under:
        // the page beneath, dark in the fold's shadow
        final w = (reach * 0.5).clamp(8.0, 60.0);
        canvas.clipPath(Path()..addPolygon(f.folded, true));
        canvas.drawRect(
          Offset.zero & size,
          Paint()..shader = _along(f.mid, f.mid + f.n * w, const [Color(0x66000000), Color(0x00000000)]),
        );
      case _ShadeKind.flapShadow:
        // the flap's own shadow on the page it lies over
        canvas.clipPath(Path()..addPolygon(f.kept, true));
        canvas.drawPath(
          Path()..addPolygon([for (final q in f.mirrored) q - f.n * 4], true),
          Paint()
            ..color = const Color(0x55000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
        // and the page darkening into the fold
        canvas.drawRect(
          Offset.zero & size,
          Paint()..shader = _along(f.mid, f.mid - f.n * 26, const [Color(0x22000000), Color(0x00000000)]),
        );
      case _ShadeKind.flapGloss:
        // the turned paper: shaded at the crease, catching the light across
        canvas.clipPath(Path()..addPolygon(f.mirrored, true));
        final w = math.max(reach, 1.0);
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = _along(
              f.mid,
              f.mid - f.n * w,
              const [Color(0x30000000), Color(0x10FFFFFF), Color(0x00FFFFFF), Color(0x1A000000)],
              const [0, 0.25, 0.7, 1],
            ),
        );
    }
  }

  Shader _along(Offset from, Offset to, List<Color> colors, [List<double>? stops]) =>
      ui.Gradient.linear(from, to, colors, stops);

  @override
  bool shouldRepaint(_Shade old) => true;
}
