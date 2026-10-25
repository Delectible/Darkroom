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
    _response();
    for (var c = 0; c < 3; c++) {
      _kernel[c] = _gaussKernel(math.max(0.35, g.clouds[c] * sizeScale));
    }
    _pad = _kernel.fold(0, (m, k) => math.max(m, k!.length ~/ 2));
  }

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

  final _kernel = List<Float64List?>.filled(3, null);
  late final int _pad;
  late final Float64List _f; // expected developed share over E in [0, _maxE]
  late final Float64List _inv; // E over D in [_d0, _d1]
  late double _d0, _d1;

  // Formed light (display-linear) for work rows [_base, _base + _rows).
  int _base = -1, _rows = 0;
  Float32List? _out;

  void _response() {
    final rnd = math.Random(20251025);
    const ns = 2048;
    final sens = Float64List(ns);
    for (var i = 0; i < ns; i += 2) {
      final u1 = rnd.nextDouble() + 1e-12, u2 = rnd.nextDouble();
      final r = math.sqrt(-2 * math.log(u1));
      sens[i] = math.exp(g.spread * r * math.cos(2 * math.pi * u2));
      sens[i + 1] = math.exp(g.spread * r * math.sin(2 * math.pi * u2));
    }
    _f = Float64List(_fN + 1);
    for (var i = 0; i <= _fN; i++) {
      final e = i / _fN * _maxE;
      var s = 0.0;
      for (var k = 0; k < ns; k++) {
        s += 1 - math.exp(-g.speed * e * sens[k]);
      }
      _f[i] = g.fog + (1 - g.fog) * s / ns;
    }
    _d0 = _f[0];
    _d1 = _f[_fN];
    _inv = Float64List(_iN + 1);
    var j = 0;
    for (var i = 0; i <= _iN; i++) {
      final d = _d0 + (_d1 - _d0) * i / _iN;
      while (j < _fN && _f[j + 1] < d) {
        j++;
      }
      final a = _f[j], b = _f[math.min(_fN, j + 1)];
      final t = b > a ? ((d - a) / (b - a)).clamp(0.0, 1.0) : 0.0;
      _inv[i] = (j + t) / _fN * _maxE;
    }
  }

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

  static Float64List _gaussKernel(double sigma) {
    final r = math.max(1, (sigma * 3).ceil());
    final k = Float64List(2 * r + 1);
    var s = 0.0;
    for (var i = -r; i <= r; i++) {
      k[i + r] = math.exp(-0.5 * (i / sigma) * (i / sigma));
      s += k[i + r];
    }
    for (var i = 0; i < k.length; i++) {
      k[i] /= s;
    }
    return k;
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

  /// Poisson(lambda) from pixel (x, y), stream [k].
  int _poisson(double lambda, int x, int y, int k) {
    if (lambda <= 0) return 0;
    if (lambda > 30) {
      final u1 = _u(x, y, k), u2 = _u(x, y, k + 101);
      final z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
      return math.max(0, (lambda + math.sqrt(lambda) * z + 0.5).floor());
    }
    final u = _u(x, y, k);
    var p = math.exp(-lambda), f = p;
    var n = 0;
    while (u > f && n < 200) {
      n++;
      p *= lambda / n;
      f += p;
    }
    return n;
  }

  /// Work rows a strip reads beyond its own (each side).
  int get pad => _pad;

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
    final counts = List.generate(3, (_) => Float32List(ww));
    final sh = g.shared, own = 1 - g.shared, n0 = crystals;
    for (var i = 0; i < rows; i++) {
      final wy = s0 - p + i;
      exposureRow(wy, er, eg, eb);
      for (var x = 0; x < ww; x++) {
        final fr = _fOf(er[x]), fg = _fOf(eg[x]), fb = _fOf(eb[x]);
        final fm = (fr + fg + fb) / 3;
        final common = _poisson(n0 * sh * fm, x, wy, 0).toDouble() / fm;
        counts[0][x] = common * fr + _poisson(n0 * own * fr, x, wy, 1);
        counts[1][x] = common * fg + _poisson(n0 * own * fg, x, wy, 2);
        counts[2][x] = common * fb + _poisson(n0 * own * fb, x, wy, 3);
      }
      for (var c = 0; c < 3; c++) {
        final k = _kernel[c]!, r = k.length ~/ 2, src = counts[c], dst = hb[c];
        final o = i * ww;
        for (var x = 0; x < ww; x++) {
          var s = 0.0;
          if (x >= r && x < ww - r) {
            for (var j = 0; j < k.length; j++) {
              s += src[x - r + j] * k[j];
            }
          } else {
            for (var j = 0; j < k.length; j++) {
              s += src[(x - r + j).clamp(0, ww - 1)] * k[j];
            }
          }
          dst[o + x] = s;
        }
      }
    }
    final out = _out != null && _out!.length >= n * ww * 3 ? _out! : Float32List(n * ww * 3);
    final invN = 1 / n0;
    final acc = Float64List(ww);
    for (var c = 0; c < 3; c++) {
      final k = _kernel[c]!, r = k.length ~/ 2, src = hb[c];
      for (var i = 0; i < n; i++) {
        final ci = i + p; // centre row in hb
        acc.fillRange(0, ww, 0);
        for (var j = 0; j < k.length; j++) {
          final o = (ci - r + j) * ww, kj = k[j];
          for (var x = 0; x < ww; x++) {
            acc[x] += src[o + x] * kj;
          }
        }
        var q = i * ww * 3 + c;
        for (var x = 0; x < ww; x++, q += 3) {
          out[q] = _eOf(acc[x] * invN);
        }
      }
    }
    _out = out;
    _base = s0;
    _rows = n;
  }
}
