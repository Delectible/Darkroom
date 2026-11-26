import 'dart:math' as math;
import 'dart:typed_data';

/// The odd physical flaw a real roll picks up, rolled per frame so no two
/// prints share them and most have none worth noticing:
///
///  * dust specks: tiny, irregular, bright (dust on a negative blocks light,
///    so it scans white; dark on positive/instant film)
///  * a fibre or hair: a thin curl
///  * a scratch: faint, long, running along the film (the frame's long side)
///    as the strip was dragged through the camera or the lab
///  * a light leak: a warm glow creeping in from one long edge
///
/// Instant film gets its chemistry's flaws instead: pinprick sparkles, a
/// little dark dust, milky streaks up from the rollers, a ragged undeveloped
/// band along an edge, a fogged corner.
///
/// Only the developed still gets them; the viewfinder shows the scene.
class FilmDefects {
  FilmDefects({
    required this.amount,
    required this.negative,
    this.instant = false,
    this.colour = true,
    required int seed,
  }) : _rnd = math.Random(seed ^ 0x5DEECE6);

  /// 0 = clean, 1 = a well-handled consumer roll.
  final double amount;

  /// Negative film (dust scans white) vs positive / instant (dust is dark).
  final bool negative;

  /// Instant film: its chemistry's flaws instead of dust and scratches.
  final bool instant;

  /// Colour film (a scratch can pick up a dye tint); false for B&W.
  final bool colour;
  final math.Random _rnd;

  /// What this frame got (for tests and the lab stamp, if ever).
  final List<String> applied = [];

  void apply(Uint8List data, int w, int h) {
    if (amount <= 0) return;
    // Sizes in pixels of a ~12MP frame; scaled to this one.
    final s = math.min(w, h) / 2000;
    // At most one flaw a frame, and most frames none: one roll for whether
    // this frame got anything, a second for what.
    final odds = instant ? 0.45 : (negative ? 0.33 : 0.25);
    if (_rnd.nextDouble() >= odds * amount) return;
    final pick = _rnd.nextDouble();
    if (instant) {
      if (pick < 0.4) {
        final n = 1 + _rnd.nextInt(3);
        for (var i = 0; i < n; i++) {
          _sparkle(data, w, h, s);
        }
        applied.add('sparkle x$n');
      } else if (pick < 0.6) {
        _streaks(data, w, h, s);
        applied.add('roller streaks');
      } else if (pick < 0.78) {
        _chemistryEdge(data, w, h);
        applied.add('chemistry edge');
      } else if (pick < 0.9) {
        _cornerFog(data, w, h);
        applied.add('corner fog');
      } else {
        _speck(data, w, h, s);
        applied.add('dust x1');
      }
      return;
    }
    if (!negative) {
      // Slide film: a speck of dust (dark on a positive) or a faint scratch.
      if (pick < 0.7) {
        _speck(data, w, h, s);
        applied.add('dust x1');
      } else {
        _scratch(data, w, h, s);
        applied.add('scratch');
      }
      return;
    }
    if (pick < 0.6) {
      final n = _rnd.nextDouble() < 0.8 ? 1 : 2;
      for (var i = 0; i < n; i++) {
        _speck(data, w, h, s);
      }
      applied.add('dust x$n');
    } else if (pick < 0.78) {
      _scratch(data, w, h, s);
      applied.add('scratch');
    } else if (pick < 0.93) {
      _hair(data, w, h, s);
      applied.add('hair');
    } else {
      _leak(data, w, h);
      applied.add('light leak');
    }
  }

  /// A pinprick where the reagent missed: a tiny bright cyan-white dot.
  void _sparkle(Uint8List d, int w, int h, double s) {
    final cx = _rnd.nextDouble() * w, cy = _rnd.nextDouble() * h;
    final r = (0.6 + 1.2 * _rnd.nextDouble()) * s;
    final a = 0.45 + 0.45 * _rnd.nextDouble();
    final ext = (r + 1.5).ceil();
    for (var y = (cy - ext).floor(); y <= (cy + ext).ceil(); y++) {
      for (var x = (cx - ext).floor(); x <= (cx + ext).ceil(); x++) {
        final dist = math.sqrt((x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy));
        _mark(d, w, h, x, y, (r + 0.5 - dist).clamp(0.0, 1.0) * a, 0.95, const [0.86, 0.96, 1.0]);
      }
    }
  }

  /// Faint milky lines running up from the roller side, where the reagent
  /// spread unevenly.
  void _streaks(Uint8List d, int w, int h, double s) {
    final n = 1 + _rnd.nextInt(3);
    var x0 = _rnd.nextDouble() * w;
    for (var k = 0; k < n; k++) {
      var x = x0 + (_rnd.nextDouble() - 0.5) * 0.08 * w;
      final length = h * (0.25 + 0.55 * _rnd.nextDouble());
      final opacity = 0.09 + 0.12 * _rnd.nextDouble();
      final pts = <(double, double, double)>[];
      for (var t = 0.0; t < length; t += 0.5) {
        x += (_rnd.nextDouble() - 0.5) * 0.05;
        final fade = math.pow(1 - t / length, 0.7).toDouble();
        pts.add((x, h - 1 - t, opacity * fade));
      }
      _stroke(d, w, h, pts, (1.5 + 2.5 * _rnd.nextDouble()) * s, 0.92, const [1.0, 0.97, 0.88]);
      x0 = x;
    }
  }

  /// A ragged band along one edge where the chemistry didn't reach: pale
  /// cream or blue-grey, undeveloped.
  void _chemistryEdge(Uint8List d, int w, int h) {
    final pick = _rnd.nextDouble();
    // 0 bottom, 1 top, 2 left, 3 right
    final edge = pick < 0.7 ? 0 : (pick < 0.85 ? 1 : (_rnd.nextBool() ? 2 : 3));
    final along = edge < 2 ? w : h;
    final base = math.min(w, h) * (0.006 + 0.014 * _rnd.nextDouble());
    final feather = math.max(2.0, base * 0.45);
    final strength = 0.33 + 0.27 * _rnd.nextDouble();
    final col = _rnd.nextDouble() < 0.6 ? const [0.92, 0.88, 0.72] : const [0.58, 0.67, 0.78];
    final waves = [
      for (var i = 0; i < 4; i++)
        (0.6 + _rnd.nextDouble() * 2.2 * (i + 1), _rnd.nextDouble() * math.pi * 2, 0.45 / (i + 1)),
    ];
    final depth = Float64List(along);
    for (var t = 0; t < along; t++) {
      var v = 0.0;
      for (final (f, ph, a) in waves) {
        v += a * math.sin(t / along * f * math.pi * 2 + ph);
      }
      // Fades out toward the ends of the edge, as the spread thins.
      final ends = math.sin(math.pi * t / along);
      depth[t] = base * (0.35 + 0.65 * ends) * (1 + v);
    }
    final reach = (base * 2.2 + feather).ceil();
    for (var t = 0; t < along; t++) {
      for (var k = 0; k < reach; k++) {
        final a = strength * ColorEdge.smooth(depth[t] + feather, depth[t] - feather, k.toDouble());
        if (a <= 0.004) continue;
        final (x, y) = switch (edge) {
          0 => (t, h - 1 - k),
          1 => (t, k),
          2 => (k, t),
          _ => (w - 1 - k, t),
        };
        final p = (y * w + x) * 3;
        for (var c = 0; c < 3; c++) {
          d[p + c] = (d[p + c] + (col[c] * 255 - d[p + c]) * a).round().clamp(0, 255);
        }
      }
    }
  }

  /// A corner fogged pale by light piping in at the edge of the pack.
  void _cornerFog(Uint8List d, int w, int h) {
    final cx = _rnd.nextBool() ? 0.0 : w - 1.0, cy = _rnd.nextBool() ? 0.0 : h - 1.0;
    final r = math.min(w, h) * (0.22 + 0.22 * _rnd.nextDouble());
    final strength = 0.22 + 0.23 * _rnd.nextDouble();
    const col = [1.0, 0.96, 0.86];
    final x0 = math.max(0, (cx - r * 2).floor()), x1 = math.min(w - 1, (cx + r * 2).ceil());
    final y0 = math.max(0, (cy - r * 2).floor()), y1 = math.min(h - 1, (cy + r * 2).ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final q = ((x - cx) * (x - cx) + (y - cy) * (y - cy)) / (r * r);
        final k = strength * math.exp(-q);
        if (k < 0.003) continue;
        final p = (y * w + x) * 3;
        for (var c = 0; c < 3; c++) {
          final v = d[p + c] / 255;
          d[p + c] = ((1 - (1 - v) * (1 - col[c] * k)) * 255).round().clamp(0, 255);
        }
      }
    }
  }

  /// Blends [tone] (0 black .. 1 white) into the pixel by [a].
  void _mark(Uint8List d, int w, int h, int x, int y, double a, double tone, [List<double>? tint]) {
    if (x < 0 || y < 0 || x >= w || y >= h || a <= 0) return;
    final p = (y * w + x) * 3;
    for (var c = 0; c < 3; c++) {
      final t = (tint == null ? tone : tone * tint[c]) * 255;
      d[p + c] = (d[p + c] + (t - d[p + c]) * math.min(1.0, a)).round().clamp(0, 255);
    }
  }

  double get _tone => negative ? 0.97 : 0.06;

  /// An irregular blob: a few overlapping soft discs.
  void _speck(Uint8List d, int w, int h, double s) {
    final cx = _rnd.nextDouble() * w, cy = _rnd.nextDouble() * h;
    final opacity = 0.52 + 0.45 * _rnd.nextDouble();
    final parts = 1 + _rnd.nextInt(3);
    for (var k = 0; k < parts; k++) {
      final r = (0.8 + 2.4 * _rnd.nextDouble()) * s;
      final ox = cx + (_rnd.nextDouble() - 0.5) * 3 * s, oy = cy + (_rnd.nextDouble() - 0.5) * 3 * s;
      final ext = (r + 1.5).ceil();
      for (var y = (oy - ext).floor(); y <= (oy + ext).ceil(); y++) {
        for (var x = (ox - ext).floor(); x <= (ox + ext).ceil(); x++) {
          final dist = math.sqrt((x + 0.5 - ox) * (x + 0.5 - ox) + (y + 0.5 - oy) * (y + 0.5 - oy));
          final cov = (r + 0.5 - dist).clamp(0.0, 1.0);
          _mark(d, w, h, x, y, cov * opacity, _tone);
        }
      }
    }
  }

  /// Draws a soft line of [width] through [pts], opacity per point.
  void _stroke(
    Uint8List d,
    int w,
    int h,
    List<(double, double, double)> pts,
    double width,
    double tone, [
    List<double>? tint,
  ]) {
    final hw = width / 2;
    final ext = (hw + 1).ceil();
    // Max coverage per pixel, so overlapping stamps don't build up.
    final cover = <int, double>{};
    for (final (px, py, a) in pts) {
      for (var y = (py - ext).floor(); y <= (py + ext).ceil(); y++) {
        for (var x = (px - ext).floor(); x <= (px + ext).ceil(); x++) {
          if (x < 0 || y < 0 || x >= w || y >= h) continue;
          final dist = math.sqrt((x + 0.5 - px) * (x + 0.5 - px) + (y + 0.5 - py) * (y + 0.5 - py));
          final cov = (hw + 0.5 - dist).clamp(0.0, 1.0) * a;
          if (cov <= 0) continue;
          final key = y * w + x;
          if ((cover[key] ?? 0) < cov) cover[key] = cov;
        }
      }
    }
    cover.forEach((key, a) => _mark(d, w, h, key % w, key ~/ w, a, tone, tint));
  }

  /// A fibre: a short random-walk curl.
  void _hair(Uint8List d, int w, int h, double s) {
    var x = _rnd.nextDouble() * w, y = _rnd.nextDouble() * h;
    var angle = _rnd.nextDouble() * math.pi * 2;
    var turn = (_rnd.nextDouble() - 0.5) * 0.02;
    final length = (120 + 260 * _rnd.nextDouble()) * s;
    final opacity = 0.52 + 0.38 * _rnd.nextDouble();
    final pts = <(double, double, double)>[];
    for (var t = 0.0; t < length; t += 0.5) {
      pts.add((x, y, opacity));
      turn = turn * 0.995 + (_rnd.nextDouble() - 0.5) * 0.0016;
      angle += turn;
      x += math.cos(angle) * 0.5;
      y += math.sin(angle) * 0.5;
    }
    _stroke(d, w, h, pts, 1.3 * s, _tone);
  }

  /// A long faint scratch along the film, wandering slightly, fading in and
  /// out. Emulsion scratches pick up a tint from the dye layer they cut.
  void _scratch(Uint8List d, int w, int h, double s) {
    final alongX = w >= h;
    final len = alongX ? w : h, across = alongX ? h : w;
    final start = _rnd.nextDouble() * len * 0.5;
    final end = start + len * (0.35 + 0.65 * _rnd.nextDouble());
    var pos = (0.08 + 0.84 * _rnd.nextDouble()) * across;
    final drift = (_rnd.nextDouble() - 0.5) * 0.02;
    final opacity = 0.22 + 0.2 * _rnd.nextDouble();
    final tint = negative && colour && _rnd.nextDouble() < 0.4 ? const [0.82, 1.0, 1.0] : null;
    final pts = <(double, double, double)>[];
    for (var t = start; t < math.min(end, len.toDouble()); t += 0.5) {
      pos += drift * 0.5 + (_rnd.nextDouble() - 0.5) * 0.02;
      final u = (t - start) / (end - start);
      final fade = math.sin(math.pi * u) * (0.7 + 0.3 * math.sin(t / (40 * s)));
      pts.add(alongX ? (t, pos, opacity * fade) : (pos, t, opacity * fade));
    }
    _stroke(d, w, h, pts, 1.1 * s, negative ? 0.95 : 0.1, tint);
  }

  /// Warm glow from one long edge, screen-blended.
  void _leak(Uint8List d, int w, int h) {
    final alongX = w >= h;
    final fromLow = _rnd.nextBool();
    final across = alongX ? h : w;
    final depth = across * (0.06 + 0.1 * _rnd.nextDouble());
    final strength = 0.27 + 0.3 * _rnd.nextDouble();
    // Where along the edge it's brightest, and how wide.
    final len = alongX ? w : h;
    final centre = _rnd.nextDouble() * len, spread = len * (0.25 + 0.35 * _rnd.nextDouble());
    const col = [1.0, 0.42, 0.12];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final a = alongX ? y : x, b = alongX ? x : y;
        final dist = fromLow ? a.toDouble() : (across - 1 - a).toDouble();
        if (dist > depth * 3) continue;
        final along = (b - centre) / spread;
        final k = strength * math.exp(-dist / depth) * math.exp(-along * along);
        if (k < 0.003) continue;
        final p = (y * w + x) * 3;
        for (var c = 0; c < 3; c++) {
          final v = d[p + c] / 255;
          final add = col[c] * k;
          d[p + c] = ((1 - (1 - v) * (1 - add)) * 255).round().clamp(0, 255);
        }
      }
    }
  }
}

/// Smoothstep from [edge0] (0) to [edge1] (1); edges may run either way.
class ColorEdge {
  const ColorEdge._();

  static double smooth(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}
