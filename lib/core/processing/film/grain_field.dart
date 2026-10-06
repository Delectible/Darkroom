import 'dart:math' as math;
import 'dart:typed_data';

/// Tileable film-grain texture, built the way grain forms: many tiny dye
/// clouds / silver grains of varying size scattered at random, overlapping
/// and saturating where they pile up (a Boolean model), plus a sparser set
/// of larger clumps. That gives crisp, irregular grain with real structure,
/// rather than the soft "low-res" look of blurred noise.
///
/// One texel is about one fine grain. Three channels (the three dye layers)
/// share most of their grains, so colour noise stays subtle; B&W stocks use
/// channel 0 only. Each channel has zero mean and unit standard deviation.
class GrainField {
  GrainField._(this.size, this.data);

  final int size;
  final Float32List data;

  /// RGBA8 encoding: v8 = 128 + v * [encodeScale]. The shader decodes with
  /// the same constant.
  static const double encodeScale = 36.0;

  static const int defaultSize = 512;

  /// Share of grains common to all three layers.
  static const double _shared = 0.78;

  factory GrainField.generate({int size = defaultSize, int seed = 1977}) {
    final rnd = math.Random(seed);
    final n = size * size;
    Float32List layer() {
      final acc = Float32List(n);
      // Fine grains: radius 0.45..1.25 texels, about half the area covered.
      _scatter(acc, size, rnd, count: (n * 0.30).round(), rMin: 0.45, rMax: 1.25, weight: 1.0);
      // Clumps: sparse, larger, fainter.
      _scatter(acc, size, rnd, count: (n * 0.018).round(), rMin: 1.6, rMax: 2.8, weight: 0.45);
      // Density saturates where grains pile up.
      for (var i = 0; i < n; i++) {
        acc[i] = 1 - math.exp(-1.4 * acc[i]);
      }
      return acc;
    }

    final common = layer();
    final data = Float32List(n * 3);
    final indep = math.sqrt(1 - _shared * _shared);
    for (var c = 0; c < 3; c++) {
      final own = layer();
      var sum = 0.0, sum2 = 0.0;
      for (var i = 0; i < n; i++) {
        final v = _shared * common[i] + indep * own[i];
        own[i] = v;
        sum += v;
        sum2 += v * v;
      }
      final mean = sum / n;
      final std = math.sqrt(math.max(1e-12, sum2 / n - mean * mean));
      for (var i = 0; i < n; i++) {
        data[i * 3 + c] = (own[i] - mean) / std;
      }
    }
    return GrainField._(size, data);
  }

  /// Adds [count] anti-aliased discs (wrapping, so the tile stays seamless).
  static void _scatter(
    Float32List acc,
    int size,
    math.Random rnd, {
    required int count,
    required double rMin,
    required double rMax,
    required double weight,
  }) {
    for (var k = 0; k < count; k++) {
      final cx = rnd.nextDouble() * size, cy = rnd.nextDouble() * size;
      final r = rMin + (rMax - rMin) * rnd.nextDouble();
      final ext = (r + 1).ceil();
      final x0 = cx.floor(), y0 = cy.floor();
      for (var dy = -ext; dy <= ext; dy++) {
        final py = y0 + dy;
        final fy = py + 0.5 - cy;
        final row = (py % size + size) % size * size;
        for (var dx = -ext; dx <= ext; dx++) {
          final px = x0 + dx;
          final fx = px + 0.5 - cx;
          // Coverage of the texel by the disc, with a one-texel soft edge.
          final cov = r + 0.5 - math.sqrt(fx * fx + fy * fy);
          if (cov <= 0) continue;
          acc[row + (px % size + size) % size] += weight * (cov >= 1 ? 1 : cov);
        }
      }
    }
  }

  /// Bilinear, wrapping sample of channel [c] at texel coordinates (x, y).
  double sample(double x, double y, int c) {
    final s = size;
    final fx = x.floorToDouble(), fy = y.floorToDouble();
    final tx = x - fx, ty = y - fy;
    final x0 = fx.toInt() % s, y0 = fy.toInt() % s;
    final xa = x0 < 0 ? x0 + s : x0, ya = y0 < 0 ? y0 + s : y0;
    final xb = (xa + 1) % s, yb = (ya + 1) % s;
    final d = data;
    final a = d[(ya * s + xa) * 3 + c], b = d[(ya * s + xb) * 3 + c];
    final e = d[(yb * s + xa) * 3 + c], f = d[(yb * s + xb) * 3 + c];
    return (a + (b - a) * tx) * (1 - ty) + (e + (f - e) * tx) * ty;
  }

  Uint8List toRgba8() {
    final n = size * size;
    final px = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      for (var c = 0; c < 3; c++) {
        px[i * 4 + c] = (128 + data[i * 3 + c] * encodeScale).round().clamp(0, 255);
      }
      px[i * 4 + 3] = 255;
    }
    return px;
  }
}
