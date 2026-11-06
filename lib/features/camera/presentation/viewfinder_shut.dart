import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../core/theme/retro_theme.dart';
import '../../cameras/domain/camera_spec.dart';

/// While the camera is off (a swipe, Settings, the picker) the viewfinder
/// shuts instead of holding a still of itself:
///
/// * film: the mirror goes up. The picture darkens from the edges to the
///   viewfinder's black, leaving the focusing screen's etched circle and
///   split line faintly lit.
/// * digital: the LCD sleeps. The picture breaks into ever bigger pixels
///   as its backlight goes, down to the dark of an unlit screen.
///
/// Opening, over the live picture again: the darkness draws back to the
/// edges (film) / the backlight comes on (digital).
///
/// Cheap: a still (while closing), a gradient and a few strokes; shut, a
/// flat colour. The pixel steps are a handful of tiny pictures made once
/// per still on the GPU.
class ViewfinderShutter {
  ViewfinderShutter._();

  /// 0 = open (live), 1 = shut. Driven by the camera screen: it closes
  /// when the camera's picture is stopped and held ([CameraViewport.freeze]
  /// without the live picture under it) and opens when it's live again.
  static Animation<double> shut = kAlwaysDismissedAnimation;

  /// The camera's picture isn't live yet (starting up, restarting): the
  /// shutter button says so ([noteOff]) instead of firing.
  static bool cameraOff = false;
  static VoidCallback? noteOff;

  /// Digital, waking: a still of the first live picture, pixelated as the
  /// LCD comes on (the live picture itself can't be, cheaply).
  static final waking = ValueNotifier<ui.Image?>(null);

  /// The film focusing screen's marks are sized from this (the viewfinder's
  /// short side as the video cameras' taller picture leaves it), so they
  /// keep one size whichever camera's picture is behind them. Set by the
  /// viewport from the space it has; null: the box's own short side.
  static double? markSide;

  /// How long closing and opening take.
  static const close = Duration(milliseconds: 320);
  static const open = Duration(milliseconds: 280);
}

/// The viewfinder of a [mode] camera: [still] (the picture as it stopped,
/// if any) shutting as [ViewfinderShutter.shut] says, or at a fixed
/// [progress] (1: a camera not in hand, shut).
class ViewfinderShut extends StatefulWidget {
  const ViewfinderShut({
    super.key,
    required this.mode,
    required this.still,
    this.progress,
    this.marks = true,
  });

  final AppMode mode;

  /// Film: the focusing screen's marks.
  final bool marks;
  final ui.Image? still;
  final double? progress;

  @override
  State<ViewfinderShut> createState() => _ViewfinderShutState();
}

class _ViewfinderShutState extends State<ViewfinderShut> {
  final _pixels = _PixelSteps();

  @override
  void didUpdateWidget(ViewfinderShut old) {
    super.didUpdateWidget(old);
    if (old.still != widget.still) _pixels.clear();
  }

  @override
  void dispose() {
    _pixels.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.ofBody(context, widget.mode);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ShutPainter(
            film: widget.mode == AppMode.film,
            marks: widget.marks,
            still: widget.still,
            fixed: widget.progress,
            shut: ViewfinderShutter.shut,
            screen: p.screen,
            ink: p.screenInk,
            pixels: _pixels,
            markSide: ViewfinderShutter.markSide,
          ),
        ),
      ),
    );
  }
}

/// The still at a few pixel sizes (columns across), made as needed.
class _PixelSteps {
  static const columns = [96, 56, 34, 22, 15];
  final Map<int, ui.Image> _made = {};
  ui.Image? _of;

  ui.Image step(ui.Image still, int i) {
    if (_of != still) clear();
    _of = still;
    return _made[i] ??= () {
      final cols = columns[i];
      final rows = (cols * still.height / still.width).round().clamp(1, 4096);
      final rec = ui.PictureRecorder();
      Canvas(rec).drawImageRect(
        still,
        Rect.fromLTWH(0, 0, still.width.toDouble(), still.height.toDouble()),
        Rect.fromLTWH(0, 0, cols.toDouble(), rows.toDouble()),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final picture = rec.endRecording();
      final image = picture.toImageSync(cols, rows);
      picture.dispose();
      return image;
    }();
  }

  void clear() {
    for (final i in _made.values) {
      i.dispose();
    }
    _made.clear();
    _of = null;
  }
}

class _ShutPainter extends CustomPainter {
  _ShutPainter({
    required this.film,
    required this.marks,
    required this.still,
    required this.fixed,
    required this.shut,
    required this.screen,
    required this.ink,
    required this.pixels,
    this.markSide,
  }) : super(repaint: fixed == null ? shut : null);

  final bool film, marks;
  final ui.Image? still;
  final double? fixed;
  final Animation<double> shut;
  final Color screen, ink;
  final _PixelSteps pixels;
  final double? markSide;

  static double _c(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final raw = fixed ?? shut.value;
    final opening = fixed == null && shut.status == AnimationStatus.reverse;
    final p = Curves.easeInOut.transform(_c(raw));
    final still = this.still;
    if (p >= 1) {
      // Shut: no picture under it to draw.
      canvas.drawRect(rect, Paint()..color = screen.withValues(alpha: 1));
      if (film && marks) _marks(canvas, rect);
      if (!film) _glass(canvas, rect, 1);
      return;
    }
    if (film) {
      if (still != null) _picture(canvas, rect, still, FilterQuality.low);
      if (p <= 0) {
        if (marks) _marks(canvas, rect);
        return;
      }
      // The mirror going up: dark from the edges in, then all of it.
      final reach = rect.longestSide / rect.shortestSide * 0.62;
      final inner = (1 - p) * 0.9;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: reach,
            colors: [
              screen.withValues(alpha: 0),
              screen.withValues(alpha: _c(p * 2)),
            ],
            stops: [inner, _c(inner + 0.45)],
          ).createShader(rect),
      );
      canvas.drawRect(rect, Paint()..color = screen.withValues(alpha: _c(p * 1.2 - 0.2)));
      if (marks) _marks(canvas, rect);
      return;
    }
    // The LCD sleeping: bigger pixels as the backlight goes, over the still
    // it stopped on; waking, the same backwards over a still of the first
    // live picture ([ViewfinderShutter.waking]), which fades into the live
    // one at the end.
    if (still != null) {
      final n = _PixelSteps.columns.length;
      final i = ((p - 0.08) / 0.7 * n).floor();
      if (i < 0 && opening) {
        paintImage(
          canvas: canvas,
          rect: rect,
          image: still,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          opacity: _c(p / 0.08),
        );
      } else if (i < 0) {
        _picture(canvas, rect, still, FilterQuality.low);
      } else {
        _picture(canvas, rect, pixels.step(still, i.clamp(0, n - 1)), FilterQuality.none);
      }
    }
    if (p <= 0) return;
    // (slow at first, so the big pixels show before it goes dark)
    canvas.drawRect(rect, Paint()..color = screen.withValues(alpha: _c(p * p * 1.3)));
    _glass(canvas, rect, p);
  }

  static void _picture(Canvas canvas, Rect rect, ui.Image image, FilterQuality q) =>
      paintImage(canvas: canvas, rect: rect, image: image, fit: BoxFit.cover, filterQuality: q);

  /// The focusing screen's etched circle and split-image line.
  /// The focusing screen's etched circle and split-image line, always there
  /// on film (live or shut): a light line with a faint dark edge, so it
  /// reads on a bright sky and on the dark alike.
  void _marks(Canvas canvas, Rect rect) {
    final c = rect.center, s = markSide ?? rect.shortestSide;
    void etch(Paint paint, Offset o) => canvas
      ..drawCircle(c + o, s * 0.17, paint)
      ..drawCircle(c + o, s * 0.065, paint)
      ..drawLine(c + o - Offset(s * 0.065, 0), c + o + Offset(s * 0.065, 0), paint);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    etch(paint..color = const Color(0x2E000000), const Offset(0, 1));
    etch(paint..color = ink.withValues(alpha: 0.3), Offset.zero);
  }

  /// An unlit LCD's glass: a faint sheen from the top left.
  void _glass(Canvas canvas, Rect rect, double p) {
    final a = 0.06 * _c((p - 0.5) * 2);
    if (a <= 0) return;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ink.withValues(alpha: a),
            ink.withValues(alpha: 0),
          ],
          stops: const [0, 0.55],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ShutPainter old) =>
      old.film != film ||
      old.marks != marks ||
      old.still != still ||
      old.fixed != fixed ||
      old.shut != shut ||
      old.screen != screen ||
      old.markSide != markSide ||
      old.ink != ink;
}
