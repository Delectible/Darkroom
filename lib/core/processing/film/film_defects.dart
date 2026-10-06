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
/// Only the developed still gets them; the viewfinder shows the scene.
class FilmDefects {
  FilmDefects({required this.amount, required this.negative, this.colour = true, required int seed})
    : _rnd = math.Random(seed ^ 0x5DEECE6);

  /// 0 = clean, 1 = a well-handled consumer roll.
  final double amount;

  /// Negative film (dust scans white) vs positive / instant (dust is dark).
  final bool negative;

  /// Colour film (a scratch can pick up a dye tint); false for B&W.
  final bool colour;
  final math.Random _rnd;

  /// What this frame got (for tests and the lab stamp, if ever).
  final List<String> applied = [];

  void apply(Uint8List data, int w, int h) {
    if (amount <= 0) return;
    // Sizes in pixels of a ~12MP frame; scaled to this one.
    final s = math.min(w, h) / 2000;

    final specks = _poisson(1.6 * amount);
    for (var i = 0; i < specks; i++) {
      _speck(data, w, h, s);
    }
    if (specks > 0) applied.add('dust x$specks');
    if (_rnd.nextDouble() < 0.12 * amount) {
      _hair(data, w, h, s);
      applied.add('hair');
    }
    if (_rnd.nextDouble() < 0.22 * amount) {
      _scratch(data, w, h, s);
      applied.add('scratch');
    }
    if (_rnd.nextDouble() < 0.06 * amount) {
      _leak(data, w, h);
      applied.add('light leak');
    }
  }

  int _poisson(double mean) {
    final l = math.exp(-mean);
    var k = 0;
    var p = _rnd.nextDouble();
    while (p > l) {
      k++;
      p *= _rnd.nextDouble();
    }
    return k;
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
    final opacity = 0.45 + 0.45 * _rnd.nextDouble();
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
    final opacity = 0.5 + 0.3 * _rnd.nextDouble();
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
    final opacity = 0.22 + 0.18 * _rnd.nextDouble();
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
    final strength = 0.18 + 0.2 * _rnd.nextDouble();
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
