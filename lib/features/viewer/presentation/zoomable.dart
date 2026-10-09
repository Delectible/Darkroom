import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Swipe-between-photos viewer with its own touch handling, so zooming
/// always wins over paging (a pinch whose first finger slid sideways used
/// to start a swipe to the next photo instead):
///
/// - one finger, sideways: next / previous photo, once the move is clearly
///   sideways (zoomed in, it pans instead);
/// - one finger, up or down: the photo follows and is put away
///   ([onDismiss]) past a short distance or on a flick;
/// - two fingers: pinch zoom round the fingers (a second finger cancels a
///   swipe already under way);
/// - double tap: zoom in on that spot, again to zoom back out;
/// - double tap and slide: zoom gradually (down = in, up = out);
/// - a single tap (after the double-tap window): [onTap].
class PhotoPager extends StatefulWidget {
  const PhotoPager({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.onPageChanged,
    this.onTap,
    this.onDismiss,
    this.maxScale = 6,
    this.doubleTapScale = 2.5,
  });

  final PageController controller;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final ValueChanged<int>? onPageChanged;

  /// A single tap, with its global position.
  final ValueChanged<Offset>? onTap;
  final VoidCallback? onDismiss;
  final double maxScale;
  final double doubleTapScale;

  /// How far a finger moves before it counts as a swipe (more than the
  /// usual touch slop: room for the second finger of a pinch to land).
  static const swipeSlop = 24.0;
  static const doubleTapTime = Duration(milliseconds: 300);

  @override
  State<PhotoPager> createState() => PhotoPagerState();
}

enum _Mode { idle, page, dismiss, pan, pinch, quickZoom, done }

class PhotoPagerState extends State<PhotoPager> with SingleTickerProviderStateMixin {
  final _ptrs = <int, Offset>{};
  var _mode = _Mode.idle;
  Size _size = Size.zero;

  // The current photo's zoom: content point p shows at p * scale + offset.
  double _s = 1;
  Offset _o = Offset.zero;
  late int _index = widget.controller.initialPage;

  /// Scale of the current photo (tests).
  double get scale => _s;

  // Gesture baselines.
  double _s0 = 1, _d0 = 1;
  Offset _o0 = Offset.zero, _p0 = Offset.zero;
  Offset _down = Offset.zero, _downGlobal = Offset.zero, _last = Offset.zero;
  DateTime _downAt = DateTime(0);
  double _pix0 = 0;
  final _vt = <int, VelocityTracker>{};

  // Put-away drag.
  double _dy = 0;

  // Taps.
  DateTime? _tapUpAt;
  Offset _tapPos = Offset.zero;
  bool _second = false;
  Timer? _tapTimer;

  // Animation for zoom snaps and the put-away spring back.
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  double _fromS = 1, _toS = 1, _fromDy = 0;
  Offset _fromO = Offset.zero, _toO = Offset.zero;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      final t = Curves.easeOutCubic.transform(_anim.value);
      setState(() {
        _s = _fromS + (_toS - _fromS) * t;
        _o = Offset.lerp(_fromO, _toO, t)!;
        _dy = _fromDy * (1 - t);
      });
    });
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  bool get _zoomed => _s > 1.01;

  Offset _clamp(Offset o, double s) {
    if (s <= 1) return Offset((_size.width * (1 - s)) / 2, (_size.height * (1 - s)) / 2);
    return Offset(
      o.dx.clamp(_size.width * (1 - s), 0.0).toDouble(),
      o.dy.clamp(_size.height * (1 - s), 0.0).toDouble(),
    );
  }

  void _animateTo(double s, Offset o) {
    _fromS = _s;
    _fromO = _o;
    _fromDy = _dy;
    _toS = s;
    _toO = _clamp(o, s);
    unawaited(_anim.forward(from: 0));
  }

  /// Zoom to [s] keeping the content under [focal] there.
  void _zoomAround(Offset focal, double s, {required double s0, required Offset o0}) {
    final p = (focal - o0) / s0;
    _s = s;
    _o = s < 1 ? _clamp(Offset.zero, s) : _clamp(focal - p * s, s);
  }

  (Offset, double) _pinch() {
    final pts = _ptrs.values.take(2).toList();
    return ((pts[0] + pts[1]) / 2, math.max(1, (pts[0] - pts[1]).distance));
  }

  void _startPinch() {
    if (_mode == _Mode.page) _settlePage(0);
    if (_mode == _Mode.dismiss) _animateTo(_s, _o);
    _anim.stop();
    _dy = 0;
    _tapTimer?.cancel();
    _second = false;
    final (f, d) = _pinch();
    _mode = _Mode.pinch;
    _s0 = _s;
    _o0 = _o;
    _d0 = d;
    _p0 = f;
  }

  void _onDown(PointerDownEvent e) {
    _ptrs[e.pointer] = e.localPosition;
    _vt[e.pointer] = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.localPosition);
    if (_ptrs.length >= 2) {
      _startPinch();
      return;
    }
    _anim.stop();
    _mode = _Mode.idle;
    _down = _last = e.localPosition;
    _downGlobal = e.position;
    _downAt = DateTime.now();
    final at = _tapUpAt;
    _second =
        at != null &&
        DateTime.now().difference(at) < PhotoPager.doubleTapTime &&
        (e.localPosition - _tapPos).distance < 48;
    if (_second) _tapTimer?.cancel();
  }

  void _onMove(PointerMoveEvent e) {
    if (!_ptrs.containsKey(e.pointer)) return;
    _ptrs[e.pointer] = e.localPosition;
    _vt[e.pointer]?.addPosition(e.timeStamp, e.localPosition);
    switch (_mode) {
      case _Mode.pinch:
        if (_ptrs.length < 2) return;
        final (f, d) = _pinch();
        final s = (_s0 * d / _d0).clamp(0.8, widget.maxScale).toDouble();
        // Zoom round the start of the pinch, then follow the fingers' midpoint.
        setState(() {
          _zoomAround(_p0, s, s0: _s0, o0: _o0);
          if (s >= 1) _o = _clamp(_o + (f - _p0), s);
        });
      case _Mode.quickZoom:
        final dy = e.localPosition.dy - _down.dy;
        final s = (_s0 * math.exp(dy / 180)).clamp(0.8, widget.maxScale).toDouble();
        setState(() => _zoomAround(_down, s, s0: _s0, o0: _o0));
      case _Mode.pan:
        final delta = e.localPosition - _last;
        setState(() => _o = _clamp(_o + delta, _s));
      case _Mode.page:
        final p = widget.controller.position;
        p.jumpTo((_pix0 - (e.localPosition.dx - _down.dx)).clamp(p.minScrollExtent, p.maxScrollExtent));
      case _Mode.dismiss:
        setState(() => _dy = e.localPosition.dy - _down.dy);
      case _Mode.idle:
        final d = e.localPosition - _down;
        if (_second) {
          if (d.distance > 10) {
            _mode = _Mode.quickZoom;
            _s0 = _s;
            _o0 = _o;
          }
        } else if (_zoomed) {
          if (d.distance > 8) _mode = _Mode.pan;
        } else if (d.dx.abs() > PhotoPager.swipeSlop && d.dx.abs() > d.dy.abs() * 1.4) {
          _mode = widget.itemCount > 1 ? _Mode.page : _Mode.done;
          _pix0 = widget.controller.position.pixels;
          _down = e.localPosition; // no jump: start following from here
        } else if (d.dy.abs() > PhotoPager.swipeSlop &&
            d.dy.abs() > d.dx.abs() * 1.4 &&
            widget.onDismiss != null) {
          _mode = _Mode.dismiss;
          _down = e.localPosition;
        }
      case _Mode.done:
        break;
    }
    _last = e.localPosition;
  }

  void _onUp(PointerEvent e, {bool cancelled = false}) {
    if (!_ptrs.containsKey(e.pointer)) return;
    final v = _vt.remove(e.pointer)?.getVelocity().pixelsPerSecond ?? Offset.zero;
    _ptrs.remove(e.pointer);
    if (_ptrs.length >= 2) {
      _startPinch(); // re-baseline on the remaining two
      return;
    }
    if (_ptrs.length == 1) {
      // A pinch down to one finger: pan from here when zoomed.
      if (_mode == _Mode.pinch) {
        _mode = _zoomed ? _Mode.pan : _Mode.done;
        _last = _down = _ptrs.values.first;
        if (!_zoomed) _animateTo(1, Offset.zero);
      }
      return;
    }
    switch (_mode) {
      case _Mode.pinch || _Mode.quickZoom || _Mode.pan:
        if (_s < 1) _animateTo(1, Offset.zero);
        _second = false;
        _tapUpAt = null;
      case _Mode.page:
        _settlePage(cancelled ? 0 : v.dx);
      case _Mode.dismiss:
        if (!cancelled && (_dy.abs() > _size.height * 0.16 || v.dy.abs() > 900)) {
          widget.onDismiss?.call();
        } else {
          _animateTo(_s, _o);
        }
      case _Mode.idle:
        if (cancelled) break;
        final quick = DateTime.now().difference(_downAt) < const Duration(milliseconds: 400);
        if (_second) {
          // Double tap: in on that spot, or back out.
          if (_zoomed) {
            _animateTo(1, Offset.zero);
          } else {
            final s = widget.doubleTapScale;
            final p = (_down - _o) / _s;
            _animateTo(s, _down - p * s);
          }
          _second = false;
          _tapUpAt = null;
        } else if (quick) {
          _tapUpAt = DateTime.now();
          _tapPos = _down;
          final at = _downGlobal;
          _tapTimer?.cancel();
          if (widget.onTap != null) {
            _tapTimer = Timer(PhotoPager.doubleTapTime, () {
              if (mounted) widget.onTap!(at);
            });
          }
        }
      case _Mode.done:
        break;
    }
    _mode = _Mode.idle;
  }

  void _settlePage(double vx) {
    final p = widget.controller.position;
    final page = widget.controller.page ?? _index.toDouble();
    var target = page.round();
    if (vx < -400) target = page.floor() + 1;
    if (vx > 400) target = page.ceil() - 1;
    target = target.clamp(0, widget.itemCount - 1);
    if (!p.hasPixels) return;
    unawaited(
      widget.controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = _size.height == 0 ? 1.0 : _size.height;
    final away = (_dy.abs() / h).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, c) {
        _size = c.biggest;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: (e) => _onUp(e, cancelled: true),
          child: Transform.translate(
            offset: Offset(0, _dy),
            child: Transform.scale(
              scale: 1 - away * 0.25,
              child: Opacity(
                opacity: (1 - away * 1.2).clamp(0.0, 1.0),
                child: PageView.builder(
                  controller: widget.controller,
                  itemCount: widget.itemCount,
                  // All touch handling is ours (above).
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) {
                    setState(() {
                      _index = i;
                      _anim.stop();
                      _s = 1;
                      _o = Offset.zero;
                    });
                    widget.onPageChanged?.call(i);
                  },
                  // Same widgets zoomed or not (the photo isn't rebuilt).
                  itemBuilder: (context, i) => ClipRect(
                    child: Transform(
                      transform: i != _index
                          ? Matrix4.identity()
                          : (Matrix4.identity()
                              ..translateByDouble(_o.dx, _o.dy, 0, 1)
                              ..scaleByDouble(_s, _s, 1, 1)),
                      child: widget.itemBuilder(context, i),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
