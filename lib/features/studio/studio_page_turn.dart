import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Pages you turn like paper: drag and the page folds back along a line
/// under your finger, its back showing, shadows in the fold and on the page
/// beneath. The page stays bound at the spine (its corner can only go where
/// a real page could), and lies over to the left page when it goes over.
/// Let go past halfway (or flick) and it goes over; else it falls back.
/// [PageTurnState.next] / [PageTurnState.previous] turn one for you, and
/// taps faster than a turn queue up (the turns speed up to catch up).
///
/// It draws past its own box on the left (the left page, where a turned
/// page lands), so its parent must not clip there.
class PageTurn extends StatefulWidget {
  const PageTurn({
    super.key,
    required this.count,
    required this.page,
    required this.builder,
    required this.back,
    required this.onPage,
    this.left,
  });

  /// The left-hand page facing [page] (drawn a page's width to the left,
  /// beneath anything turning over onto it); null: none.
  final Widget Function(BuildContext context, int page)? left;

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
  late final AnimationController _t = AnimationController(vsync: this)..addListener(() => setState(() {}));

  bool? _forward; // turning: forward (this page over) or back (the last one back)
  bool _bottom = true; // the corner taken: bottom or top
  Offset _start = Offset.zero;
  Offset _at = Offset.zero; // where the corner is now (dragging)
  Offset _from = Offset.zero, _to = Offset.zero; // the animation's ends
  bool _arc = false; // an auto turn: the corner lifts as it goes
  int _queued = 0; // turns asked for while one was running (+ forward, - back)
  Size _size = Size.zero;

  // Each page keeps its widgets as it moves between lying flat, turning
  // and lying beneath (no reloads, no flashed frames).
  final _keys = <int, GlobalKey>{};

  bool get turning => _forward != null;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  Widget _page(BuildContext context, int i) =>
      KeyedSubtree(key: _keys.putIfAbsent(i, GlobalKey.new), child: widget.builder(context, i));

  /// Turns to the next page, if there is one (queued if a turn's running).
  void next() => _ask(1);

  void previous() => _ask(-1);

  void _ask(int dir) {
    if (turning) {
      // (not past the last page or the first)
      final landing = widget.page + (_forward! ? 1 : -1) + _queued + dir;
      if (landing >= 0 && landing < widget.count) _queued += dir;
      return;
    }
    _auto(dir > 0, fast: false);
  }

  void _auto(bool forward, {required bool fast}) {
    if (forward ? widget.page >= widget.count - 1 : widget.page <= 0) return;
    final w = _size.width, h = _size.height;
    setState(() {
      _forward = forward;
      _bottom = true;
      _arc = true;
      _from = Offset(forward ? w : -w, h);
      _to = Offset(forward ? -w : w, h);
      _at = _from;
    });
    _run(Duration(milliseconds: fast ? 300 : 640));
  }

  void _dragStart(DragStartDetails d) {
    if (turning) return;
    _start = d.localPosition;
    _t.value = 0;
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_t.isAnimating || _size.isEmpty) return;
    final w = _size.width, h = _size.height;
    final move = d.localPosition - _start;
    if (_forward == null) {
      if (move.dx.abs() < 4) return;
      final forward = move.dx < 0;
      if (forward ? widget.page >= widget.count - 1 : widget.page <= 0) return;
      _bottom = _start.dy > h / 2;
      _forward = forward;
      _arc = false;
    }
    // the corner follows the finger (twice as far across: a short drag
    // turns a page), held to where a bound page can reach
    final cy = _bottom ? h : 0.0;
    final base = Offset(_forward! ? w : -w, cy);
    setState(() => _at = _bind(base + Offset(move.dx * 2, move.dy * 0.8)));
  }

  void _dragEnd(DragEndDetails d) {
    if (_forward == null || _t.isAnimating) return;
    final v = d.velocity.pixelsPerSecond.dx;
    final w = _size.width, h = _size.height;
    final over = _forward! ? (_at.dx < 0 || v < -500) && v < 300 : (_at.dx > 0 || v > 500) && v > -300;
    final goLeft = _forward! == over;
    final cy = _bottom ? h : 0.0;
    _from = _at;
    _to = Offset(goLeft ? -w : w, cy);
    _arc = false;
    final dist = (_to - _from).distance / (2 * w);
    _run(Duration(milliseconds: (140 + 300 * dist).round()));
  }

  void _run(Duration time) {
    _t
      ..duration = time
      ..value = 0;
    _t.animateTo(1, curve: Curves.easeInOutCubic).whenComplete(() {
      if (!mounted) return;
      final f = _forward;
      final landedLeft = _to.dx < 0;
      // The new page first, then the turn ends, in the same frame: never a
      // frame of the old page flat.
      if (f == true && landedLeft) widget.onPage(widget.page + 1);
      if (f == false && !landedLeft) widget.onPage(widget.page - 1);
      setState(() => _forward = null);
      if (_queued != 0) {
        final dir = _queued > 0;
        _queued += dir ? -1 : 1;
        // (after the parent has the new page)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !turning) _auto(dir, fast: true);
        });
      }
    });
  }

  /// [p] held to where the corner of a page bound at the spine can go: no
  /// further from the spine's near end than the page is wide, nor from its
  /// far end than the page's diagonal.
  Offset _bind(Offset p) {
    final w = _size.width, h = _size.height;
    final cy = _bottom ? h : 0.0;
    final near = Offset(0, cy), far = Offset(0, h - cy);
    var q = p;
    final dn = q - near;
    if (dn.distance > w) q = near + dn * (w / dn.distance);
    final diag = math.sqrt(w * w + h * h);
    final df = q - far;
    if (df.distance > diag) q = far + df * (diag / df.distance);
    return q;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _size = box.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _dragStart,
          onHorizontalDragUpdate: _dragUpdate,
          onHorizontalDragEnd: _dragEnd,
          child: _forward == null ? _flat(context) : _turning(context, _size),
        );
      },
    );
  }

  /// The left page facing [page], where it lies.
  Widget _leftOf(BuildContext context, int page) => Positioned(
    left: -_size.width,
    width: _size.width,
    top: 0,
    bottom: 0,
    child: widget.left!(context, page),
  );

  Widget _flat(BuildContext context) => widget.left == null
      ? _page(context, widget.page)
      : Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [_leftOf(context, widget.page), _page(context, widget.page)],
        );

  Widget _turning(BuildContext context, Size size) {
    final forward = _forward!;
    final top = forward ? widget.page : widget.page - 1; // the page that turns
    final under = forward ? widget.page + 1 : widget.page;
    final h = size.height;
    var corner = _at;
    if (_t.isAnimating || _t.value > 0) {
      final e = _t.value;
      corner = Offset.lerp(_from, _to, e)!;
      if (_arc) {
        // the corner lifts off the page and comes down on the other side
        corner = corner + Offset(0, (_bottom ? -1 : 1) * h * 0.1 * math.sin(math.pi * e));
      }
      corner = _bind(corner);
    }
    final fold = _Fold(Offset(size.width, _bottom ? h : 0), corner, size);
    if (fold.flat) return _page(context, top);
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        // (beneath a page coming back: the left page before it)
        if (widget.left != null) _leftOf(context, forward ? widget.page : widget.page - 1),
        _page(context, under),
        CustomPaint(painter: _Shade(fold, _ShadeKind.under)),
        ClipPath(clipper: _PolyClip(fold.kept), child: _page(context, top)),
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
        // the flap's own shadow on the page it lies over (and the left page)
        canvas.clipPath(
          Path.combine(
            PathOperation.difference,
            Path()..addRect(Rect.fromLTRB(-size.width, -size.height, size.width, size.height * 2)),
            Path()..addPolygon(f.folded, true),
          ),
        );
        canvas.drawPath(
          Path()..addPolygon([for (final q in f.mirrored) q - f.n * 4], true),
          Paint()
            ..color = const Color(0x55000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
        // and the page darkening into the fold
        canvas.save();
        canvas.clipPath(Path()..addPolygon(f.kept, true));
        canvas.drawRect(
          Offset.zero & size,
          Paint()..shader = _along(f.mid, f.mid - f.n * 26, const [Color(0x22000000), Color(0x00000000)]),
        );
        canvas.restore();
      case _ShadeKind.flapGloss:
        // the turned paper: shaded at the crease, catching the light across
        canvas.clipPath(Path()..addPolygon(f.mirrored, true));
        final w = math.max(reach, 1.0);
        canvas.drawRect(
          Rect.fromLTRB(-size.width, -size.height, size.width, size.height * 2),
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
