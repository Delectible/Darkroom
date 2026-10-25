import 'dart:math' as math;

import 'grain_formation.dart';

/// How a stock behaves in the camera, the developer and the scanner: the
/// part of the look that isn't a fixed colour curve. Used by the still
/// renderer while a print develops (the live viewfinder shows the curve and
/// an approximation of the grain).
///
///   * Metering: the camera exposes the frame by its own centre-weighted
///     reading, not the phone's, so backlit and dark scenes land over or
///     under like a real roll.
///   * Exposure: an under- or overexposed negative sits lower or higher on
///     the film's curve. The lab scan pulls most of it back to normal
///     brightness ([scanFix]), so what's left is the character: thin,
///     foggy, grainy shadows when under; dense, pastel, fine-grained when
///     over.
///   * Grain: each crystal has its own sensitivity (noise in log exposure,
///     before the curve, so the curve itself shapes it), the biggest,
///     fastest crystals develop first (coarser grain in the shadows), and
///     each dye layer has its own cloud size (blue coarsest).
///   * Development: every roll goes through the chemistry once, so a whole
///     roll shares a small shift in contrast, density and colour.
///   * Halation: a tight core plus a wide skirt of light scattered back
///     from the film base, and an optional neutral bloom.
class FilmProcess {
  const FilmProcess({
    this.meter = 0.35,
    this.meterKey = 0.16,
    this.scanFix = 0.75,
    this.crystal = 0.55,
    this.grainGain = 1.4,
    this.shadowCoarse = 1.6,
    this.layerScale = const [1.15, 1.0, 1.45],
    this.underGrain = 0.25,
    this.overGrain = 0.12,
    this.underFog = 0.035,
    this.underTint = const [-0.012, 0.01, 0.002],
    this.overSaturation = -0.07,
    this.overWarmth = 0.0,
    this.chemistry = 1.0,
    this.halationSpread = 0.45,
    this.bloom = 0,
    this.formation,
  });

  /// How much the camera's own meter reading moves exposure (0 = trust
  /// the phone's exposure completely).
  final double meter;

  /// Log-average linear luminance the meter calls "correct". Phone photos
  /// average a little under 18% grey in log terms.
  final double meterKey;

  /// Share of an exposure error the lab scan corrects (0..1).
  final double scanFix;

  /// Share of the grain that comes from crystal sensitivity (log exposure,
  /// before the curve); the rest is dye-cloud texture added after it.
  final double crystal;

  /// Stills grain relative to [FilmProfile.grainAmount] (the viewfinder's):
  /// coarse shadow grain and dye clouds carry less fine detail, so the
  /// still needs more to read the same (calibrated to the scans).
  final double grainGain;

  /// Grain size in deep shadows relative to the highlights.
  final double shadowCoarse;

  /// Dye-cloud size per layer (R, G, B), relative to the stock's grain.
  final List<double> layerScale;

  /// Extra grain per stop under / less grain per stop over.
  final double underGrain;
  final double overGrain;

  /// Milky base fog in the shadows per stop under (sRGB units), and the
  /// colour a thin negative's shadows scan to.
  final double underFog;
  final List<double> underTint;

  /// Saturation change per stop over (dense negatives go pastel), and a
  /// warm shift of overexposed highlights per stop.
  final double overSaturation;
  final double overWarmth;

  /// Per-roll development variation (0 = a perfectly controlled lab).
  final double chemistry;

  /// Share of halation in the wide skirt (the rest is the tight core).
  final double halationSpread;

  /// Neutral glow round the brightest highlights (0..1): diffusion in a
  /// soft or cheap lens.
  final double bloom;

  /// The image is built out of grains (stills): detail stops at the grain.
  /// Null = the grain texture over a sharp image.
  final GrainFormation? formation;

  /// Most stops the meter may move the frame either way.
  static const double maxMeterEv = 1.5;
}

/// One roll's trip through the chemistry: shared by every frame shot on
/// the same stock the same day.
class Development {
  const Development({this.contrast = 1, this.density = 0, this.tint = const [1, 1, 1]});

  /// Rolled from the roll's seed. [amount] = FilmProcess.chemistry.
  factory Development.roll(int rollSeed, double amount) {
    if (amount <= 0) return const Development();
    final r = math.Random(rollSeed ^ 0x5eed);
    double gauss() {
      // Sum of three uniforms: close enough to normal, bounded.
      return (r.nextDouble() + r.nextDouble() + r.nextDouble() - 1.5) * 2;
    }

    return Development(
      contrast: 1 + 0.045 * amount * gauss(),
      density: 0.12 * amount * gauss(),
      tint: [1 + 0.012 * amount * gauss(), 1.0, 1 + 0.014 * amount * gauss()],
    );
  }

  /// Contrast multiplier (push / pull, developer temperature and age).
  final double contrast;

  /// Density shift in stops.
  final double density;

  /// Colour balance of the lab's chemistry (R, G, B gains).
  final List<double> tint;

  /// Stable seed for one roll: the stock and the darkroom day (rolls
  /// change at 5am, like the free allowance).
  static int rollSeedFor(String cameraId, int capturedAtMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(capturedAtMs).subtract(const Duration(hours: 5));
    var h = d.year * 372 + d.month * 31 + d.day;
    for (final c in cameraId.codeUnits) {
      h = (h * 31 + c) & 0x3fffffff;
    }
    return h;
  }
}
