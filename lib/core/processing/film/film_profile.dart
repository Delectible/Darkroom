import 'dart:math' as math;

import 'color_math.dart';
import 'film_process.dart';
import 'grain_formation.dart';

/// A hue-selective adjustment applied in OKLCh after the film curve.
class HueTweak {
  const HueTweak(this.hue, this.width, {this.shift = 0, this.chroma = 1, this.light = 0});

  /// Centre hue (OKLCh degrees: red ~29, skin/orange ~55, yellow ~110,
  /// green ~142, cyan ~195, sky ~235, blue ~264, magenta ~328).
  final double hue;

  /// Gaussian width in degrees.
  final double width;

  /// Hue rotation in degrees at the centre.
  final double shift;

  /// Chroma multiplier at the centre.
  final double chroma;

  /// OKLab lightness offset at the centre.
  final double light;
}

/// Everything that defines one film stock's look. Pure data; evaluated by
/// [FilmModel] into a 3D LUT that the live shader, the still renderer and
/// FFmpeg all share, so preview, photo and video match.
class FilmProfile {
  const FilmProfile({
    required this.id,
    this.mono = false,
    this.monoWeights = const [0.2126, 0.7152, 0.0722],
    this.matrix = const [1, 0, 0, 0, 1, 0, 0, 0, 1],
    this.balance = const [1, 1, 1],
    this.exposureEv = 0,
    required this.contrast,
    this.white = 1.0,
    this.saturation = 1.0,
    this.hues = const [],
    this.shadowLift = 0,
    this.highlightCap = 1.0,
    this.shadowTint = const [0, 0, 0],
    this.highlightTint = const [0, 0, 0],
    required this.grainAmount,
    this.grainChroma = 0.35,
    required this.grainResolution,
    this.halation = 0,
    this.halationColor = const [1.0, 0.38, 0.14],
    this.vignette = 0.15,
    this.flashStrength = 0.6,
    this.exposureDrift = 0.10,
    this.weave = 0,
    this.flicker = 0,
    this.dust = 0,
    this.gate = 0,
    this.defects = 0,
    this.negative = true,
    this.grainHighlights = 0,
    this.process = const FilmProcess(),
  });

  final String id;

  // --- colour -------------------------------------------------------------
  final bool mono;

  /// Panchromatic sensitivity for black & white stocks (linear weights).
  final List<double> monoWeights;

  /// Linear-light crosstalk between the emulsion layers (row-major 3x3).
  final List<double> matrix;

  /// Per-channel gain before the curve (white balance of the stock).
  final List<double> balance;
  final double exposureEv;

  /// Per-channel curve contrast (R, G, B). Different values per channel
  /// produce the colour crossover of real negatives (e.g. cool shadows and
  /// warm highlights when blue is softer than red).
  final List<double> contrast;

  /// Shoulder asymptote of the characteristic curve (linear output).
  final double white;

  /// Global OKLCh chroma scale.
  final double saturation;
  final List<HueTweak> hues;

  /// Scanned-negative black lift and highlight ceiling (sRGB units).
  final double shadowLift;
  final double highlightCap;

  /// Split toning added in sRGB, weighted toward shadows / highlights.
  final List<double> shadowTint;
  final List<double> highlightTint;

  // --- texture --------------------------------------------------------------
  /// Grain standard deviation in sRGB units at "Normal" strength.
  final double grainAmount;

  /// 0 = monochrome grain, 1 = independent per-channel grain.
  final double grainChroma;

  /// Grain texels across the frame height. Lower = coarser grain. Relative
  /// to the frame, so preview and a 12MP export look alike.
  final double grainResolution;

  /// Extra grain toward the highlights (0 = colour-negative behaviour,
  /// strongest in the mid-tones). B&W negative scans grain up most in bright
  /// skies and skin: the dense parts of the negative.
  final double grainHighlights;

  /// Red-orange glow around bright highlights (0..1).
  final double halation;
  final List<double> halationColor;
  final double vignette;
  final double flashStrength;

  /// Random per-frame exposure variation (EV), like a real roll.
  final double exposureDrift;

  // --- cine (Super 8) ---------------------------------------------------------
  final double weave;
  final double flicker;
  final double dust;

  /// Rounded, soft-edged projector gate (0 = none).
  final double gate;

  /// How often developed frames pick up dust, a hair, a scratch or a light
  /// leak (0 = never, 1 = a well-handled consumer roll). See FilmDefects.
  final double defects;

  /// Negative film (dust scans white); false for positive / instant.
  final bool negative;

  /// Camera, developer and scanner behaviour of the developed still.
  final FilmProcess process;

  bool get isCine => weave > 0 || flicker > 0 || gate > 0;

  static FilmProfile? forStock(String id) => _profiles[id];

  static const _profiles = <String, FilmProfile>{
    // Tuned against the owner's Ektar 100 scans: clean and sharp, punchy but
    // natural colour, bright azure skies leaning cyan (not navy), warm true
    // reds and golden yellows, deep greens, deep slightly warm blacks with
    // no lift, neutral clean highlights, very fine luminance grain.
    'ektar100': FilmProfile(
      id: 'ektar100',
      balance: [1.01, 1.0, 0.985],
      contrast: [1.30, 1.28, 1.33],
      white: 1.04,
      saturation: 1.2,
      hues: [
        HueTweak(27, 24, shift: 4, chroma: 1.12),
        HueTweak(55, 24, shift: 1, chroma: 1.05),
        HueTweak(100, 30, shift: -5, chroma: 1.08),
        HueTweak(142, 36, shift: 3, chroma: 1.10, light: -0.02),
        HueTweak(232, 34, shift: -5, chroma: 0.92, light: 0.045),
        HueTweak(264, 26, shift: -10, chroma: 0.92, light: 0.03),
      ],
      shadowTint: [0.006, 0.002, -0.012],
      highlightTint: [0.004, -0.002, 0.0],
      grainAmount: 0.018,
      grainChroma: 0.2,
      grainResolution: 2400,
      halation: 0.08,
      vignette: 0.14,
      defects: 0.6,
      // Little latitude below box speed: shadows block up and go cold.
      process: FilmProcess(
        meter: 0.5,
        scanFix: 0.7,
        crystal: 0.4,
        grainGain: 1.0,
        shadowCoarse: 1.3,
        layerScale: [1.1, 1.0, 1.35],
        underGrain: 0.3,
        overGrain: 0.08,
        underFog: 0.02,
        underTint: [-0.006, -0.004, 0.016],
        overSaturation: -0.03,
      ),
    ),
    // Tuned against the owner's Portra 400 scans: the stock that should read as
    // film. Soft contrast, green-teal shadows (red drops out first), warm
    // creamy highlights that never quite reach white, peachy skin, gentle
    // greens, clearly visible grain with a little colour in it.
    'portra400': FilmProfile(
      id: 'portra400',
      exposureEv: 0.15,
      balance: [1.02, 1.0, 0.97],
      contrast: [1.12, 1.05, 1.0],
      white: 1.0,
      saturation: 0.95,
      hues: [
        HueTweak(27, 24, shift: 5, chroma: 0.95),
        HueTweak(50, 30, shift: -2, chroma: 1.08, light: 0.015),
        HueTweak(140, 44, shift: -10, chroma: 0.85, light: -0.01),
        HueTweak(240, 40, shift: -3, chroma: 0.95),
      ],
      shadowLift: 0.015,
      highlightCap: 0.965,
      shadowTint: [-0.032, 0.015, -0.004],
      highlightTint: [0.012, 0.0, -0.022],
      grainAmount: 0.05,
      grainChroma: 0.4,
      grainResolution: 1500,
      halation: 0.20,
      vignette: 0.18,
      defects: 1.0,
      // Famous latitude: overexposed it goes creamy, pastel and finer;
      // underexposed the shadows go muddy green-teal and the grain climbs.
      // Metered a little over (rated nearer 200, as Portra shooters do).
      process: FilmProcess(
        meter: 0.4,
        meterKey: 0.12,
        grainGain: 1.48,
        scanFix: 0.82,
        crystal: 0.6,
        shadowCoarse: 1.5,
        layerScale: [1.1, 1.0, 1.5],
        underGrain: 0.4,
        overGrain: 0.18,
        underFog: 0.03,
        underTint: [-0.008, 0.006, 0.002],
        overSaturation: -0.06,
        overWarmth: 0.012,
        halationSpread: 0.5,
        formation: GrainFormation(),
      ),
    ),
    // Tuned against the owner's HP5 scans: strictly neutral, deep blacks, strong
    // contrast, bright highlights, and heavy grain that is strongest in the
    // highlights (skies, skin) and cleaner in the shadows; a grey glow round
    // bright lamps.
    'hp5plus400': FilmProfile(
      id: 'hp5plus400',
      mono: true,
      monoWeights: [0.24, 0.56, 0.20],
      contrast: [1.34, 1.34, 1.34],
      white: 1.03,
      shadowLift: 0.008,
      highlightCap: 1.0,
      grainAmount: 0.026,
      grainChroma: 0,
      grainResolution: 1600,
      grainHighlights: 3.0,
      halation: 0.12,
      halationColor: [1.0, 1.0, 1.0],
      vignette: 0.20,
      defects: 1.0,
      // Silver grain, coarse in thin shadows; home-developed, so rolls vary.
      process: FilmProcess(
        meter: 0.55,
        scanFix: 0.8,
        crystal: 0.7,
        grainGain: 1.3,
        shadowCoarse: 1.8,
        layerScale: [1.0, 1.0, 1.0],
        underGrain: 0.45,
        overGrain: 0.1,
        underFog: 0.04,
        underTint: [0.0, 0.0, 0.0],
        overSaturation: 0,
        chemistry: 1.2,
      ),
    ),
    // Instant integral film, tuned against the owner's Polaroid 600 scans:
    // washed-out cream highlights that never reach white, navy-teal shadows,
    // very compressed (muted) colour with greens leaning teal, soft
    // contrast, a heavy vignette and almost no visible grain (the dyes are
    // smooth). Chemistry flaws are frequent (FilmDefects, instant mode).
    'polaroid600': FilmProfile(
      id: 'polaroid600',
      exposureEv: 0.25,
      balance: [1.02, 1.0, 0.96],
      contrast: [0.96, 0.92, 0.88],
      white: 0.96,
      saturation: 0.7,
      hues: [
        HueTweak(27, 26, shift: 4, chroma: 0.98),
        HueTweak(55, 30, shift: 4, chroma: 1.02, light: 0.015),
        HueTweak(110, 28, shift: -6, chroma: 0.9),
        HueTweak(142, 40, shift: 28, chroma: 0.8, light: -0.01),
        HueTweak(235, 40, shift: -8, chroma: 0.85),
      ],
      shadowLift: 0.035,
      highlightCap: 0.895,
      shadowTint: [-0.035, 0.002, 0.05],
      highlightTint: [0.012, 0.004, -0.05],
      grainAmount: 0.022,
      grainChroma: 0.25,
      grainResolution: 1500,
      halation: 0.06,
      vignette: 0.42,
      flashStrength: 0.9,
      exposureDrift: 0.16,
      defects: 1.0,
      negative: false,
      // No scanner to save it: a crude meter, exposure errors print as they
      // are (dark and murky, or washed out), and temperature swings the
      // chemistry from pack to pack.
      process: FilmProcess(
        meter: 0.7,
        scanFix: 0.0,
        crystal: 0.2,
        shadowCoarse: 1.1,
        layerScale: [1.0, 1.0, 1.2],
        underGrain: 0.1,
        overGrain: 0.0,
        underFog: 0.0,
        underTint: [-0.01, 0.0, 0.012],
        overSaturation: -0.15,
        overWarmth: 0.02,
        chemistry: 1.5,
      ),
    ),
    // --- Pro stocks (1.9): first passes, to tune on the phone ------------
    // Golden 200: the warm consumer film from every drugstore shelf. Golden
    // cast, yellows and skin pushed, saturated reds, slightly cool lifted
    // shadows, medium grain.
    'gold200': FilmProfile(
      id: 'gold200',
      exposureEv: 0.1,
      balance: [1.03, 1.0, 0.95],
      contrast: [1.18, 1.14, 1.08],
      white: 1.02,
      saturation: 1.12,
      hues: [
        HueTweak(27, 24, shift: 3, chroma: 1.1),
        HueTweak(60, 30, shift: 4, chroma: 1.12, light: 0.02),
        HueTweak(100, 30, shift: -6, chroma: 1.15, light: 0.02),
        HueTweak(142, 40, shift: -6, chroma: 0.95),
        HueTweak(235, 40, shift: -4, chroma: 0.9),
      ],
      shadowLift: 0.02,
      highlightCap: 0.98,
      shadowTint: [-0.01, 0.0, 0.012],
      highlightTint: [0.016, 0.006, -0.022],
      grainAmount: 0.034,
      grainChroma: 0.4,
      grainResolution: 1700,
      halation: 0.12,
      vignette: 0.2,
      defects: 1.0,
      process: FilmProcess(
        meter: 0.5,
        crystal: 0.5,
        shadowCoarse: 1.7,
        layerScale: [1.2, 1.0, 1.6],
        underGrain: 0.4,
        underFog: 0.035,
        underTint: [-0.004, 0.008, -0.006],
        overSaturation: -0.05,
        overWarmth: 0.015,
      ),
    ),
    // Night 800T: cinema stock balanced for tungsten light, with the
    // anti-halation layer removed: cool daylight, warm lamps, glowing red
    // halos round every light, teal shadows, visible grain.
    'cinestill800t': FilmProfile(
      id: 'cinestill800t',
      exposureEv: 0.2,
      balance: [0.9, 0.98, 1.1],
      contrast: [1.1, 1.08, 1.04],
      white: 1.0,
      saturation: 1.0,
      hues: [
        HueTweak(27, 24, shift: 4, chroma: 1.15),
        HueTweak(55, 28, shift: -4, chroma: 1.05),
        HueTweak(195, 40, shift: 6, chroma: 1.1),
        HueTweak(235, 40, shift: -8, chroma: 1.05),
      ],
      shadowLift: 0.03,
      highlightCap: 0.97,
      shadowTint: [-0.03, 0.01, 0.025],
      highlightTint: [0.015, 0.0, -0.01],
      grainAmount: 0.045,
      grainChroma: 0.45,
      grainResolution: 1400,
      halation: 0.7,
      halationColor: [1.0, 0.18, 0.08],
      vignette: 0.18,
      defects: 1.0,
      // No anti-halation backing: a wide red skirt and a glow on every lamp.
      process: FilmProcess(
        meter: 0.5,
        crystal: 0.6,
        shadowCoarse: 1.6,
        layerScale: [1.2, 1.0, 1.5],
        underGrain: 0.4,
        underFog: 0.03,
        underTint: [-0.016, 0.006, 0.014],
        halationSpread: 0.65,
        bloom: 0.06,
      ),
    ),
    // Chrome 50: saturated slide film, the landscape photographer's
    // favourite. Deep blacks, vivid greens and blues, warm tight
    // highlights, almost no grain. Slides are positives (no lift, dark dust).
    'velvia50': FilmProfile(
      id: 'velvia50',
      exposureEv: -0.15,
      balance: [1.0, 1.0, 1.02],
      contrast: [1.45, 1.45, 1.42],
      white: 1.02,
      saturation: 1.35,
      hues: [
        HueTweak(27, 24, shift: 2, chroma: 1.15),
        HueTweak(55, 26, shift: 2, chroma: 1.05),
        HueTweak(142, 40, shift: 4, chroma: 1.25, light: -0.03),
        HueTweak(235, 34, shift: 2, chroma: 1.2, light: -0.03),
        HueTweak(300, 40, shift: 0, chroma: 1.2),
      ],
      shadowTint: [0.0, -0.004, 0.01],
      highlightTint: [0.006, 0.0, -0.012],
      grainAmount: 0.012,
      grainChroma: 0.15,
      grainResolution: 2800,
      halation: 0.05,
      vignette: 0.22,
      defects: 0.6,
      negative: false,
      // Slide film: what you shoot is what you get (no scan rescue), dense
      // black when under, washed out when over; E-6 labs are tightly run.
      process: FilmProcess(
        meter: 0.5,
        scanFix: 0.15,
        crystal: 0.3,
        shadowCoarse: 1.2,
        layerScale: [1.05, 1.0, 1.3],
        underGrain: 0.1,
        overGrain: 0.0,
        underFog: 0.0,
        underTint: [0.0, -0.004, 0.01],
        overSaturation: -0.12,
        chemistry: 0.6,
      ),
    ),
    // Single-Use 27: the cardboard camera from every wedding table and
    // holiday. A 400 consumer film with a green cast, punchy but cheap
    // colour, a soft plastic lens with heavy vignetting, harsh flash.
    'superia400': FilmProfile(
      id: 'superia400',
      exposureEv: 0.1,
      balance: [0.98, 1.03, 0.97],
      contrast: [1.2, 1.24, 1.16],
      white: 1.02,
      saturation: 1.08,
      hues: [
        HueTweak(27, 24, shift: -2, chroma: 1.05),
        HueTweak(142, 44, shift: 6, chroma: 1.12),
        HueTweak(195, 40, shift: -6, chroma: 1.05),
      ],
      shadowLift: 0.025,
      highlightCap: 0.97,
      shadowTint: [-0.015, 0.018, 0.0],
      highlightTint: [0.008, 0.006, -0.012],
      grainAmount: 0.04,
      grainChroma: 0.45,
      grainResolution: 1300,
      halation: 0.15,
      vignette: 0.45,
      flashStrength: 1.0,
      exposureDrift: 0.18,
      defects: 1.0,
      // Fixed shutter and aperture: it exposes by the scene, not the phone.
      // The minilab rescues most of it, with green mud in the shadows.
      process: FilmProcess(
        meter: 0.9,
        scanFix: 0.85,
        crystal: 0.55,
        shadowCoarse: 1.8,
        layerScale: [1.2, 1.0, 1.6],
        underGrain: 0.5,
        underFog: 0.05,
        underTint: [-0.012, 0.016, -0.002],
        overSaturation: -0.05,
        chemistry: 1.3,
        bloom: 0.08,
      ),
    ),
    // Epic 70: big-screen 65/70 mm motion picture film. Clean, wide, rich
    // and filmic: soft roll-off, gentle teal-orange split, very fine grain,
    // no gate or weave (a modern projector print).
    'vision70': FilmProfile(
      id: 'vision70',
      balance: [1.02, 1.0, 0.98],
      contrast: [1.16, 1.12, 1.1],
      white: 1.0,
      saturation: 1.05,
      hues: [
        HueTweak(55, 30, shift: 2, chroma: 1.06, light: 0.01),
        HueTweak(142, 40, shift: -8, chroma: 0.9),
        HueTweak(210, 44, shift: -6, chroma: 1.05),
      ],
      shadowLift: 0.01,
      highlightCap: 0.98,
      shadowTint: [-0.02, 0.008, 0.02],
      highlightTint: [0.016, 0.006, -0.016],
      grainAmount: 0.012,
      grainChroma: 0.3,
      grainResolution: 2400,
      halation: 0.12,
      vignette: 0.12,
      exposureDrift: 0,
    ),
    // Tuned against the owner's Super 8 scans: faded home-movie colour, lifted
    // blacks, soft highlights that rarely reach white, very muted colour
    // with olive mids and slightly green highlights, heavy grain, a warm
    // glow, clearly visible flicker and weave; shown as a full-gate scan
    // (CineStrip) with the sprocket hole on the left.
    'super8': FilmProfile(
      id: 'super8',
      balance: [1.0, 1.0, 0.93],
      contrast: [1.02, 1.0, 0.96],
      white: 0.96,
      saturation: 0.78,
      hues: [
        HueTweak(27, 26, chroma: 1.02),
        HueTweak(55, 28, shift: -2, chroma: 0.98),
        HueTweak(142, 40, shift: -14, chroma: 0.8),
        HueTweak(235, 40, shift: -6, chroma: 0.85),
      ],
      shadowLift: 0.1,
      highlightCap: 0.85,
      shadowTint: [0.012, 0.006, -0.006],
      highlightTint: [-0.012, 0.012, -0.006],
      // Normal = what Weak was until 1.4.7 (0.064 / 380: still too grainy;
      // 0.085 until 1.3.26); Weak and Strong scale from here.
      grainAmount: 0.0256,
      grainChroma: 0.45,
      grainResolution: 513,
      halation: 0.3,
      vignette: 0.3,
      exposureDrift: 0,
      weave: 1,
      flicker: 1,
      dust: 1,
      gate: 1,
    ),
  };
}

/// Grain strength chosen per film stock in settings: how strong the grain
/// is ([factor]) and how fine ([resolution] scales the stock's grain
/// resolution: weak is finer, strong is coarser, like a faster film).
enum GrainStrength {
  weak(0.4, 1.35),
  normal(1.0, 1.0),
  strong(2.4, 0.55);

  const GrainStrength(this.factor, this.resolution);
  final double factor;
  final double resolution;

  static GrainStrength fromName(String? n) =>
      GrainStrength.values.firstWhere((g) => g.name == n, orElse: () => GrainStrength.normal);
}

/// Evaluates a [FilmProfile] for one colour.
///
/// Input is *display-linear* RGB (the phone JPEG decoded to linear light,
/// possibly pushed above 1.0 by exposure / flash). Output is sRGB in [0, 1].
///
///   1. B&W: panchromatic mix to one channel
///   2. crosstalk matrix, stock white balance, exposure
///   3. inverse display transform: re-open the phone's compressed highlights
///      so the film shoulder (not the phone's clip) decides how they roll off
///   4. per-channel characteristic curve  y = W x^g / (x^g + m^g), with m
///      chosen so mid-grey stays mid-grey
///   5. hue-selective tweaks + saturation in OKLCh, gamut-mapped back
///   6. sRGB encode, split toning, scanner black lift / highlight cap
class FilmModel {
  FilmModel(this.p, {this.dev = const Development()}) {
    for (var c = 0; c < 3; c++) {
      final g = p.contrast[c] * dev.contrast;
      // y(x0) = 0.18 with x0 = inverseDisplay(0.18)
      final x0 = _inverseDisplay(0.18);
      _mg[c] = math.pow(x0, g) * (p.white / 0.18 - 1);
    }
    _ev = math.pow(2, p.exposureEv).toDouble();
  }

  final FilmProfile p;

  /// The roll's development (stills only; the viewfinder uses none).
  final Development dev;
  final List<double> _mg = List<double>.filled(3, 0);
  late final double _ev;
  final List<double> _lab = List<double>.filled(3, 0);
  final List<double> _rgb = List<double>.filled(3, 0);

  static double _inverseDisplay(double y) => y * (1 + 3.0 * y * y * y);

  /// Writes sRGB output into [out].
  void evaluate(double r, double g, double b, List<double> out) {
    if (p.mono) {
      final y = p.monoWeights[0] * r + p.monoWeights[1] * g + p.monoWeights[2] * b;
      r = g = b = y;
    }
    final m = p.matrix;
    final t = dev.tint;
    var cr = (m[0] * r + m[1] * g + m[2] * b) * p.balance[0] * t[0] * _ev;
    var cg = (m[3] * r + m[4] * g + m[5] * b) * p.balance[1] * t[1] * _ev;
    var cb = (m[6] * r + m[7] * g + m[8] * b) * p.balance[2] * t[2] * _ev;
    cr = _curve(_inverseDisplay(math.max(0, cr)), 0);
    cg = _curve(_inverseDisplay(math.max(0, cg)), 1);
    cb = _curve(_inverseDisplay(math.max(0, cb)), 2);

    if (!p.mono && (p.hues.isNotEmpty || p.saturation != 1)) {
      ColorMath.linearToOklab(cr, cg, cb, _lab);
      final l0 = _lab[0];
      var c = math.sqrt(_lab[1] * _lab[1] + _lab[2] * _lab[2]);
      var h = math.atan2(_lab[2], _lab[1]) * 180 / math.pi;
      var lightness = l0;
      final neutral = ColorMath.smoothstep(0.012, 0.07, c);
      for (final t in p.hues) {
        final d = ColorMath.hueDelta(h, t.hue);
        final w = math.exp(-0.5 * (d / t.width) * (d / t.width)) * neutral;
        if (w < 1e-4) continue;
        h += t.shift * w;
        c *= 1 + (t.chroma - 1) * w;
        lightness += t.light * w * ColorMath.smoothstep(0.05, 0.35, l0);
      }
      c *= p.saturation;
      final hr = h * math.pi / 180;
      final ca = math.cos(hr), sa = math.sin(hr);
      // Gamut map: shrink chroma until every channel is >= 0.
      var lo = 0.0, hi = c;
      ColorMath.oklabToLinear(lightness, c * ca, c * sa, _rgb);
      if (_rgb[0] < 0 || _rgb[1] < 0 || _rgb[2] < 0) {
        for (var k = 0; k < 10; k++) {
          final mid = (lo + hi) / 2;
          ColorMath.oklabToLinear(lightness, mid * ca, mid * sa, _rgb);
          if (_rgb[0] < 0 || _rgb[1] < 0 || _rgb[2] < 0) {
            hi = mid;
          } else {
            lo = mid;
          }
        }
        ColorMath.oklabToLinear(lightness, lo * ca, lo * sa, _rgb);
      }
      cr = _rgb[0];
      cg = _rgb[1];
      cb = _rgb[2];
    }

    final lift = p.shadowLift, cap = p.highlightCap;
    for (var k = 0; k < 3; k++) {
      final lin = k == 0 ? cr : (k == 1 ? cg : cb);
      var s = ColorMath.linearToSrgb(lin.clamp(0.0, 1.0));
      final sh = (1 - s) * (1 - s), hl = s * s;
      s += p.shadowTint[k] * sh + p.highlightTint[k] * hl;
      s = lift + (cap - lift) * s;
      out[k] = s.clamp(0.0, 1.0);
    }
  }

  double _curve(double x, int c) {
    final g = p.contrast[c] * dev.contrast;
    final xg = math.pow(x, g);
    return p.white * xg / (xg + _mg[c]);
  }
}
