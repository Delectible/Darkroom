import 'dart:math' as math;
import 'dart:typed_data';

import 'color_math.dart';
import 'film_lut.dart';
import 'film_profile.dart';
import 'grain_field.dart';

/// Shared spatial maths (vignette, flash fall-off, grain weighting). The
/// GLSL in shaders/film.frag mirrors these line for line.
class FilmSpatial {
  const FilmSpatial._();

  /// [r] = normalised radius (0 centre, 1 corner).
  static double exposure(double r, double vignette, double flash) {
    final v = 1 - vignette * ColorMath.smoothstep(0.30, 1.0, r);
    final hot = 1 - ColorMath.smoothstep(0.0, 0.85, r);
    return v * (1 + flash * (1.1 * hot - 0.35 * (1 - hot)));
  }

  /// Grain is most visible in the mid-tones.
  static double grainWeight(double l) => 0.35 + 2.6 * l * (1 - l);

  /// Halation threshold / gain on display-linear luminance.
  static const double halThreshold = 0.82;
  static const double halGain = 2.2;

  /// Halation radius as a fraction of the frame height.
  static const double halRadius = 0.014;
}

/// Full-resolution film renderer for stills (runs in the photo isolate).
/// In place on an interleaved RGB8 buffer; scratch memory is the LUT, one
/// 512^2 grain tile and a 1/8-resolution halation map.
class FilmRenderer {
  FilmRenderer(this.profile, {required this.seed, this.grain = GrainStrength.normal})
    : lut = FilmLut.build(profile),
      field = GrainField.generate();

  final FilmProfile profile;
  final int seed;
  final GrainStrength grain;
  final FilmLut lut;
  final GrainField field;

  void render(Uint8List data, int w, int h, {required double flash}) {
    final rnd = math.Random(seed);
    final drift = math.pow(2, (rnd.nextDouble() * 2 - 1) * profile.exposureDrift).toDouble();
    final tint = [
      (1 + (rnd.nextDouble() - 0.5) * 0.02) * (1 - 0.03 * flash),
      1.0,
      (1 + (rnd.nextDouble() - 0.5) * 0.02) * (1 + 0.06 * flash),
    ];
    final flashAmt = flash * profile.flashStrength;

    // sRGB8 -> linear
    final toLin = Float64List(256);
    for (var i = 0; i < 256; i++) {
      toLin[i] = ColorMath.srgbToLinear(i / 255);
    }
    // linear [0, maxLinear] -> shaper coordinate
    const shapeN = 4096;
    final shape = Float64List(shapeN + 1);
    for (var i = 0; i <= shapeN; i++) {
      shape[i] = LutShaper.encode(i / shapeN * LutShaper.maxLinear);
    }
    const shapeScale = shapeN / LutShaper.maxLinear;
    // radial exposure indexed by r^2/2 in [0, 1]
    const expoN = 1024;
    final expo = Float64List(expoN);
    for (var i = 0; i < expoN; i++) {
      expo[i] = FilmSpatial.exposure(math.sqrt(i / (expoN - 1)), profile.vignette, flashAmt) * drift;
    }
    final dx2 = Float64List(w);
    for (var x = 0; x < w; x++) {
      final d = ((x + 0.5) / w - 0.5) * 2.0;
      dx2[x] = d * d * 0.5;
    }

    final hal = profile.halation > 0 ? _halationMap(data, w, h, toLin, drift, flashAmt) : null;
    final hw = (w + 7) ~/ 8, hh = (h + 7) ~/ 8;
    final hc = profile.halationColor;

    final amount = profile.grainAmount * grain.factor;
    final chroma = profile.grainChroma;
    final texel = h / profile.grainResolution; // image px per grain texel
    final inv = 1 / texel;
    final ox = rnd.nextDouble() * field.size, oy = rnd.nextDouble() * field.size;
    final out = List<double>.filled(3, 0);

    for (var y = 0; y < h; y++) {
      final dy = ((y + 0.5) / h - 0.5) * 2.0;
      final dy2 = dy * dy * 0.5;
      final gy = y * inv + oy;
      final hy = (y + 0.5) / 8 - 0.5;
      for (var x = 0; x < w; x++) {
        final p = (y * w + x) * 3;
        var qi = ((dx2[x] + dy2) * (expoN - 1)).toInt();
        if (qi > expoN - 1) qi = expoN - 1;
        final e = expo[qi];
        final lr = toLin[data[p]] * e * tint[0];
        final lg = toLin[data[p + 1]] * e * tint[1];
        final lb = toLin[data[p + 2]] * e * tint[2];
        lut.sample(
          shape[math.min(shapeN, (lr * shapeScale).toInt())],
          shape[math.min(shapeN, (lg * shapeScale).toInt())],
          shape[math.min(shapeN, (lb * shapeScale).toInt())],
          out,
        );
        var r = out[0], g = out[1], b = out[2];

        if (hal != null) {
          final hv = _bilinear(hal, hw, hh, (x + 0.5) / 8 - 0.5, hy) * profile.halation;
          if (hv > 0) {
            r += hc[0] * hv * (1 - r);
            g += hc[1] * hv * (1 - g);
            b += hc[2] * hv * (1 - b);
          }
        }

        if (amount > 0) {
          final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final a = amount * FilmSpatial.grainWeight(l);
          final gx = x * inv + ox;
          final n0 = field.sample(gx, gy, 0);
          if (chroma > 0) {
            r += (n0 * (1 - chroma) + n0 * chroma) * a;
            g += (n0 * (1 - chroma) + field.sample(gx, gy, 1) * chroma) * a;
            b += (n0 * (1 - chroma) + field.sample(gx, gy, 2) * chroma) * a;
          } else {
            r += n0 * a;
            g += n0 * a;
            b += n0 * a;
          }
        }

        data[p] = r <= 0 ? 0 : (r >= 1 ? 255 : (r * 255 + 0.5).toInt());
        data[p + 1] = g <= 0 ? 0 : (g >= 1 ? 255 : (g * 255 + 0.5).toInt());
        data[p + 2] = b <= 0 ? 0 : (b >= 1 ? 255 : (b * 255 + 0.5).toInt());
      }
    }
  }

  /// Blurred highlight energy at 1/8 resolution, values ~0..1.
  Float32List _halationMap(Uint8List data, int w, int h, Float64List toLin, double drift, double flashAmt) {
    final bw = (w + 7) ~/ 8, bh = (h + 7) ~/ 8;
    final m = Float32List(bw * bh);
    final cnt = Int32List(bw * bh);
    for (var y = 0; y < h; y++) {
      final row = (y ~/ 8) * bw;
      final dy = ((y + 0.5) / h - 0.5) * 2.0;
      for (var x = 0; x < w; x += 2) {
        final p = (y * w + x) * 3;
        final dx = ((x + 0.5) / w - 0.5) * 2.0;
        final e =
            FilmSpatial.exposure(math.sqrt((dx * dx + dy * dy) * 0.5), profile.vignette, flashAmt) * drift;
        final l = (0.2126 * toLin[data[p]] + 0.7152 * toLin[data[p + 1]] + 0.0722 * toLin[data[p + 2]]) * e;
        m[row + x ~/ 8] += math.max(0, l - FilmSpatial.halThreshold) * FilmSpatial.halGain;
        cnt[row + x ~/ 8]++;
      }
    }
    for (var i = 0; i < m.length; i++) {
      if (cnt[i] > 0) m[i] /= cnt[i];
    }
    final sigma = math.max(0.6, FilmSpatial.halRadius * h / 8);
    _gauss(m, bw, bh, sigma);
    for (var i = 0; i < m.length; i++) {
      m[i] = math.min(1.0, m[i] * 2.5);
    }
    return m;
  }

  static void _gauss(Float32List a, int w, int h, double sigma) {
    final r = (sigma * 2.5).ceil();
    final k = Float64List(2 * r + 1);
    var ks = 0.0;
    for (var i = -r; i <= r; i++) {
      k[i + r] = math.exp(-0.5 * (i / sigma) * (i / sigma));
      ks += k[i + r];
    }
    final tmp = Float32List(a.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0.0;
        for (var i = -r; i <= r; i++) {
          s += a[y * w + (x + i).clamp(0, w - 1)] * k[i + r];
        }
        tmp[y * w + x] = s / ks;
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0.0;
        for (var i = -r; i <= r; i++) {
          s += tmp[(y + i).clamp(0, h - 1) * w + x] * k[i + r];
        }
        a[y * w + x] = s / ks;
      }
    }
  }

  static double _bilinear(Float32List m, int w, int h, double fx, double fy) {
    final x0 = fx.floor().clamp(0, w - 1), y0 = fy.floor().clamp(0, h - 1);
    final x1 = math.min(w - 1, x0 + 1), y1 = math.min(h - 1, y0 + 1);
    final tx = (fx - x0).clamp(0.0, 1.0), ty = (fy - y0).clamp(0.0, 1.0);
    final a = m[y0 * w + x0], b = m[y0 * w + x1], c = m[y1 * w + x0], d = m[y1 * w + x1];
    return (a + (b - a) * tx) * (1 - ty) + (c + (d - c) * tx) * ty;
  }
}
