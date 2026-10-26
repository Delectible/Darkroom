import 'dart:math' as math;
import 'dart:typed_data';

import 'color_math.dart';
import 'film_defects.dart';
import 'film_lut.dart';
import 'film_process.dart';
import 'film_profile.dart';
import 'grain_field.dart';
import 'grain_formation.dart';

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

  /// Grain is most visible in the mid-tones (plus [highlights] more toward
  /// white, for B&W negatives); deep blacks stay clean.
  static double grainWeight(double l, [double highlights = 0]) =>
      0.22 + 3.1 * l * (1 - l) + highlights * l * l;

  /// Grain finer than a pixel can't be drawn: it averages out. Returns the
  /// drawn texel size (>= 1 px) and the matching amplitude scale, so a
  /// preview or a small export looks like the full photo seen at that size.
  static (double texel, double gain) grainTexel(double framePx, double resolution) {
    final t = framePx / resolution;
    return t >= 1 ? (t, 1.0) : (1.0, t);
  }

  /// Halation threshold / gain on display-linear luminance.
  static const double halThreshold = 0.82;
  static const double halGain = 2.2;

  /// Halation radius as a fraction of the frame height.
  static const double halRadius = 0.014;
}

/// Full-resolution film renderer for stills (runs in the photo isolate while
/// the print develops). In place on an interleaved RGB8 buffer; scratch
/// memory is the LUT, one 512^2 grain tile and two 1/8-resolution halation
/// maps. See [FilmProcess] for what happens beyond the colour curve.
class FilmRenderer {
  FilmRenderer(
    this.profile, {
    required this.seed,
    int? rollSeed,
    this.grain = GrainStrength.normal,
    this.nominal = false,
    this.forceEv,
    this.sceneEv,
    this.throttle = 0,
  }) : dev = nominal ? const Development() : Development.roll(rollSeed ?? seed, profile.process.chemistry),
       field = GrainField.generate() {
    lut = FilmLut.build(profile, dev: dev);
  }

  final FilmProfile profile;
  final int seed;
  final GrainStrength grain;

  /// Exactly as metered by the phone: no camera meter, no exposure drift,
  /// no roll-to-roll development (calibration and tests).
  final bool nominal;

  /// Exposure in stops from the phone's, instead of metering (previews).
  final double? forceEv;

  /// The scene's real brightness (EV at ISO 100, from the phone's shutter,
  /// ISO and aperture); null = unknown. Too dark for the film's speed and
  /// the frame comes out under (no flash).
  final double? sceneEv;

  /// Grain formation rests this fraction of its work time after each strip
  /// so a develop never pins a core (the app passes 0.5; tools 0).
  final double throttle;
  final Development dev;
  late final FilmLut lut;
  final GrainField field;

  /// Exposure the last [render] gave the frame, in stops from the phone's.
  double lastEv = 0;

  void render(Uint8List data, int w, int h, {required double flash}) {
    if (!nominal) profile.lens?.apply(data, w, h);
    final pr = profile.process;
    final rnd = math.Random(seed);
    final drift = (rnd.nextDouble() * 2 - 1) * profile.exposureDrift;
    final light = nominal ? const [1.0, 1.0, 1.0] : pr.lightGain(sceneEv);
    final tint = [
      (1 + (rnd.nextDouble() - 0.5) * 0.02) * (1 - 0.03 * flash) * light[0],
      light[1],
      (1 + (rnd.nextDouble() - 0.5) * 0.02) * (1 + 0.06 * flash) * light[2],
    ];
    final flashAmt = flash * profile.flashStrength;

    // sRGB8 -> linear
    final toLin = Float64List(256);
    for (var i = 0; i < 256; i++) {
      toLin[i] = ColorMath.srgbToLinear(i / 255);
    }

    // --- exposure: the camera's meter, the roll, the frame ---------------
    var ev = 0.0;
    if (forceEv != null) {
      ev = forceEv!;
    } else if (!nominal) {
      ev = drift + dev.density + pr.meter * (1 - flash) * _meterEv(data, w, h, toLin, pr.meterKey);
      if (sceneEv != null && flash == 0) ev -= pr.underFor(sceneEv!);
    }
    lastEv = ev;
    // The lab scan pulls most of an exposure error back; the film's curve
    // only sees what's left. What the scan can't undo is the character of
    // a thin or dense negative (fog, tint, grain, saturation, below).
    final gainE = math.pow(2, ev * (1 - pr.scanFix)).toDouble();
    final under = math.max(0.0, -ev), over = math.max(0.0, ev);

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
      expo[i] = FilmSpatial.exposure(math.sqrt(i / (expoN - 1)), profile.vignette, flashAmt) * gainE;
    }
    final dx2 = Float64List(w);
    for (var x = 0; x < w; x++) {
      final d = ((x + 0.5) / w - 0.5) * 2.0;
      dx2[x] = d * d * 0.5;
    }

    final fog = pr.underFog * under;
    final ut = [pr.underTint[0] * under, pr.underTint[1] * under, pr.underTint[2] * under];
    final sat = math.max(0.4, 1 + pr.overSaturation * over);
    final warm = pr.overWarmth * over;

    final halo = profile.halation > 0 ? _halationMaps(data, w, h, toLin, gainE, flashAmt) : null;
    final hw = (w + 7) ~/ 8, hh = (h + 7) ~/ 8;
    final hc = profile.halationColor;
    final spread = pr.halationSpread, bloom = pr.bloom;

    // --- grain ------------------------------------------------------------
    final (texel, gain) = FilmSpatial.grainTexel(h.toDouble(), profile.grainResolution * grain.resolution);
    final expoGrain = (1 + pr.underGrain * under) * math.max(0.4, 1 - pr.overGrain * over);
    final amount = profile.grainAmount * pr.grainGain * grain.factor * gain * expoGrain;
    final chroma = profile.grainChroma;
    final inv = 1 / texel; // grain texels per image px
    final coarse = 1 / math.max(1.0, pr.shadowCoarse);
    final ls = [1 / pr.layerScale[0], 1 / pr.layerScale[1], 1 / pr.layerScale[2]];
    final ox = rnd.nextDouble() * field.size, oy = rnd.nextDouble() * field.size;
    // Crystal grain is noise in log exposure: scale it so that at mid-grey
    // it shows as [amount] once the curve has shaped it.
    final crystal = pr.crystal * amount / _slope();
    final dye = (1 - pr.crystal) * amount;
    final hi = profile.grainHighlights;
    final out = List<double>.filled(3, 0);
    final n = List<double>.filled(3, 0);

    // Image made of grains (stocks with a GrainFormation): formed at the
    // film's resolution, read back bilinearly. Replaces the grain texture.
    final form = pr.formation;
    // The negative is exposed by the full error (an underexposed frame has
    // few developed grains, so it's grainy); the scan then pulls most of
    // the brightness back (the rest is in gainE above).
    final negGain = math.pow(2, ev * pr.scanFix).toDouble();
    GrainFormer? former;
    var wh = 0, ww = 0, keep = 1, done = 0;
    Uint8List? ring;
    Int32List? wxi;
    Float64List? wtx;
    if (form != null && amount > 0) {
      // The frame's short side is the film's frame height.
      final hn = form.frameHeight * grain.resolution;
      final short = math.min(w, h).toDouble();
      final k = math.min(1.0, hn / short);
      wh = math.max(1, (h * k).round());
      ww = math.max(1, (w * k).round());
      final size = short * k / hn;
      final sx = Int32List(ww + 1);
      for (var i = 0; i <= ww; i++) {
        sx[i] = math.min(w, (i * w / ww).floor());
      }
      former = GrainFormer(
        form,
        ww: ww,
        wh: wh,
        seed: seed,
        sizeScale: size,
        // Strong grain is coarser too, which reads a little softer at the
        // same noise: fewer crystals again by the resolution makes up for it.
        crystals: form.crystals * grain.resolution / (grain.factor * grain.factor * size * size),
        throttle: throttle,
        exposureRow: (wy, er, eg, eb) {
          final y = wy < 0 ? 0 : (wy >= wh ? wh - 1 : wy);
          final ya = math.min(h - 1, (y * h / wh).floor());
          final yb = math.max(ya + 1, math.min(h, ((y + 1) * h / wh).floor()));
          final dy = (((ya + yb) * 0.5) / h - 0.5) * 2.0;
          final dy2 = dy * dy * 0.5;
          for (var x = 0; x < ww; x++) {
            final xa = math.min(w - 1, sx[x]), xb = math.max(xa + 1, sx[x + 1]);
            var r = 0.0, g = 0.0, b = 0.0;
            for (var yy = ya; yy < yb; yy++) {
              final old = yy < done;
              final src = old ? ring! : data;
              var q = ((old ? yy % keep : yy) * w + xa) * 3;
              for (var xx = xa; xx < xb; xx++, q += 3) {
                r += toLin[src[q]];
                g += toLin[src[q + 1]];
                b += toLin[src[q + 2]];
              }
            }
            final dx = (((xa + xb) * 0.5) / w - 0.5) * 2.0;
            var qi = ((dx * dx * 0.5 + dy2) * (expoN - 1)).toInt();
            if (qi > expoN - 1) qi = expoN - 1;
            final e = expo[qi] * negGain / ((yb - ya) * (xb - xa));
            er[x] = r * e * tint[0];
            eg[x] = g * e * tint[1];
            eb[x] = b * e * tint[2];
          }
        },
      );
      // The main loop writes the finished photo over [data] row by row,
      // but a new strip still reads a few source rows above it: keep the
      // originals of recent rows in a ring.
      keep = ((former.pad + 2) * h / wh).ceil() + 2;
      ring = Uint8List(keep * w * 3);
      wxi = Int32List(w);
      wtx = Float64List(w);
      for (var x = 0; x < w; x++) {
        final f = ((x + 0.5) * ww / w - 0.5).clamp(0.0, ww - 1.0);
        final i = math.min(ww - 2, f.floor());
        wxi[x] = math.max(0, i);
        wtx[x] = ww < 2 ? 0 : (f - wxi[x]).clamp(0.0, 1.0);
      }
    }
    final formed = former != null;

    for (var y = 0; y < h; y++) {
      final dy = ((y + 0.5) / h - 0.5) * 2.0;
      final dy2 = dy * dy * 0.5;
      final gy = y * inv + oy;
      final hy = (y + 0.5) / 8 - 0.5;
      var wy0 = 0, wy1 = 0;
      var wty = 0.0;
      if (formed) {
        ring!.setRange((y % keep) * w * 3, (y % keep + 1) * w * 3, data, y * w * 3);
        done = y + 1;
        final f = ((y + 0.5) * wh / h - 0.5).clamp(0.0, wh - 1.0);
        wy0 = f.floor();
        wy1 = math.min(wh - 1, wy0 + 1);
        wty = f - wy0;
        former.ensure(wy0, wy1);
      }
      for (var x = 0; x < w; x++) {
        final p = (y * w + x) * 3;
        var qi = ((dx2[x] + dy2) * (expoN - 1)).toInt();
        if (qi > expoN - 1) qi = expoN - 1;
        final e = expo[qi];
        var sr = shape[math.min(shapeN, (toLin[data[p]] * e * tint[0] * shapeScale).toInt())];
        var sg = shape[math.min(shapeN, (toLin[data[p + 1]] * e * tint[1] * shapeScale).toInt())];
        var sb = shape[math.min(shapeN, (toLin[data[p + 2]] * e * tint[2] * shapeScale).toInt())];
        if (formed) {
          final x0 = wxi![x], x1 = math.min(ww - 1, x0 + 1), tx = wtx![x];
          double at(int c) {
            final a = former!.at(c, x0, wy0), b = former.at(c, x1, wy0);
            final cc = former.at(c, x0, wy1), d = former.at(c, x1, wy1);
            return ((a + (b - a) * tx) * (1 - wty) + (cc + (d - cc) * tx) * wty) / negGain;
          }

          sr = shape[math.min(shapeN, (at(0) * shapeScale).toInt())];
          sg = shape[math.min(shapeN, (at(1) * shapeScale).toInt())];
          sb = shape[math.min(shapeN, (at(2) * shapeScale).toInt())];
        }

        // One grain pattern per pixel: the big, fast crystals (coarse) win
        // in the shadows, the fine ones in the highlights; each dye layer
        // clouds at its own size.
        final tone = 0.2126 * sr + 0.7152 * sg + 0.0722 * sb; // ~log exposure, 0..1
        if (amount > 0 && !formed) {
          final gx = x * inv + ox;
          final cw = 1 - ColorMath.smoothstep(0.35, 0.75, tone);
          var m = field.sample(gx, gy, 0);
          if (cw > 0.01) {
            final c = field.sample(gx * coarse + 97.0, gy * coarse + 41.0, 0);
            m = (m * (1 - cw) + c * cw) / math.sqrt((1 - cw) * (1 - cw) + cw * cw);
          }
          if (chroma > 0) {
            for (var c = 0; c < 3; c++) {
              n[c] =
                  m * (1 - chroma) + field.sample(gx * ls[c] + 31.0 * c, gy * ls[c] + 17.0 * c, c) * chroma;
            }
          } else {
            n[0] = n[1] = n[2] = m;
          }
          if (crystal > 0) {
            // Shaped like the dye grain: quiet in the deep shadows and the
            // brightest highlights, so skies stay clean.
            final j = crystal * FilmSpatial.grainWeight(tone, hi);
            sr += n[0] * j;
            sg += n[1] * j;
            sb += n[2] * j;
          }
        }
        lut.sample(sr, sg, sb, out);
        var r = out[0], g = out[1], b = out[2];

        if (halo != null) {
          final fx = (x + 0.5) / 8 - 0.5;
          final core = _bilinear(halo.$1, hw, hh, fx, hy), wide = _bilinear(halo.$2, hw, hh, fx, hy);
          final hv = (core * (1 - spread) + wide * spread) * profile.halation;
          if (hv > 0) {
            r += hc[0] * hv * (1 - r);
            g += hc[1] * hv * (1 - g);
            b += hc[2] * hv * (1 - b);
          }
          final bv = wide * bloom;
          if (bv > 0) {
            r += bv * (1 - r);
            g += bv * (1 - g);
            b += bv * (1 - b);
          }
        }

        if (dye > 0 && !formed) {
          final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final a = dye * FilmSpatial.grainWeight(l, hi);
          r += n[0] * a;
          g += n[1] * a;
          b += n[2] * a;
        }

        if (ev != 0) {
          final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          if (sat != 1) {
            r = l + (r - l) * sat;
            g = l + (g - l) * sat;
            b = l + (b - l) * sat;
          }
          if (under > 0) {
            final sh = (1 - l) * (1 - l);
            r = fog + (1 - fog) * r + ut[0] * sh;
            g = fog + (1 - fog) * g + ut[1] * sh;
            b = fog + (1 - fog) * b + ut[2] * sh;
          }
          if (warm != 0) {
            final hl = l * l;
            r += warm * hl;
            b -= warm * hl;
          }
        }

        data[p] = r <= 0 ? 0 : (r >= 1 ? 255 : (r * 255 + 0.5).toInt());
        data[p + 1] = g <= 0 ? 0 : (g >= 1 ? 255 : (g * 255 + 0.5).toInt());
        data[p + 2] = b <= 0 ? 0 : (b >= 1 ? 255 : (b * 255 + 0.5).toInt());
      }
    }
    FilmDefects(
      amount: profile.defects,
      negative: profile.negative,
      colour: !profile.mono,
      seed: seed,
    ).apply(data, w, h);
  }

  /// Stops the camera's centre-weighted meter would move this frame from
  /// the phone's exposure (its log-average luminance against [key]).
  static double _meterEv(Uint8List data, int w, int h, Float64List toLin, double key) {
    final step = math.max(1, math.max(w, h) ~/ 160);
    var sum = 0.0, wsum = 0.0;
    for (var y = step ~/ 2; y < h; y += step) {
      final dy = ((y + 0.5) / h - 0.5) * 2.0;
      for (var x = step ~/ 2; x < w; x += step) {
        final dx = ((x + 0.5) / w - 0.5) * 2.0;
        final r = math.sqrt((dx * dx + dy * dy) * 0.5);
        final wt = 1 + 2 * (1 - ColorMath.smoothstep(0.25, 0.7, r));
        final p = (y * w + x) * 3;
        final l = 0.2126 * toLin[data[p]] + 0.7152 * toLin[data[p + 1]] + 0.0722 * toLin[data[p + 2]];
        sum += wt * math.log(math.max(l, 1e-3));
        wsum += wt;
      }
    }
    if (wsum == 0) return 0;
    final ev = math.log(key / math.exp(sum / wsum)) / math.ln2;
    return ev.clamp(-FilmProcess.maxMeterEv, FilmProcess.maxMeterEv);
  }

  /// Output luminance per unit of shaper coordinate at mid-grey.
  double _slope() {
    final s0 = LutShaper.encode(0.18), d = 0.02;
    final a = List<double>.filled(3, 0), b = List<double>.filled(3, 0);
    lut.sample(s0 - d, s0 - d, s0 - d, a);
    lut.sample(s0 + d, s0 + d, s0 + d, b);
    double l(List<double> v) => 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2];
    return math.max(0.05, (l(b) - l(a)) / (2 * d));
  }

  /// Blurred highlight energy at 1/8 resolution, values ~0..1: a tight
  /// core and a wide skirt (light bounced back from the film base).
  (Float32List, Float32List) _halationMaps(
    Uint8List data,
    int w,
    int h,
    Float64List toLin,
    double gainE,
    double flashAmt,
  ) {
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
            FilmSpatial.exposure(math.sqrt((dx * dx + dy * dy) * 0.5), profile.vignette, flashAmt) * gainE;
        final l = (0.2126 * toLin[data[p]] + 0.7152 * toLin[data[p + 1]] + 0.0722 * toLin[data[p + 2]]) * e;
        m[row + x ~/ 8] += math.max(0, l - FilmSpatial.halThreshold) * FilmSpatial.halGain;
        cnt[row + x ~/ 8]++;
      }
    }
    for (var i = 0; i < m.length; i++) {
      if (cnt[i] > 0) m[i] /= cnt[i];
    }
    final wide = Float32List.fromList(m);
    _gauss(m, bw, bh, math.max(0.6, FilmSpatial.halRadius * h / 8));
    _gauss(wide, bw, bh, math.max(1.5, FilmSpatial.halRadius * 3.5 * h / 8));
    for (var i = 0; i < m.length; i++) {
      m[i] = math.min(1.0, m[i] * 2.5);
      wide[i] = math.min(1.0, wide[i] * 6.0);
    }
    return (m, wide);
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
