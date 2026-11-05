import 'dart:math' as math;
import 'dart:typed_data';

import '../../features/cameras/domain/camera_spec.dart';

/// The film camera's lens, drawn into the photo: the same as
/// shaders/lens.frag draws over the viewfinder, before the film's own look.
///
/// Works in place on an RGB8 buffer. Blurs, glows and streaks come from a
/// small copy of the frame (long edge ~1024) so even a full-size print takes
/// a moment, not minutes; bending and the sharp parts use the full frame.
class LensRenderer {
  LensRenderer(this.lens);

  final LensKind lens;

  void render(Uint8List data, int w, int h) {
    if (lens == LensKind.standard) return;
    final src = Uint8List.fromList(data);
    final small = _Small.of(src, w, h);
    final aspect = w / h;
    final diag = math.sqrt(0.25 * aspect * aspect + 0.25);
    final mn = math.min(w, h).toDouble();
    final out = List<double>.filled(3, 0);
    final tmp = List<double>.filled(3, 0);

    // what a blurred disc of radius [rad] (uv) looks like at (u, v)
    final blurs = <int, _Small>{};
    _Small blurred(double rad) {
      final px = math.max(1, (rad * small.h).round());
      return blurs[px] ??= small.blurred(px);
    }

    for (var y = 0; y < h; y++) {
      final v = (y + 0.5) / h;
      for (var x = 0; x < w; x++) {
        final u = (x + 0.5) / w;
        final dx = u - 0.5, dy = v - 0.5;
        final r = math.sqrt(dx * dx * aspect * aspect + dy * dy) / diag;
        final i = (y * w + x) * 3;
        switch (lens) {
          case LensKind.wide:
            final f = 0.93 * (1 + 0.10 * r * r);
            final su = 0.5 + dx * f, sv = 0.5 + dy * f;
            _sample(src, w, h, su, sv, out);
            final m = ((r - 0.55) / 0.45).clamp(0.0, 1.0) * 0.6;
            if (m > 0) {
              blurred(0.004).sample(su, sv, tmp);
              _mix(out, tmp, m);
            }
            _scale(out, 1 - 0.35 * r * r);
          case LensKind.fisheye:
            final px = dx * w, py = dy * h;
            final rad = 0.49 * mn;
            final rm = math.sqrt(px * px + py * py) / rad;
            final th = math.min(rm * 1.25, 1.45);
            final k = (math.tan(th) / math.tan(1.25)) / math.max(rm, 1e-4);
            final dg = 0.5 * math.sqrt(w * w + h * h);
            _sample(
              src,
              w,
              h,
              0.5 + (px / rad) * k * dg * 0.72 / w,
              0.5 + (py / rad) * k * dg * 0.72 / h,
              out,
            );
            final edge = ((1 - rm) * rad / 2).clamp(0.0, 1.0);
            _scale(out, (1 - 0.25 * rm * rm) * edge);
          case LensKind.plastic:
            final f = 1 + 0.06 * r * r;
            _sample(src, w, h, 0.5 + dx * f * 1.006, 0.5 + dy * f * 1.006, tmp);
            final red = tmp[0];
            _sample(src, w, h, 0.5 + dx * f * 0.994, 0.5 + dy * f * 0.994, tmp);
            final blue = tmp[2];
            _sample(src, w, h, 0.5 + dx * f, 0.5 + dy * f, out);
            out[0] = red;
            out[2] = blue;
            blurred(0.008).sample(0.5 + dx * f, 0.5 + dy * f, tmp);
            _mix(out, tmp, (r * r * 1.6).clamp(0.0, 1.0));
            const tint = [1.04, 1.0, 0.94];
            final vig = 1 - 0.75 * math.pow(r, 2.2);
            for (var c = 0; c < 3; c++) {
              out[c] = (out[c] * 0.92 + 0.04) * tint[c] * vig;
            }
          case LensKind.soft:
            _read(src, i, out);
            blurred(0.018).sample(u, v, tmp);
            final l = _luma(out);
            final m = math.pow(((l - 0.45) / 0.5).clamp(0.0, 1.0), 1.5);
            for (var c = 0; c < 3; c++) {
              out[c] = (1 - (1 - out[c]) * (1 - tmp[c] * (0.55 * m + 0.12))) * 0.97;
            }
          case LensKind.swirl:
            final sw = 0.24 * math.pow((r - 0.25).clamp(0.0, 1.0), 1.4);
            if (sw <= 0) {
              _read(src, i, out);
            } else {
              final ax = dx * aspect, ay = dy;
              final ang = math.atan2(ay, ax), rr = math.sqrt(ax * ax + ay * ay);
              out.fillRange(0, 3, 0);
              for (var t = 0; t < 9; t++) {
                final a = ang + (t / 8 - 0.5) * sw;
                small.sample(0.5 + math.cos(a) * rr / aspect, 0.5 + math.sin(a) * rr, tmp);
                for (var c = 0; c < 3; c++) {
                  out[c] += tmp[c] / 9;
                }
              }
              // the middle stays the full frame's
              final keep = (1 - (r - 0.25) / 0.15).clamp(0.0, 1.0);
              if (keep > 0) {
                _read(src, i, tmp);
                _mix(out, tmp, keep);
              }
            }
            _scale(out, 1 - 0.4 * r * r);
          case LensKind.tiltShift:
            _read(src, i, out);
            final m = ((((v - 0.52).abs()) - 0.13) / 0.28).clamp(0.0, 1.0);
            if (m > 0) {
              blurred(0.003 + 0.012 * m).sample(u, v, tmp);
              _mix(out, tmp, m);
            }
            final l = _luma(out);
            for (var c = 0; c < 3; c++) {
              out[c] = ((l + (out[c] - l) * 1.35) - 0.5) * 1.12 + 0.5;
            }
          case LensKind.star:
            _read(src, i, out);
            small.stars(u, v, tmp);
            for (var c = 0; c < 3; c++) {
              out[c] = 1 - (1 - out[c]) * (1 - tmp[c].clamp(0.0, 1.0));
            }
          case LensKind.anamorphic:
            _read(src, i, out);
            final s = small.streak(u, v).clamp(0.0, 1.0);
            const blueish = [0.35, 0.6, 1.0];
            for (var c = 0; c < 3; c++) {
              out[c] = 1 - (1 - out[c]) * (1 - s * blueish[c]);
            }
            final ov = math.sqrt(dx * dx * 4 + dy * dy * 9);
            _scale(out, 1 - 0.3 * math.pow((ov - 0.5).clamp(0.0, 1.0), 1.5));
          case LensKind.pinhole:
            blurred(0.006).sample(u, v, out);
            final vig = 1 - 0.95 * math.pow(r, 2.6);
            for (var c = 0; c < 3; c++) {
              out[c] = ((out[c] - 0.5) * 0.9 + 0.5) * vig;
            }
          case LensKind.standard:
            _read(src, i, out);
        }
        for (var c = 0; c < 3; c++) {
          data[i + c] = (out[c] * 255).round().clamp(0, 255);
        }
      }
    }
  }

  static double _luma(List<double> c) => 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];

  static void _read(Uint8List s, int i, List<double> out) {
    out[0] = s[i] / 255;
    out[1] = s[i + 1] / 255;
    out[2] = s[i + 2] / 255;
  }

  static void _mix(List<double> a, List<double> b, double t) {
    for (var c = 0; c < 3; c++) {
      a[c] += (b[c] - a[c]) * t;
    }
  }

  static void _scale(List<double> a, double k) {
    for (var c = 0; c < 3; c++) {
      a[c] *= k;
    }
  }

  /// Bilinear sample at (u, v) (0-1, clamped) of an RGB8 frame.
  static void _sample(Uint8List s, int w, int h, double u, double v, List<double> out) {
    final x = (u.clamp(0.0, 1.0) * w - 0.5).clamp(0.0, w - 1.0),
        y = (v.clamp(0.0, 1.0) * h - 0.5).clamp(0.0, h - 1.0);
    final x0 = x.floor(), y0 = y.floor();
    final x1 = math.min(x0 + 1, w - 1), y1 = math.min(y0 + 1, h - 1);
    final fx = x - x0, fy = y - y0;
    for (var c = 0; c < 3; c++) {
      final a = s[(y0 * w + x0) * 3 + c], b = s[(y0 * w + x1) * 3 + c];
      final cc = s[(y1 * w + x0) * 3 + c], d = s[(y1 * w + x1) * 3 + c];
      out[c] = ((a * (1 - fx) + b * fx) * (1 - fy) + (cc * (1 - fx) + d * fx) * fy) / 255;
    }
  }
}

/// A small float copy of the frame (long edge <= 1024), for the soft parts.
class _Small {
  _Small(this.px, this.w, this.h);

  factory _Small.of(Uint8List s, int w, int h) {
    final k = math.max(1, (math.max(w, h) / 1024).ceil());
    final sw = math.max(1, w ~/ k), sh = math.max(1, h ~/ k);
    final px = Float32List(sw * sh * 3);
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        for (var c = 0; c < 3; c++) {
          var sum = 0;
          for (var yy = 0; yy < k; yy++) {
            final row = ((y * k + yy) * w + x * k) * 3 + c;
            for (var xx = 0; xx < k; xx++) {
              sum += s[row + xx * 3];
            }
          }
          px[(y * sw + x) * 3 + c] = sum / (k * k * 255);
        }
      }
    }
    return _Small(px, sw, sh);
  }

  final Float32List px;
  final int w, h;

  /// Three box blurs of radius [r] (close to a gaussian).
  _Small blurred(int r) {
    final a = Float32List.fromList(px);
    final b = Float32List(px.length);
    for (var pass = 0; pass < 3; pass++) {
      _box(a, b, w, h, r, horizontal: true);
      _box(b, a, w, h, r, horizontal: false);
    }
    return _Small(a, w, h);
  }

  static void _box(Float32List s, Float32List d, int w, int h, int r, {required bool horizontal}) {
    final n = horizontal ? w : h, lines = horizontal ? h : w;
    final norm = 1 / (2 * r + 1);
    for (var line = 0; line < lines; line++) {
      int at(int i) {
        final j = i.clamp(0, n - 1);
        return horizontal ? (line * w + j) * 3 : (j * w + line) * 3;
      }

      for (var c = 0; c < 3; c++) {
        var acc = 0.0;
        for (var i = -r; i <= r; i++) {
          acc += s[at(i) + c];
        }
        for (var i = 0; i < n; i++) {
          d[at(i) + c] = acc * norm;
          acc += s[at(i + r + 1) + c] - s[at(i - r) + c];
        }
      }
    }
  }

  void sample(double u, double v, List<double> out) {
    final x = (u.clamp(0.0, 1.0) * w - 0.5).clamp(0.0, w - 1.0),
        y = (v.clamp(0.0, 1.0) * h - 0.5).clamp(0.0, h - 1.0);
    final x0 = x.floor(), y0 = y.floor();
    final x1 = math.min(x0 + 1, w - 1), y1 = math.min(y0 + 1, h - 1);
    final fx = x - x0, fy = y - y0;
    for (var c = 0; c < 3; c++) {
      final a = px[(y0 * w + x0) * 3 + c], b = px[(y0 * w + x1) * 3 + c];
      final cc = px[(y1 * w + x0) * 3 + c], d = px[(y1 * w + x1) * 3 + c];
      out[c] = (a * (1 - fx) + b * fx) * (1 - fy) + (cc * (1 - fx) + d * fx) * fy;
    }
  }

  // ---- highlight streaks, worked out once on this small frame ----

  Float32List? _stars, _streaks;

  void stars(double u, double v, List<double> out) {
    final s = _stars ??= _makeStars();
    final x = (u * w).floor().clamp(0, w - 1), y = (v * h).floor().clamp(0, h - 1);
    for (var c = 0; c < 3; c++) {
      out[c] = s[(y * w + x) * 3 + c];
    }
  }

  Float32List _makeStars() {
    final o = Float32List(px.length);
    final aspect = w / h;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        for (var dir = 0; dir < 3; dir++) {
          final a = 0.5236 + dir * 1.0472;
          final sx = math.cos(a) / aspect * 0.006 * w, sy = math.sin(a) * 0.006 * h;
          for (var i = 1; i <= 10; i++) {
            final wt = math.exp(-i / 3.5) * 0.22 * 10;
            for (final sg in const [1, -1]) {
              final xx = (x + sx * i * sg).round(), yy = (y + sy * i * sg).round();
              if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
              final j = (yy * w + xx) * 3;
              for (var c = 0; c < 3; c++) {
                final hi = px[j + c] - 0.9;
                if (hi > 0) o[(y * w + x) * 3 + c] += hi * wt;
              }
            }
          }
        }
      }
    }
    return o;
  }

  double streak(double u, double v) {
    final s = _streaks ??= _makeStreaks();
    final x = (u * w).floor().clamp(0, w - 1), y = (v * h).floor().clamp(0, h - 1);
    return s[y * w + x];
  }

  Float32List _makeStreaks() {
    final o = Float32List(w * h);
    final hi = Float32List(w * h);
    for (var i = 0; i < w * h; i++) {
      final l = 0.2126 * px[i * 3] + 0.7152 * px[i * 3 + 1] + 0.0722 * px[i * 3 + 2];
      hi[i] = math.max(0, l - 0.85) / 0.15;
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var acc = 0.0;
        for (var i = 1; i <= 16; i++) {
          final wt = math.exp(-i / 6) * 0.16;
          final off = (i * 0.016 * w).round();
          if (x + off < w) acc += hi[y * w + x + off] * wt;
          if (x - off >= 0) acc += hi[y * w + x - off] * wt;
        }
        o[y * w + x] = acc;
      }
    }
    return o;
  }
}
