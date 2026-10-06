import 'dart:math' as math;
import 'dart:typed_data';

import 'color_math.dart';
import 'film_profile.dart';

/// Log-ish encoding of display-linear light in [0, 4] (two stops of
/// headroom for exposure and flash) used as the LUT's input axis. The GLSL
/// in shaders/film.frag implements the identical function.
class LutShaper {
  const LutShaper._();

  static const double maxLinear = 4.0;
  static const double _k = 31.0;
  static final double _norm = math.log(1 + _k * maxLinear);

  static double encode(double x) => x <= 0 ? 0 : math.min(1.0, math.log(1 + _k * x) / _norm);
  static double decode(double s) => (math.exp(s * _norm) - 1) / _k;
}

/// What the LUT's input axis means.
enum LutInput {
  /// [LutShaper]-encoded display-linear light (shader + still renderer).
  shaped,

  /// Plain sRGB code values (FFmpeg `lut3d`, which sees 8-bit video).
  srgb,
}

/// A 3D LUT sampled from a [FilmModel]. Red varies fastest (the .cube
/// convention).
class FilmLut {
  FilmLut._(this.size, this.data);

  final int size;

  /// size^3 RGB triples, sRGB output in [0, 1].
  final Float32List data;

  static const int defaultSize = 33;

  factory FilmLut.build(
    FilmProfile profile, {
    int size = defaultSize,
    LutInput input = LutInput.shaped,
    double exposureEv = 0,
  }) {
    final model = FilmModel(profile);
    final data = Float32List(size * size * size * 3);
    final axis = Float64List(size);
    final gain = math.pow(2, exposureEv).toDouble();
    for (var i = 0; i < size; i++) {
      final t = i / (size - 1);
      axis[i] = (input == LutInput.shaped ? LutShaper.decode(t) : ColorMath.srgbToLinear(t)) * gain;
    }
    final out = List<double>.filled(3, 0);
    var o = 0;
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          model.evaluate(axis[r], axis[g], axis[b], out);
          data[o++] = out[0];
          data[o++] = out[1];
          data[o++] = out[2];
        }
      }
    }
    return FilmLut._(size, data);
  }

  /// Tetrahedral interpolation (same scheme as FFmpeg's lut3d), inputs in
  /// [0, 1]. Writes sRGB into [out].
  void sample(double r, double g, double b, List<double> out) {
    final n1 = size - 1;
    final fr = (r < 0 ? 0.0 : (r > 1 ? 1.0 : r)) * n1;
    final fg = (g < 0 ? 0.0 : (g > 1 ? 1.0 : g)) * n1;
    final fb = (b < 0 ? 0.0 : (b > 1 ? 1.0 : b)) * n1;
    var ir = fr.floor(), ig = fg.floor(), ib = fb.floor();
    if (ir >= n1) ir = n1 - 1;
    if (ig >= n1) ig = n1 - 1;
    if (ib >= n1) ib = n1 - 1;
    final dr = fr - ir, dg = fg - ig, db = fb - ib;
    final s1 = 3, s2 = size * 3, s3 = size * size * 3;
    final c000 = (ib * size * size + ig * size + ir) * 3;
    final c111 = c000 + s1 + s2 + s3;
    int a, bb;
    double w0, w1, w2, w3;
    if (dr > dg) {
      if (dg > db) {
        a = c000 + s1;
        bb = c000 + s1 + s2;
        w0 = 1 - dr;
        w1 = dr - dg;
        w2 = dg - db;
        w3 = db;
      } else if (dr > db) {
        a = c000 + s1;
        bb = c000 + s1 + s3;
        w0 = 1 - dr;
        w1 = dr - db;
        w2 = db - dg;
        w3 = dg;
      } else {
        a = c000 + s3;
        bb = c000 + s1 + s3;
        w0 = 1 - db;
        w1 = db - dr;
        w2 = dr - dg;
        w3 = dg;
      }
    } else {
      if (db > dg) {
        a = c000 + s3;
        bb = c000 + s2 + s3;
        w0 = 1 - db;
        w1 = db - dg;
        w2 = dg - dr;
        w3 = dr;
      } else if (db > dr) {
        a = c000 + s2;
        bb = c000 + s2 + s3;
        w0 = 1 - dg;
        w1 = dg - db;
        w2 = db - dr;
        w3 = dr;
      } else {
        a = c000 + s2;
        bb = c000 + s1 + s2;
        w0 = 1 - dg;
        w1 = dg - dr;
        w2 = dr - db;
        w3 = db;
      }
    }
    final d = data;
    out[0] = w0 * d[c000] + w1 * d[a] + w2 * d[bb] + w3 * d[c111];
    out[1] = w0 * d[c000 + 1] + w1 * d[a + 1] + w2 * d[bb + 1] + w3 * d[c111 + 1];
    out[2] = w0 * d[c000 + 2] + w1 * d[a + 2] + w2 * d[bb + 2] + w3 * d[c111 + 2];
  }

  /// RGBA8 strip for the GPU: blue slices laid side by side, so the image is
  /// (size*size) x size; pixel (b*size + r, g).
  Uint8List toRgbaStrip() {
    final w = size * size, h = size;
    final px = Uint8List(w * h * 4);
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          final src = ((b * size + g) * size + r) * 3;
          final dst = (g * w + b * size + r) * 4;
          px[dst] = (data[src] * 255 + 0.5).toInt().clamp(0, 255);
          px[dst + 1] = (data[src + 1] * 255 + 0.5).toInt().clamp(0, 255);
          px[dst + 2] = (data[src + 2] * 255 + 0.5).toInt().clamp(0, 255);
          px[dst + 3] = 255;
        }
      }
    }
    return px;
  }

  /// Adobe/Resolve .cube text for FFmpeg's lut3d filter.
  String toCube({String title = 'Darkroom'}) {
    final sb = StringBuffer()
      ..writeln('TITLE "$title"')
      ..writeln('LUT_3D_SIZE $size')
      ..writeln('DOMAIN_MIN 0.0 0.0 0.0')
      ..writeln('DOMAIN_MAX 1.0 1.0 1.0');
    for (var i = 0; i < data.length; i += 3) {
      sb.writeln(
        '${data[i].toStringAsFixed(5)} ${data[i + 1].toStringAsFixed(5)} ${data[i + 2].toStringAsFixed(5)}',
      );
    }
    return sb.toString();
  }
}
