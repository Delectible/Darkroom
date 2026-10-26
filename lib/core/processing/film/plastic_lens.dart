import 'dart:math' as math;
import 'dart:typed_data';

import 'color_math.dart';

/// A cheap moulded lens in front of the film (stills): straight lines bow
/// out (barrel), colours split toward the edges (lateral aberration), the
/// corners go soft, and the highlights roll off early (a narrow, flat
/// exposure range, like a fixed-exposure camera's minilab print).
class PlasticLens {
  const PlasticLens({
    this.distortion = 0.06,
    this.aberration = 0.0025,
    this.softness = 0.7,
    this.compress = 0.18,
  });

  /// Barrel strength: the corner is pulled in by about this share of the
  /// half-diagonal (the frame is refilled, so no black corners).
  final double distortion;

  /// Red is magnified this much more than green at the corner, blue this
  /// much less (share of the half-diagonal).
  final double aberration;

  /// How much of the frame's corners comes from a blurred copy (0..1).
  final double softness;

  /// Highlights above mid-grey are pulled toward it in log exposure by
  /// this share (0 = none); shadows by a third of it.
  final double compress;

  /// Applies the lens to packed RGB8 [data] (w x h), in place.
  void apply(Uint8List data, int w, int h) {
    final src = Uint8List.fromList(data);

    // A blurred copy at 1/8 size for the soft corners.
    const f = 8;
    final bw = (w + f - 1) ~/ f, bh = (h + f - 1) ~/ f;
    final blur = Float32List(bw * bh * 3);
    final cnt = Float32List(bw * bh);
    for (var y = 0; y < h; y++) {
      final by = y ~/ f;
      var q = y * w * 3;
      for (var x = 0; x < w; x++, q += 3) {
        final b = by * bw + x ~/ f;
        blur[b * 3] += src[q];
        blur[b * 3 + 1] += src[q + 1];
        blur[b * 3 + 2] += src[q + 2];
        cnt[b] += 1;
      }
    }
    for (var b = 0; b < bw * bh; b++) {
      final n = cnt[b];
      blur[b * 3] /= n;
      blur[b * 3 + 1] /= n;
      blur[b * 3 + 2] /= n;
    }
    _smooth(blur, bw, bh);
    _smooth(blur, bw, bh);

    // Tone: sRGB8 -> compressed sRGB8.
    final tone = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      final lin = ColorMath.srgbToLinear(i / 255);
      double out;
      if (lin <= 0) {
        out = 0;
      } else {
        final c = lin > 0.18 ? compress : compress / 3;
        out = 0.18 * math.pow(lin / 0.18, 1 - c);
      }
      tone[i] = (ColorMath.linearToSrgb(out.clamp(0.0, 1.0)) * 255 + 0.5).toInt().clamp(0, 255);
    }

    final cx = w / 2, cy = h / 2;
    final half = math.sqrt(cx * cx + cy * cy);
    final k = distortion, norm = 1 / (1 + k);
    final scale = [1 + aberration, 1.0, 1 - aberration];
    for (var y = 0; y < h; y++) {
      final dy = (y + 0.5 - cy) / half;
      var q = y * w * 3;
      for (var x = 0; x < w; x++, q += 3) {
        final dx = (x + 0.5 - cx) / half;
        final r2 = dx * dx + dy * dy;
        // Output radius -> source radius (the corner stays the corner).
        final m = (1 + k * r2) * norm;
        final soft = softness * _smoothstep(0.35, 1.0, r2);
        for (var c = 0; c < 3; c++) {
          final s = m * scale[c];
          final sx = cx + dx * s * half - 0.5, sy = cy + dy * s * half - 0.5;
          var v = _bilinear(src, w, h, sx, sy, c);
          if (soft > 0) {
            final b = _bilinearF(blur, bw, bh, (sx + 0.5) / f - 0.5, (sy + 0.5) / f - 0.5, c);
            v += (b - v) * soft;
          }
          data[q + c] = tone[v.round().clamp(0, 255)];
        }
      }
    }
  }

  static double _smoothstep(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _bilinear(Uint8List a, int w, int h, double x, double y, int c) {
    final xc = x.clamp(0.0, w - 1.0), yc = y.clamp(0.0, h - 1.0);
    final x0 = xc.floor(), y0 = yc.floor();
    final x1 = math.min(w - 1, x0 + 1), y1 = math.min(h - 1, y0 + 1);
    final fx = xc - x0, fy = yc - y0;
    final a00 = a[(y0 * w + x0) * 3 + c], a01 = a[(y0 * w + x1) * 3 + c];
    final a10 = a[(y1 * w + x0) * 3 + c], a11 = a[(y1 * w + x1) * 3 + c];
    final top = a00 + (a01 - a00) * fx, bot = a10 + (a11 - a10) * fx;
    return top + (bot - top) * fy;
  }

  static double _bilinearF(Float32List a, int w, int h, double x, double y, int c) {
    final xc = x.clamp(0.0, w - 1.0), yc = y.clamp(0.0, h - 1.0);
    final x0 = xc.floor(), y0 = yc.floor();
    final x1 = math.min(w - 1, x0 + 1), y1 = math.min(h - 1, y0 + 1);
    final fx = xc - x0, fy = yc - y0;
    final a00 = a[(y0 * w + x0) * 3 + c], a01 = a[(y0 * w + x1) * 3 + c];
    final a10 = a[(y1 * w + x0) * 3 + c], a11 = a[(y1 * w + x1) * 3 + c];
    final top = a00 + (a01 - a00) * fx, bot = a10 + (a11 - a10) * fx;
    return top + (bot - top) * fy;
  }

  /// 3x3 box blur, in place.
  static void _smooth(Float32List a, int w, int h) {
    final o = Float32List.fromList(a);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        for (var c = 0; c < 3; c++) {
          var s = 0.0;
          for (var j = -1; j <= 1; j++) {
            final yy = (y + j).clamp(0, h - 1);
            for (var i = -1; i <= 1; i++) {
              s += o[(yy * w + (x + i).clamp(0, w - 1)) * 3 + c];
            }
          }
          a[(y * w + x) * 3 + c] = s / 9;
        }
      }
    }
  }
}
