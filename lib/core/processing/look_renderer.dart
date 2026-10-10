import 'dart:math' as math;
import 'dart:typed_data';

import 'look_spec.dart';

/// CPU implementation of the look shaders for full-resolution stills.
///
/// Runs inside a background isolate (see PhotoPipeline). Everything works
/// in place on an interleaved 8-bit RGB buffer and allocates only O(width)
/// scratch memory (plus small LUTs and grain tiles), so a 12MP frame never
/// needs a second full-size copy.
class LookRenderer {
  LookRenderer(this.look, {required this.seed});

  final LookSpec look;
  final int seed;

  static const _lumR = 0.2126, _lumG = 0.7152, _lumB = 0.0722;

  // ---------------------------------------------------------------------------
  // Pre-passes (spatial effects that happen before the colour grade, matching
  // the order of texture sampling in the shaders)
  // ---------------------------------------------------------------------------

  /// 4-neighbour unsharp mask with rolling row buffers (CCD); a negative
  /// [LookSpec.sharpen] blurs instead.
  void sharpen(Uint8List data, int w, int h, {int radius = 1}) {
    final amount = look.sharpen * 2.0;
    // Negative amounts soften (cheap plastic lenses).
    if (amount == 0 || w < 3 || h < 3) return;
    final rowBytes = w * 3;
    final r = radius.clamp(1, 8);
    // Ring buffer holding the original values of rows [y - r, y + r].
    final ring = List<Uint8List>.generate(2 * r + 1, (_) => Uint8List(rowBytes));
    Uint8List rowAt(int y) => ring[(y % ring.length + ring.length) % ring.length];
    for (var y = 0; y <= math.min(r, h - 1); y++) {
      rowAt(y).setRange(0, rowBytes, data, y * rowBytes);
    }
    for (var y = 0; y < h; y++) {
      final next = y + r;
      if (next < h && next > r) {
        rowAt(next).setRange(0, rowBytes, data, next * rowBytes);
      }
      final cur = rowAt(y);
      final up = rowAt(math.max(0, y - r));
      final down = rowAt(math.min(h - 1, y + r));
      final base = y * rowBytes;
      for (var x = 0; x < w; x++) {
        final xl = math.max(0, x - r) * 3, xr = math.min(w - 1, x + r) * 3;
        final i = x * 3;
        for (var k = 0; k < 3; k++) {
          final c = cur[i + k];
          final avg = (cur[xl + k] + cur[xr + k] + up[i + k] + down[i + k]) * 0.25;
          data[base + i + k] = (c + (c - avg) * amount).round().clamp(0, 255);
        }
      }
    }
  }

  /// VHS signal path: per-line time-base jitter, soft luma with the
  /// camera's edge halos, right-smeared chroma, and (by chance, seeded per
  /// shot) a few torn lines or a dropout streak. Operates on a frame that is
  /// already at "tape" resolution (~640 wide).
  void vhsSignal(Uint8List data, int w, int h) {
    final rnd = math.Random(seed);
    final rowBytes = w * 3;
    final src = Uint8List(rowBytes);
    final y = Float64List(w), i = Float64List(w), q = Float64List(w);
    // This frame's glitches (like the shader: random, sometimes none).
    final tearY = rnd.nextDouble() < 0.35 * look.tracking ? rnd.nextDouble() : -1.0;
    final drops = <(int, double, double)>[
      if (rnd.nextDouble() < 0.6 * look.tracking)
        for (var k = 0; k < 1 + rnd.nextInt(2); k++)
          () {
            final x0 = rnd.nextDouble();
            return (rnd.nextInt(h), x0, x0 + 0.15 + rnd.nextDouble() * 0.6);
          }(),
    ];
    final bleed = look.bleed;
    final cs = 1.0 + 4.0 * bleed;
    final cshift = -2.0 * bleed;

    for (var row = 0; row < h; row++) {
      final ny = (row + 0.5) / h;
      final lineHash = _hash(row * 7919 + seed);
      var jitter = (lineHash - 0.5) * 2.0 * look.jitter;
      jitter += math.sin(ny * 9.0 + seed * 0.1) * 0.6 * look.jitter;
      final tear = tearY < 0 ? 0.0 : 1 - _smoothstep(0, 0.02, (ny - tearY).abs());
      jitter += tear * (_hash(row * 104729 + seed + 1) * 14.0 - 4.0);
      final drop = drops.where((d) => d.$1 == row).firstOrNull;

      final base = row * rowBytes;
      src.setRange(0, rowBytes, data, base);
      // Decode to YIQ with the jitter applied (nearest sample, clamped).
      for (var x = 0; x < w; x++) {
        final sx = (x + jitter).round().clamp(0, w - 1) * 3;
        final r = src[sx] / 255, g = src[sx + 1] / 255, b = src[sx + 2] / 255;
        y[x] = 0.299 * r + 0.587 * g + 0.114 * b;
        i[x] = 0.596 * r - 0.274 * g - 0.322 * b;
        q[x] = 0.211 * r - 0.523 * g + 0.312 * b;
      }
      for (var x = 0; x < w; x++) {
        final yl = y[math.max(0, x - 1)], yr = y[math.min(w - 1, x + 1)];
        var luma = y[x] * 0.5 + (yl + yr) * 0.25;
        // edge "enhancement": bright halos round dark edges
        luma += (luma - (y[math.max(0, x - 4)] + y[math.min(w - 1, x + 4)]) * 0.5) * 0.6;
        var si = 0.0, sq = 0.0;
        for (var t = -2; t <= 2; t++) {
          final sx = (x + cshift + t * cs).round().clamp(0, w - 1);
          si += i[sx];
          sq += q[sx];
        }
        si = si / 5 * (1 + 0.3 * bleed);
        sq = sq / 5 * (1 + 0.3 * bleed);
        var r = luma + 0.956 * si + 0.621 * sq;
        var g = luma - 0.272 * si - 0.647 * sq;
        var b = luma - 1.106 * si + 1.703 * sq;
        if (drop != null) {
          final u = x / w;
          if (u >= drop.$2 && u <= drop.$3 && _hash((x * 40 ~/ w) * 31 + row * 977 + seed) > 0.3) {
            r = r + (0.9 - r) * 0.85;
            g = g + (0.9 - g) * 0.85;
            b = b + (0.9 - b) * 0.85;
          }
        }
        final o = base + x * 3;
        data[o] = (r * 255).round().clamp(0, 255);
        data[o + 1] = (g * 255).round().clamp(0, 255);
        data[o + 2] = (b * 255).round().clamp(0, 255);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Grade
  // ---------------------------------------------------------------------------

  /// Colour matrix, exposure/vignette/flash, clip, tone curve, bloom, grain
  /// and (for VHS/JPEG) scanlines / posterisation — in the shader's order.
  ///
  /// [frameWidthForGrain] is the width the grain should be scaled against
  /// (the exported frame's width; for low-res looks the pre-upscale width).
  void grade(Uint8List data, int w, int h, {required double flash, int? frameWidthForGrain}) {
    final m = look.combinedMatrix();
    final o = look.combinedOffset();
    final tint = look.flashTint(flash);
    final m0 = m[0] * tint[0], m1 = m[1] * tint[0], m2 = m[2] * tint[0];
    final m3 = m[3] * tint[1], m4 = m[4] * tint[1], m5 = m[5] * tint[1];
    final m6 = m[6] * tint[2], m7 = m[7] * tint[2], m8 = m[8] * tint[2];
    final o0 = o[0] * tint[0], o1 = o[1] * tint[1], o2 = o[2] * tint[2];

    // Tone LUT over the clamped [0, 1] input.
    const toneN = 1024;
    final toneLut = Float64List(toneN);
    for (var k = 0; k < toneN; k++) {
      toneLut[k] = look.tone(k / (toneN - 1)) * 255.0;
    }
    // Radial exposure LUT indexed by q = r^2 in [0, 1].
    const expoN = 1024;
    final expoLut = Float64List(expoN);
    for (var k = 0; k < expoN; k++) {
      expoLut[k] = look.spatialExposure(math.sqrt(k / (expoN - 1)), flash);
    }
    final inv255 = Float64List(256);
    for (var k = 0; k < 256; k++) {
      inv255[k] = k / 255.0;
    }
    final dx2 = Float64List(w);
    for (var x = 0; x < w; x++) {
      final d = ((x + 0.5) / w - 0.5) * 2.0;
      dx2[x] = d * d * 0.5;
    }

    // Vertical smear (CCD): per-column mean of clipped highlight energy.
    final smear = look.smear > 0 ? _smearColumns(data, w, h) : null;

    // Bloom source (CCD): graded, blurred, 1/8 resolution.
    final bloom = look.bloom > 0 ? _bloomMap(data, w, h, flash) : null;
    final bw = bloom == null ? 0 : (w + 7) ~/ 8;
    final bh = bloom == null ? 0 : (h + 7) ~/ 8;

    // Grain tiles.
    final gw = frameWidthForGrain ?? w;
    final cell = math.max(1.0, look.grainSize * gw / LookSpec.referenceWidth);
    final needGrain = look.grainAmount > 0 || look.chromaNoise > 0;
    final tiles = needGrain ? _GrainTiles(seed, cell) : null;
    final grainAmt = look.grainAmount * 255.0;
    final chroma = look.grainChroma;
    final chromaNoise = look.chromaNoise * 255.0;
    final levels = look.kind == ShaderKind.jpegPixel ? math.max(2.0, look.posterize) : 0.0;
    final scan = look.kind == ShaderKind.vhs ? look.scanline : 0.0;

    for (var y = 0; y < h; y++) {
      final dy = ((y + 0.5) / h - 0.5) * 2.0;
      final dy2 = dy * dy * 0.5;
      final rowScan = (scan > 0 && y.isOdd) ? 1.0 - scan : 1.0;
      final base = y * w * 3;
      final tr = tiles?.row(y);
      for (var x = 0; x < w; x++) {
        final p = base + x * 3;
        final r = inv255[data[p]], g = inv255[data[p + 1]], b = inv255[data[p + 2]];
        var qi = ((dx2[x] + dy2) * (expoN - 1)).toInt();
        if (qi > expoN - 1) qi = expoN - 1;
        final e = expoLut[qi];
        var cr = (m0 * r + m1 * g + m2 * b + o0) * e;
        var cg = (m3 * r + m4 * g + m5 * b + o1) * e;
        var cb = (m6 * r + m7 * g + m8 * b + o2) * e;
        cr = cr < 0 ? 0 : (cr > 1 ? 1 : cr);
        cg = cg < 0 ? 0 : (cg > 1 ? 1 : cg);
        cb = cb < 0 ? 0 : (cb > 1 ? 1 : cb);
        var outR = toneLut[(cr * (toneN - 1) + 0.5).toInt()];
        var outG = toneLut[(cg * (toneN - 1) + 0.5).toInt()];
        var outB = toneLut[(cb * (toneN - 1) + 0.5).toInt()];

        if (bloom != null) {
          final bv = _sampleBloom(bloom, bw, bh, x / 8.0, y / 8.0);
          // Screen blend, same as the shader.
          outR = 255 - (255 - outR) * (1 - bv[0] * 0.5);
          outG = 255 - (255 - outG) * (1 - bv[1] * 0.5);
          outB = 255 - (255 - outB) * (1 - bv[2] * 0.5);
        }

        if (smear != null) {
          final sv = smear[x];
          outR += sv * 255.0;
          outG += sv * 0.94 * 255.0;
          outB += sv * 1.06 * 255.0;
        }

        if (tr != null) {
          final l = (_lumR * outR + _lumG * outG + _lumB * outB) / 255.0;
          final n = tr.mono(x);
          if (grainAmt > 0) {
            final wgt = LookSpec.midtoneWeight(l) * grainAmt;
            if (chroma > 0) {
              outR += (n * (1 - chroma) + tr.r(x) * chroma) * wgt;
              outG += (n * (1 - chroma) + tr.g(x) * chroma) * wgt;
              outB += (n * (1 - chroma) + tr.b(x) * chroma) * wgt;
            } else {
              outR += n * wgt;
              outG += n * wgt;
              outB += n * wgt;
            }
          }
          if (chromaNoise > 0) {
            final s = (1 - l) * (1 - l) * chromaNoise;
            outR += tr.r(x) * s;
            outG += tr.g(x) * s;
            outB += tr.b(x) * s;
          }
        }

        if (levels > 0) {
          outR = (outR / 255 * levels).roundToDouble() / levels * 255;
          outG = (outG / 255 * levels).roundToDouble() / levels * 255;
          outB = (outB / 255 * levels).roundToDouble() / levels * 255;
        }
        outR *= rowScan;
        outG *= rowScan;
        outB *= rowScan;

        data[p] = outR < 0 ? 0 : (outR > 255 ? 255 : outR.round());
        data[p + 1] = outG < 0 ? 0 : (outG > 255 ? 255 : outG.round());
        data[p + 2] = outB < 0 ? 0 : (outB > 255 ? 255 : outB.round());
      }
    }
  }

  /// Smear strength per column, same constants as the CCD shader.
  Float64List _smearColumns(Uint8List data, int w, int h) {
    final col = Float64List(w);
    final step = math.max(1, h ~/ 96);
    var rows = 0;
    for (var y = 0; y < h; y += step) {
      rows++;
      final base = y * w * 3;
      for (var x = 0; x < w; x++) {
        final p = base + x * 3;
        final l = (_lumR * data[p] + _lumG * data[p + 1] + _lumB * data[p + 2]) / 255.0 * look.exposure;
        if (l > 0.92) col[x] += l - 0.92;
      }
    }
    for (var x = 0; x < w; x++) {
      col[x] = col[x] / rows * 7.0 * look.smear;
    }
    return col;
  }

  /// Highlight bloom map (values 0..1 per channel) at 1/8 resolution.
  Float32List _bloomMap(Uint8List data, int w, int h, double flash) {
    final bw = (w + 7) ~/ 8, bh = (h + 7) ~/ 8;
    final small = Float32List(bw * bh * 3);
    final counts = Int32List(bw * bh);
    for (var y = 0; y < h; y++) {
      final sy = y ~/ 8;
      for (var x = 0; x < w; x++) {
        final si = sy * bw + x ~/ 8;
        final p = (y * w + x) * 3;
        small[si * 3] += data[p];
        small[si * 3 + 1] += data[p + 1];
        small[si * 3 + 2] += data[p + 2];
        counts[si]++;
      }
    }
    final m = look.combinedMatrix();
    final o = look.combinedOffset();
    final tint = look.flashTint(flash);
    for (var i = 0; i < bw * bh; i++) {
      final n = math.max(1, counts[i]) * 255.0;
      final r = small[i * 3] / n, g = small[i * 3 + 1] / n, b = small[i * 3 + 2] / n;
      final sy = i ~/ bw, sx = i % bw;
      final dx = ((sx + 0.5) / bw - 0.5) * 2, dy = ((sy + 0.5) / bh - 0.5) * 2;
      final e = look.spatialExposure(math.sqrt((dx * dx + dy * dy) * 0.5), flash);
      for (var k = 0; k < 3; k++) {
        final v = ((m[k * 3] * r + m[k * 3 + 1] * g + m[k * 3 + 2] * b + o[k]) * e * tint[k]).clamp(0.0, 1.0);
        small[i * 3 + k] = (math.max(0.0, look.tone(v) - 0.8) * 5.0 * look.bloom).toDouble();
      }
    }
    // Two box-blur passes for a soft halo.
    for (var pass = 0; pass < 2; pass++) {
      _boxBlur3(small, bw, bh);
    }
    return small;
  }

  static void _boxBlur3(Float32List a, int w, int h) {
    final tmp = Float32List.fromList(a);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        for (var k = 0; k < 3; k++) {
          var s = 0.0;
          var c = 0;
          for (var oy = -1; oy <= 1; oy++) {
            final yy = y + oy;
            if (yy < 0 || yy >= h) continue;
            for (var ox = -1; ox <= 1; ox++) {
              final xx = x + ox;
              if (xx < 0 || xx >= w) continue;
              s += tmp[(yy * w + xx) * 3 + k];
              c++;
            }
          }
          a[(y * w + x) * 3 + k] = s / c;
        }
      }
    }
  }

  static final _bloomScratch = Float64List(3);

  static Float64List _sampleBloom(Float32List b, int bw, int bh, double fx, double fy) {
    final x0 = fx.floor().clamp(0, bw - 1), y0 = fy.floor().clamp(0, bh - 1);
    final x1 = math.min(bw - 1, x0 + 1), y1 = math.min(bh - 1, y0 + 1);
    final tx = (fx - x0).clamp(0.0, 1.0), ty = (fy - y0).clamp(0.0, 1.0);
    for (var k = 0; k < 3; k++) {
      final a = b[(y0 * bw + x0) * 3 + k], c = b[(y0 * bw + x1) * 3 + k];
      final d = b[(y1 * bw + x0) * 3 + k], e = b[(y1 * bw + x1) * 3 + k];
      _bloomScratch[k] = (a + (c - a) * tx) * (1 - ty) + (d + (e - d) * tx) * ty;
    }
    return _bloomScratch;
  }

  /// Mean luminance (0..1) sampled on a coarse grid; used by Flash = Auto.
  static double meanLuma(Uint8List data, int w, int h) {
    var sum = 0.0;
    var n = 0;
    final step = math.max(1, math.sqrt(w * h / 4096).floor());
    for (var y = 0; y < h; y += step) {
      for (var x = 0; x < w; x += step) {
        final p = (y * w + x) * 3;
        sum += (_lumR * data[p] + _lumG * data[p + 1] + _lumB * data[p + 2]) / 255;
        n++;
      }
    }
    return n == 0 ? 0.5 : sum / n;
  }

  static double _smoothstep(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// Integer hash -> [0, 1).
  static double _hash(int v) {
    var x = v & 0x7fffffff;
    x = ((x >> 16) ^ x) * 0x45d9f3b & 0x7fffffff;
    x = ((x >> 16) ^ x) * 0x45d9f3b & 0x7fffffff;
    x = (x >> 16) ^ x;
    return (x & 0xffffff) / 0x1000000;
  }
}

/// Blurred noise tiles reproducing the shader's triangular grain statistics
/// (std ~0.408) at an arbitrary cell size. Two tiles of coprime size are
/// summed so the pattern never visibly repeats on a 12MP frame.
class _GrainTiles {
  _GrainTiles(int seed, double cell) : _a = _makeTile(_sa, cell, seed), _b = _makeTile(_sb, cell, seed + 7) {
    final rnd = math.Random(seed);
    for (var k = 0; k < _offsets.length; k++) {
      _offsets[k] = rnd.nextInt(1 << 16);
    }
  }

  static const _sa = 256, _sb = 241;
  final Float32List _a;
  final Float32List _b;
  final List<int> _offsets = List<int>.filled(10, 0);

  int _rowA = 0, _rowB = 0, _y = 0;

  _GrainTiles row(int y) {
    _y = y;
    _rowA = ((y + _offsets[0]) % _sa) * _sa;
    _rowB = ((y + _offsets[1]) % _sb) * _sb;
    return this;
  }

  double _sample(int x, int channel) {
    final ox = _offsets[2 + channel * 2];
    final oy = _offsets[3 + channel * 2];
    final ra = channel == 0 ? _rowA : ((_y + oy) % _sa) * _sa;
    final rb = channel == 0 ? _rowB : ((_y + ox) % _sb) * _sb;
    return (_a[ra + (x + ox) % _sa] + _b[rb + (x + oy) % _sb]) * 0.70710678;
  }

  double mono(int x) => _sample(x, 0);
  double r(int x) => _sample(x, 1);
  double g(int x) => _sample(x, 2);
  double b(int x) => _sample(x, 3);

  static Float32List _makeTile(int size, double cell, int seed) {
    final rnd = math.Random(seed);
    final t = Float32List(size * size);
    for (var i = 0; i < t.length; i++) {
      t[i] = rnd.nextDouble() + rnd.nextDouble() - 1.0; // triangular
    }
    final radius = ((cell - 1) / 2).round();
    if (radius > 0) {
      final tmp = Float32List(size * size);
      final span = 2 * radius + 1;
      // Separable box blur with wrap-around (tileable).
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          var s = 0.0;
          for (var k = -radius; k <= radius; k++) {
            s += t[y * size + (x + k) % size];
          }
          tmp[y * size + x] = s / span;
        }
      }
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          var s = 0.0;
          for (var k = -radius; k <= radius; k++) {
            s += tmp[((y + k) % size) * size + x];
          }
          t[y * size + x] = s / span;
        }
      }
    }
    // Normalise to the shader's distribution width.
    var sum = 0.0, sum2 = 0.0;
    for (final v in t) {
      sum += v;
      sum2 += v * v;
    }
    final mean = sum / t.length;
    final std = math.sqrt(math.max(1e-9, sum2 / t.length - mean * mean));
    const target = 0.408;
    for (var i = 0; i < t.length; i++) {
      t[i] = (t[i] - mean) / std * target;
    }
    return t;
  }
}
