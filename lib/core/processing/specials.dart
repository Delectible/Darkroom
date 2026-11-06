import 'dart:math' as math;
import 'dart:typed_data';

import '../../features/cameras/domain/camera_spec.dart';

/// The cameras' specials that change the picture (CameraSpecial): pure
/// functions on an RGB8 frame (stills) or on the FFmpeg graph (video).
class Specials {
  const Specials._();

  /// Light getting in at the back of a cheap camera: a warm glow from one
  /// edge, hot near it and red as it spreads, different on every frame
  /// ([seed]). Screen-blended, before the film's look.
  static void lightLeak(Uint8List data, int w, int h, {required int seed}) {
    final rnd = math.Random(seed);
    final short = math.min(w, h).toDouble();
    // where it comes in: a point just outside one edge
    final side = rnd.nextInt(4);
    final t = 0.15 + rnd.nextDouble() * 0.7;
    final (ax, ay) = switch (side) {
      0 => (-0.08 * short, t * h),
      1 => (w + 0.08 * short, t * h),
      2 => (t * w, -0.08 * short),
      _ => (t * w, h + 0.08 * short),
    };
    // along the edge it reaches further than into the frame
    final alongX = side < 2 ? 0.0 : 1.0;
    final reach = short * (0.45 + rnd.nextDouble() * 0.3);
    final strength = 0.75 + rnd.nextDouble() * 0.25;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = (x - ax) / (reach * (alongX == 1 ? 1.8 : 1)),
            dy = (y - ay) / (reach * (alongX == 0 ? 1.8 : 1));
        final d2 = dx * dx + dy * dy;
        if (d2 > 6) continue;
        final k = math.exp(-d2) * strength;
        // hot (pale yellow) near the gap, red where it thins out
        final hot = math.min(1.0, k * 1.3);
        final lr = k * (0.95 + 0.05 * hot),
            lg = k * (0.22 + 0.6 * hot * hot),
            lb = k * (0.06 + 0.35 * hot * hot * hot);
        final i = (y * w + x) * 3;
        data[i] = (255 - (255 - data[i]) * (1 - lr.clamp(0.0, 1.0))).round();
        data[i + 1] = (255 - (255 - data[i + 1]) * (1 - lg.clamp(0.0, 1.0))).round();
        data[i + 2] = (255 - (255 - data[i + 2]) * (1 - lb.clamp(0.0, 1.0))).round();
      }
    }
  }

  /// The digital cameras' colour modes, after their look.
  static void colorFx(Uint8List data, ColorFx fx) {
    if (fx == ColorFx.none) return;
    for (var i = 0; i + 2 < data.length; i += 3) {
      final l = 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
      if (fx == ColorFx.mono) {
        final v = l.round().clamp(0, 255);
        data[i] = v;
        data[i + 1] = v;
        data[i + 2] = v;
      } else {
        final (r, g, b) = sepia(l / 255);
        data[i] = (r * 255).round().clamp(0, 255);
        data[i + 1] = (g * 255).round().clamp(0, 255);
        data[i + 2] = (b * 255).round().clamp(0, 255);
      }
    }
  }

  /// A warm brown tone of luma [l] (0-1): the cameras' sepia mode.
  static (double, double, double) sepia(double l) => (l * 1.07 + 0.03, l * 0.86 + 0.02, l * 0.62);

  /// The viewfinder's colour matrix for [fx] (Flutter's 5x4), or null.
  static List<double>? colorMatrix(ColorFx fx) => switch (fx) {
    ColorFx.none => null,
    ColorFx.mono => const [
      0.2126, 0.7152, 0.0722, 0, 0, //
      0.2126, 0.7152, 0.0722, 0, 0, //
      0.2126, 0.7152, 0.0722, 0, 0, //
      0, 0, 0, 1, 0,
    ],
    ColorFx.sepia => const [
      0.2275, 0.7653, 0.0773, 0, 7.65, //
      0.1828, 0.6151, 0.0621, 0, 5.1, //
      0.1318, 0.4434, 0.0448, 0, 0, //
      0, 0, 0, 1, 0,
    ],
  };

  /// SLOW: how much longer the take runs (half speed).
  static const slowFactor = 2.0;

  /// The sound stretched to match (pitch kept), after [filter] (if any).
  static String slowAudio(String? filter) => filter == null ? 'atempo=0.5' : '$filter,atempo=0.5';
}
