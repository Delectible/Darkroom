import 'dart:io' show sleep;
import 'dart:math' as math;
import 'dart:typed_data';

/// How a stock's image is built out of grains (stills): the picture is made
/// of soft, round dye clouds, so detail finer than a grain isn't there at
/// all (rather than sharp detail with grain laid on top).
///
/// Crystals are scattered through each dye layer. Each has its own
/// sensitivity (log-normal); one that catches enough light develops
/// (p = 1 - exp(-speed * E * s), plus base [fog]) into a soft round dye
/// cloud. The layer's density is the sum of its clouds; the scanner turns
/// density back into light by inverting the expected response. Most clouds
/// are [shared] between the layers (so the grain is mostly neutral), the
/// rest are each layer's own; blue clouds are the largest.
class GrainFormation {
  const GrainFormation({
    this.frameHeight = 3000,
    this.clouds = const [2.2, 2.0, 2.8],
    this.crystals = 6,
    this.shared = 0.92,
    this.fog = 0.04,
    this.speed = 0.7,
    this.spread = 1.1,
  });

  /// Frame height (px) at which [clouds] and [crystals] are given: the
  /// film's own resolution. Bigger photos are formed at this size and
  /// scaled up smoothly (there is no finer detail to lose).
  final double frameHeight;

  /// Dye cloud radius (Gaussian sigma, px at [frameHeight]) per layer R, G, B.
  final List<double> clouds;

  /// Clouds per px^2 per layer at [frameHeight] when fully exposed. Fewer =
  /// grainier (the noise goes as 1 / sqrt(crystals)).
  final double crystals;

  /// Share of clouds common to the three layers.
  final double shared;

  /// Developed share with no light at all (base + fog).
  final double fog;

  /// Light needed to develop a typical crystal (higher = faster film, more
  /// of the range near the shoulder).
  final double speed;

  /// Spread of crystal sensitivities (sigma of ln).
  final double spread;
}

/// Forms the image strip by strip at the film's resolution. Deterministic
/// per pixel (counter-based random numbers), so strips join seamlessly
/// whatever order or overlap they are computed in.
class GrainFormer {
  GrainFormer(
    this.g, {
    required this.ww,
    required this.wh,
    required this.seed,
    required double sizeScale,
    required this.crystals,
    required this.exposureRow,
    this.throttle = 0,
  }) {
    final r = _responses.putIfAbsent((g.fog, g.speed, g.spread), () => _Response(g));
    _f = r.f;
    _inv = r.inv;
    _d0 = r.d0;
    _d1 = r.d1;
    var pad = 0;
    for (var c = 0; c < 3; c++) {
      final sigma = math.max(0.35, g.clouds[c] * sizeScale);
      if (sigma < 1.6) {
        // Too fine for boxes (they'd print each grain as a square).
        final r = math.max(1, (sigma * 3).ceil());
        final k = Float64List(2 * r + 1);
        var sum = 0.0;
        for (var i = -r; i <= r; i++) {
          sum += k[i + r] = math.exp(-i * i / (2 * sigma * sigma));
        }
        for (var i = 0; i < k.length; i++) {
          k[i] /= sum;
        }
        _kernel[c] = k;
        pad = math.max(pad, r);
      } else {
        final b = _boxRadii(sigma);
        _boxes[c] = b;
        pad = math.max(pad, b.fold(0, (a, r) => a + r));
      }
    }
    _pad = pad + 1;
  }

  /// The response tables only depend on the film, not the photo.
  static final _responses = <(double, double, double), _Response>{};

  final GrainFormation g;

  /// Work (film) resolution.
  final int ww, wh;
  final int seed;

  /// Clouds per work px^2 per layer when fully exposed.
  final double crystals;

  /// Fills display-linear exposure for work row [wy] (may be outside
  /// 0..wh-1: clamp) into r, g, b (length [ww]).
  final void Function(int wy, Float32List r, Float32List g, Float32List b) exposureRow;

  /// Rest this fraction of the work time after each strip (caps how much
  /// of a core the develop takes; 0 = flat out).
  final double throttle;

  static const int _strip = 64;
  static const double _maxE = 8.0;
  static const int _fN = 16384;
  static const int _iN = 16384;

  /// Three box blurs per layer approximate its Gaussian cloud (radii).
  final _boxes = List<List<int>?>.filled(3, null);

  /// Or, for fine clouds, the Gaussian itself.
  final _kernel = List<Float64List?>.filled(3, null);
  late final int _pad;

  /// Rows of context a strip needs above and below it.
  int get pad => _pad;
  late final Float64List _f; // expected developed share over E in [0, _maxE]
  late final Float64List _inv; // E over D in [_d0, _d1]
  late final double _d0, _d1;

  // Formed light (display-linear) for work rows [_base, _base + _rows).
  int _base = -1, _rows = 0;
  Float32List? _out;

  double _fOf(double e) {
    if (e <= 0) return _d0;
    final x = e * (_fN / _maxE);
    if (x >= _fN) return _d1;
    final i = x.toInt();
    return _f[i] + (_f[i + 1] - _f[i]) * (x - i);
  }

  double _eOf(double d) {
    final x = (d - _d0) * (_iN / (_d1 - _d0));
    if (x <= 0) return 0;
    if (x >= _iN) return _maxE;
    final i = x.toInt();
    return _inv[i] + (_inv[i + 1] - _inv[i]) * (x - i);
  }

  /// Box radii whose three passes match a Gaussian of [sigma] (Kovesi).
  static List<int> _boxRadii(double sigma) {
    const n = 3;
    final ideal = math.sqrt(12 * sigma * sigma / n + 1);
    var wl = ideal.floor();
    if (wl.isEven) wl--;
    final wu = wl + 2;
    final m = ((12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4 * wl - 4)).round();
    return [for (var i = 0; i < n; i++) ((i < m ? wl : wu) - 1) ~/ 2];
  }

  /// Uniform in (0, 1) for pixel (x, y), stream [k].
  double _u(int x, int y, int k) {
    var h = (x * 0x27d4eb2d) ^ (y * 0x165667b1) ^ (k * 0x9e3779b9) ^ seed;
    h &= 0xffffffff;
    h ^= h >> 16;
    h = (h * 0x85ebca6b) & 0xffffffff;
    h ^= h >> 13;
    h = (h * 0xc2b2ae35) & 0xffffffff;
    h ^= h >> 16;
    return (h + 0.5) / 4294967296.0;
  }

  /// Poisson(lambda) from pixel (x, y), stream [k]: counted out below 12,
  /// normal above (table lookups only).
  int _poisson(double lambda, int x, int y, int k) {
    if (lambda <= 0) return 0;
    final u = _u(x, y, k);
    if (lambda > 12) {
      final z = _normal[(u * _normalN).toInt()];
      final v = lambda + math.sqrt(lambda) * z + 0.5;
      return v <= 0 ? 0 : v.toInt();
    }
    var p = _expNeg[(lambda * _expScale).toInt()], f = p;
    var n = 0;
    while (u > f && n < 60) {
      n++;
      p *= lambda / n;
      f += p;
    }
    return n;
  }

  static const int _normalN = 4096;
  static const double _expScale = 1024;

  /// Standard normal quantiles at (i + 0.5) / N.
  static final Float64List _normal = () {
    final t = Float64List(_normalN);
    for (var i = 0; i < _normalN; i++) {
      t[i] = _probit((i + 0.5) / _normalN);
    }
    return t;
  }();

  /// exp(-lambda) for lambda in [0, 12] in steps of 1 / [_expScale].
  static final Float64List _expNeg = () {
    final t = Float64List((12 * _expScale).toInt() + 2);
    for (var i = 0; i < t.length; i++) {
      // At or above exp(-lambda), so the count always ends (below, a
      // draw near 1 would run on to the cap: a bright speck).
      t[i] = math.exp(-i / _expScale);
    }
    return t;
  }();

  /// Inverse normal CDF (Acklam's rational approximation).
  static double _probit(double p) {
    const a = [
      -39.69683028665376,
      220.9460984245205,
      -275.9285104469687,
      138.357751867269,
      -30.66479806614716,
      2.506628277459239,
    ];
    const b = [
      -54.47609879822406,
      161.5858368580409,
      -155.6989798598866,
      66.80131188771972,
      -13.28068155288572,
    ];
    const c = [
      -0.007784894002430293,
      -0.3223964580411365,
      -2.400758277161838,
      -2.549732539343734,
      4.374664141464968,
      2.938163982698783,
    ];
    const d = [0.007784695709041462, 0.3224671290700398, 2.445134137142996, 3.754408661907416];
    if (p < 0.02425) {
      final q = math.sqrt(-2 * math.log(p));
      return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
          ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
    }
    if (p > 1 - 0.02425) return -_probit(1 - p);
    final q = p - 0.5, r = q * q;
    return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) *
        q /
        (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
  }

  /// Formed light of layer [c] at work pixel (wx, wy); call [ensure] first.
  double at(int c, int wx, int wy) => _out![((wy - _base) * ww + wx) * 3 + c];

  /// Makes work rows lo..hi (inclusive, within 0..wh-1) available.
  void ensure(int lo, int hi) {
    if (_base >= 0 && lo >= _base && hi < _base + _rows) return;
    final sw = Stopwatch()..start();
    _compute(lo, math.min(wh, math.max(hi + 1, lo + _strip)));
    if (throttle > 0) {
      sleep(Duration(microseconds: (sw.elapsedMicroseconds * throttle).round()));
    }
  }

  void _compute(int s0, int s1) {
    final p = _pad, n = s1 - s0, rows = n + 2 * p;
    final hb = List.generate(3, (_) => Float32List(rows * ww));
    final er = Float32List(ww), eg = Float32List(ww), eb = Float32List(ww);
    final tmp = Float32List(ww);
    final sh = g.shared, own = 1 - g.shared, n0 = crystals;
    for (var i = 0; i < rows; i++) {
      final wy = s0 - p + i;
      exposureRow(wy, er, eg, eb);
      final o = i * ww;
      final c0 = hb[0], c1 = hb[1], c2 = hb[2];
      for (var x = 0; x < ww; x++) {
        final fr = _fOf(er[x]), fg = _fOf(eg[x]), fb = _fOf(eb[x]);
        final fm = (fr + fg + fb) / 3;
        final common = _poisson(n0 * sh * fm, x, wy, 0).toDouble() / fm;
        c0[o + x] = common * fr + _poisson(n0 * own * fr, x, wy, 1);
        c1[o + x] = common * fg + _poisson(n0 * own * fg, x, wy, 2);
        c2[o + x] = common * fb + _poisson(n0 * own * fb, x, wy, 3);
      }
      for (var c = 0; c < 3; c++) {
        final k = _kernel[c];
        if (k != null) {
          _kernelRow(hb[c], o, ww, k, tmp);
        } else {
          for (final r in _boxes[c]!) {
            _boxRow(hb[c], o, ww, r, tmp);
          }
        }
      }
    }
    final out = _out != null && _out!.length >= n * ww * 3 ? _out! : Float32List(n * ww * 3);
    final invN = 1 / n0;
    final acc = Float64List(ww);
    for (var c = 0; c < 3; c++) {
      final src = hb[c], k = _kernel[c];
      if (k != null) {
        final r = k.length ~/ 2;
        for (var i = 0; i < n; i++) {
          acc.fillRange(0, ww, 0);
          for (var j = 0; j < k.length; j++) {
            final o = (i + p - r + j) * ww, kj = k[j];
            for (var x = 0; x < ww; x++) {
              acc[x] += src[o + x] * kj;
            }
          }
          var q = i * ww * 3 + c;
          for (var x = 0; x < ww; x++, q += 3) {
            out[q] = _eOf(acc[x] * invN);
          }
        }
        continue;
      }
      // Vertical passes: each one leaves its radius of rows at either end
      // unfinished, inside the padding.
      var lo = 0, hi = rows;
      for (final r in _boxes[c]!) {
        _boxColumns(src, ww, lo, hi, r);
        lo += r;
        hi -= r;
      }
      for (var i = 0; i < n; i++) {
        final o = (i + p) * ww;
        var q = i * ww * 3 + c;
        for (var x = 0; x < ww; x++, q += 3) {
          out[q] = _eOf(src[o + x] * invN);
        }
      }
    }
    _out = out;
    _base = s0;
    _rows = n;
  }

  /// The Gaussian [k] along the row at [o] (edges clamped), in place.
  static void _kernelRow(Float32List a, int o, int w, Float64List k, Float32List tmp) {
    final r = k.length ~/ 2;
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      if (x >= r && x < w - r) {
        final b = o + x - r;
        for (var j = 0; j < k.length; j++) {
          s += a[b + j] * k[j];
        }
      } else {
        for (var j = 0; j < k.length; j++) {
          final xi = x - r + j;
          s += a[o + (xi < 0 ? 0 : (xi >= w ? w - 1 : xi))] * k[j];
        }
      }
      tmp[x] = s;
    }
    a.setRange(o, o + w, tmp);
  }

  /// Box blur of radius [r] along the row at [o] (edges clamped), in place.
  static void _boxRow(Float32List a, int o, int w, int r, Float32List tmp) {
    if (r <= 0) return;
    final inv = 1 / (2 * r + 1);
    var sum = 0.0;
    for (var j = -r; j <= r; j++) {
      sum += a[o + (j < 0 ? 0 : (j >= w ? w - 1 : j))];
    }
    for (var x = 0; x < w; x++) {
      tmp[x] = sum * inv;
      final add = x + r + 1, sub = x - r;
      sum += a[o + (add >= w ? w - 1 : add)] - a[o + (sub < 0 ? 0 : sub)];
    }
    a.setRange(o, o + w, tmp);
  }

  /// Box blur of radius [r] down the columns for rows [lo + r, hi - r),
  /// reading rows [lo, hi); in place (a sliding window of row sums).
  static void _boxColumns(Float32List a, int w, int lo, int hi, int r) {
    if (r <= 0 || hi - lo <= 2 * r) return;
    final inv = 1 / (2 * r + 1);
    final sum = Float64List(w);
    for (var y = lo; y <= lo + 2 * r; y++) {
      final o = y * w;
      for (var x = 0; x < w; x++) {
        sum[x] += a[o + x];
      }
    }
    // Rows are overwritten as we go, so keep the originals the window
    // still needs (the last 2r + 1).
    final ring = Float32List((2 * r + 1) * w);
    for (var y = lo; y <= lo + 2 * r; y++) {
      ring.setRange(((y - lo) % (2 * r + 1)) * w, ((y - lo) % (2 * r + 1) + 1) * w, a, y * w);
    }
    for (var y = lo + r; y < hi - r; y++) {
      final o = y * w;
      for (var x = 0; x < w; x++) {
        a[o + x] = sum[x] * inv;
      }
      final add = y + r + 1;
      if (add >= hi) break;
      final slot = ((y - r) - lo) % (2 * r + 1);
      final so = slot * w, ao = add * w;
      for (var x = 0; x < w; x++) {
        final v = a[ao + x];
        sum[x] += v - ring[so + x];
        ring[so + x] = v;
      }
    }
  }
}

/// The film's expected response (developed share against exposure) and its
/// inverse, built once per film.
class _Response {
  _Response(GrainFormation g) {
    final rnd = math.Random(20251025);
    const ns = 512;
    final sens = Float64List(ns);
    for (var i = 0; i < ns; i += 2) {
      final u1 = rnd.nextDouble() + 1e-12, u2 = rnd.nextDouble();
      final r = math.sqrt(-2 * math.log(u1));
      sens[i] = math.exp(g.spread * r * math.cos(2 * math.pi * u2));
      sens[i + 1] = math.exp(g.spread * r * math.sin(2 * math.pi * u2));
    }
    const fN = GrainFormer._fN, iN = GrainFormer._iN, maxE = GrainFormer._maxE;
    f = Float64List(fN + 1);
    for (var i = 0; i <= fN; i++) {
      final e = i / fN * maxE;
      var s = 0.0;
      for (var k = 0; k < ns; k++) {
        s += 1 - math.exp(-g.speed * e * sens[k]);
      }
      f[i] = g.fog + (1 - g.fog) * s / ns;
    }
    d0 = f[0];
    d1 = f[fN];
    inv = Float64List(iN + 1);
    var j = 0;
    for (var i = 0; i <= iN; i++) {
      final d = d0 + (d1 - d0) * i / iN;
      while (j < fN && f[j + 1] < d) {
        j++;
      }
      final a = f[j], b = f[math.min(fN, j + 1)];
      final t = b > a ? ((d - a) / (b - a)).clamp(0.0, 1.0) : 0.0;
      inv[i] = (j + t) / fN * maxE;
    }
  }

  late final Float64List f, inv;
  late final double d0, d1;
}
