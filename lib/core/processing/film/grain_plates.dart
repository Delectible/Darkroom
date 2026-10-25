import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'grain_formation.dart';

/// Grain for film video. Forming every frame out of grains (as the stills
/// do) is far too slow on a phone, so a reel gets a few "plates" instead:
/// pure grain formed with the same model ([GrainFormation]) on an even
/// mid exposure, normalised and stored as 128 + [scale] * z per channel.
/// FFmpeg picks a plate per frame at a random offset (so it never repeats)
/// and lets the picture's tone set how strongly it shows (`lut2`).
class GrainPlates {
  const GrainPlates._();

  static const int count = 16;

  /// Grey levels per standard deviation in a plate.
  static const double scale = 40;

  /// Developed share of the clouds at mid-grey.
  static const double _f0 = 0.35;

  /// Plate margin either side, for the random offset (px).
  static int margin(int h) => (h * 0.08).round() & ~1;

  /// Film px per picture px: the grain's size in the picture.
  static double filmScale(GrainFormation g, int h, double resolution) => h / (g.frameHeight * resolution);

  /// Writes plate_00.png .. into [dir], each (w + 2 margin) x (h + 2 margin).
  static void render(
    String dir,
    int w,
    int h,
    GrainFormation g, {
    double resolution = 1,
    double factor = 1,
    int seed = 0,
  }) {
    final m = margin(h);
    final pw = w + 2 * m, ph = h + 2 * m;
    final s = filmScale(g, h, resolution);
    // Weak / strong grain: more / fewer crystals (noise goes as 1/sqrt(n)).
    final n = g.crystals / (s * s) / (factor * factor);
    final kernels = [for (final c in g.clouds) _kernel(math.max(0.4, c * s))];
    final rnd = math.Random(seed ^ 0x9a17);
    final common = Float32List(pw * ph);
    final buf = Float32List(pw * ph), tmp = Float32List(pw * ph);
    for (var k = 0; k < count; k++) {
      for (var i = 0; i < common.length; i++) {
        common[i] = _poisson(n * g.shared * _f0, rnd).toDouble();
      }
      final im = img.Image(width: pw, height: ph);
      final px = im.buffer.asUint8List();
      for (var c = 0; c < 3; c++) {
        for (var i = 0; i < buf.length; i++) {
          buf[i] = common[i] + _poisson(n * (1 - g.shared) * _f0, rnd);
        }
        _blur(buf, tmp, pw, ph, kernels[c]);
        var sum = 0.0, sum2 = 0.0;
        for (final v in buf) {
          sum += v;
          sum2 += v * v;
        }
        final mean = sum / buf.length;
        final inv = 1 / math.sqrt(math.max(1e-9, sum2 / buf.length - mean * mean));
        for (var i = 0; i < buf.length; i++) {
          px[i * 3 + c] = (128 + (buf[i] - mean) * inv * scale).round().clamp(0, 255);
        }
      }
      File(
        p.join(dir, 'plate_${k.toString().padLeft(2, '0')}.png'),
      ).writeAsBytesSync(img.encodePng(im, level: 1));
    }
  }

  static int _poisson(double lambda, math.Random r) {
    if (lambda > 30) {
      final u1 = r.nextDouble() + 1e-12, u2 = r.nextDouble();
      final z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
      return math.max(0, (lambda + math.sqrt(lambda) * z + 0.5).floor());
    }
    final u = r.nextDouble();
    var q = math.exp(-lambda), f = q;
    var k = 0;
    while (u > f && k < 200) {
      k++;
      q *= lambda / k;
      f += q;
    }
    return k;
  }

  static Float64List _kernel(double sigma) {
    final r = math.max(1, (sigma * 3).ceil());
    final k = Float64List(2 * r + 1);
    var s = 0.0;
    for (var i = -r; i <= r; i++) {
      s += k[i + r] = math.exp(-0.5 * (i / sigma) * (i / sigma));
    }
    for (var i = 0; i < k.length; i++) {
      k[i] /= s;
    }
    return k;
  }

  /// Separable Gaussian with wrap-around, in place.
  static void _blur(Float32List a, Float32List t, int w, int h, Float64List k) {
    final r = k.length ~/ 2;
    for (var y = 0; y < h; y++) {
      final o = y * w;
      for (var x = 0; x < w; x++) {
        var s = 0.0;
        for (var j = 0; j < k.length; j++) {
          s += a[o + (x - r + j) % w] * k[j];
        }
        t[o + x] = s;
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0.0;
        for (var j = 0; j < k.length; j++) {
          s += t[((y - r + j) % h) * w + x] * k[j];
        }
        a[y * w + x] = s;
      }
    }
  }
}
