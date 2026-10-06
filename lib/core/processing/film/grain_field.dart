import 'dart:math' as math;
import 'dart:typed_data';

/// Tileable film-grain texture: fine noise plus a slightly coarser octave of
/// the same noise, which gives the irregular "clumps" of silver-halide /
/// dye-cloud grain rather than the flat look of per-pixel white noise.
///
/// Three channels, partially correlated (colour negative layers share some
/// structure); B&W stocks use channel 0 only. Each channel has zero mean and
/// unit standard deviation.
class GrainField {
  GrainField._(this.size, this.data);

  final int size;
  final Float32List data;

  /// RGBA8 encoding: v8 = 128 + v * [encodeScale]. The shader decodes with
  /// the same constant.
  static const double encodeScale = 36.0;

  static const int defaultSize = 512;

  factory GrainField.generate({int size = defaultSize, int seed = 1977}) {
    final rnd = math.Random(seed);
    double gauss() => rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 1.5;
    final n = size * size;
    final shared = Float32List(n);
    for (var i = 0; i < n; i++) {
      shared[i] = gauss();
    }
    const corr = 0.55;
    final indep = math.sqrt(1 - corr * corr);
    final data = Float32List(n * 3);
    final ch = Float32List(n);
    final fine = Float32List(n);
    final coarse = Float32List(n);
    final tmp = Float32List(n);
    for (var c = 0; c < 3; c++) {
      for (var i = 0; i < n; i++) {
        ch[i] = corr * shared[i] + indep * gauss();
      }
      _blur(ch, fine, tmp, size, 0.6);
      _blur(ch, coarse, tmp, size, 1.7);
      var sum = 0.0, sum2 = 0.0;
      for (var i = 0; i < n; i++) {
        final v = fine[i] + 0.75 * coarse[i];
        fine[i] = v;
        sum += v;
        sum2 += v * v;
      }
      final mean = sum / n;
      final std = math.sqrt(math.max(1e-12, sum2 / n - mean * mean));
      for (var i = 0; i < n; i++) {
        data[i * 3 + c] = (fine[i] - mean) / std;
      }
    }
    return GrainField._(size, data);
  }

  /// Separable, wrap-around gaussian blur (keeps the tile seamless).
  static void _blur(Float32List src, Float32List dst, Float32List tmp, int size, double sigma) {
    final r = (sigma * 3).ceil();
    final k = Float64List(2 * r + 1);
    var ks = 0.0;
    for (var i = -r; i <= r; i++) {
      k[i + r] = math.exp(-0.5 * (i / sigma) * (i / sigma));
      ks += k[i + r];
    }
    for (var i = 0; i < k.length; i++) {
      k[i] /= ks;
    }
    for (var y = 0; y < size; y++) {
      final row = y * size;
      for (var x = 0; x < size; x++) {
        var s = 0.0;
        for (var i = -r; i <= r; i++) {
          s += src[row + (x + i + size) % size] * k[i + r];
        }
        tmp[row + x] = s;
      }
    }
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        var s = 0.0;
        for (var i = -r; i <= r; i++) {
          s += tmp[((y + i + size) % size) * size + x] * k[i + r];
        }
        dst[y * size + x] = s;
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
