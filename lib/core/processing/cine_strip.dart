import 'dart:math' as math;

import 'crop_math.dart';

/// Layout of a full-gate Super 8 scan, the way reels are digitised today:
/// the picture, a black edge down the left with the sprocket hole, a thin
/// edge on the right, and slivers of the previous / next frames above and
/// below, across thin frame lines.
///
/// All values are fractions of the canvas (width for x, height for y) in the
/// viewer's upright frame. One source for the live viewfinder (film.frag),
/// the viewport mask and the exported reel (VideoFilters.filmGraph).
class CineStrip {
  const CineStrip._();

  /// Black film edge on the left (holds the sprocket hole).
  static const left = 0.16;

  /// Thin black edge on the right.
  static const right = 0.035;

  /// How much of the neighbouring frames shows above and below.
  static const sliver = 0.05;

  /// Frame line between frames.
  static const gap = 0.014;

  static const picX = left;
  static const picW = 1 - left - right;
  static const picY = sliver + gap;
  static const picH = 1 - 2 * (sliver + gap);

  /// Sprocket hole: just left of the picture, centred on it.
  static const holeW = 0.115;
  static const holeH = 0.25;
  static const holeX = left - holeW - 0.008;
  static const holeY = 0.5 - holeH / 2;

  /// Corner radius of the hole, as a fraction of the canvas height.
  static const holeRadius = 0.035;

  /// Corner radius of each frame, as a fraction of the canvas height.
  static const frameRadius = 0.02;

  /// Canvas width / height for a picture of aspect [pictureAspect] (w / h).
  static double canvasAspect(double pictureAspect) => pictureAspect * picH / picW;

  /// Canvas size in pixels around a [picW]x[picH] picture (even numbers).
  static (int, int) canvasSize(int pictureW, int pictureH) {
    int even(double v) => (v.round() ~/ 2) * 2;
    return (even(pictureW / picW), even(pictureH / picH));
  }

  /// The canvas inside a portrait preview box of width 1 and height
  /// [boxAspect] (>= 1), normalised to the box. Upright, the canvas is
  /// landscape across the box; held sideways ([turns] odd), it runs down it.
  static UnitRect previewCanvas({
    required double boxAspect,
    required int turns,
    double pictureAspect = 4 / 3,
  }) {
    final ca = canvasAspect(pictureAspect);
    final ap = boxAspect >= 1 ? boxAspect : 1 / boxAspect;
    if (turns.isEven) {
      // Landscape across the box: full width, or limited by height.
      final w = math.min(1.0, ap * ca);
      final h = w / ca / ap;
      return UnitRect((1 - w) / 2, (1 - h) / 2, w, h);
    }
    // Long side down the box.
    final hBox = math.min(ap, ca); // in box-width units
    final w = hBox / ca;
    final h = hBox / ap;
    return UnitRect((1 - w) / 2, (1 - h) / 2, w, h);
  }
}

/// One pixel of the strip at canvas uv ([u], [v]): coverage (0 where a frame
/// shows through, 1 on the film edge / frame lines) and its colour. Mirrored
/// line for line by `stripColor` in shaders/film.frag.
class CineStripPixel {
  const CineStripPixel._();

  static const base = (18, 12, 10);
  static const rim = (255, 192, 125);
  static const edgeLine = (62, 74, 104);

  static double _box(double x, double y, double cx, double cy, double hx, double hy, double r) {
    final qx = (x - cx).abs() - hx + r, qy = (y - cy).abs() - hy + r;
    final ox = math.max(qx, 0.0), oy = math.max(qy, 0.0);
    return math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0.0) - r;
  }

  /// [aspect] = canvas w / h; [px] = one pixel in canvas-height units.
  static (double, int, int, int) at(
    double u,
    double v,
    double aspect,
    double px,
    double Function(double, double, double) smooth,
  ) {
    final x = u * aspect, y = v;
    // Nearest frame (previous, this one, next).
    const pitch = CineStrip.picH + CineStrip.gap;
    final k = ((y - CineStrip.picY - CineStrip.picH / 2) / pitch).round().clamp(-1, 1);
    final frame = _box(
      x,
      y,
      (CineStrip.picX + CineStrip.picW / 2) * aspect,
      CineStrip.picY + CineStrip.picH / 2 + k * pitch,
      CineStrip.picW / 2 * aspect,
      CineStrip.picH / 2,
      CineStrip.frameRadius,
    );
    final cov = smooth(-px, px, frame);
    if (cov <= 0) return (0, 0, 0, 0);
    final hole = _box(
      x,
      y,
      (CineStrip.holeX + CineStrip.holeW / 2) * aspect,
      CineStrip.holeY + CineStrip.holeH / 2,
      CineStrip.holeW / 2 * aspect,
      CineStrip.holeH / 2,
      CineStrip.holeRadius,
    );
    var r = base.$1.toDouble(), g = base.$2.toDouble(), b = base.$3.toDouble();
    // Faint line down the film's outer edge.
    final e = (x - 0.012 * aspect) / 0.0016;
    final line = 0.55 * math.exp(-e * e);
    r += (edgeLine.$1 - r) * line;
    g += (edgeLine.$2 - g) * line;
    b += (edgeLine.$3 - b) * line;
    // Light bleeding round the sprocket hole's edge.
    if (hole > 0) {
      final t = hole / 0.0035;
      final glow = math.min(1.0, math.exp(-t * t) + 0.35 * math.exp(-hole / 0.012));
      r += (rim.$1 - r) * glow;
      g += (rim.$2 - g) * glow;
      b += (rim.$3 - b) * glow;
    }
    // The hole itself: black.
    final inHole = smooth(px, -px, hole);
    r *= 1 - inHole;
    g *= 1 - inHole;
    b *= 1 - inHole;
    return (cov, r.round(), g.round(), b.round());
  }
}
