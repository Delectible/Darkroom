import '../crop_math.dart';
import 'film_lut.dart';
import 'film_profile.dart';

/// Float uniforms of shaders/film.frag after `uSize` (indices 2..22), in
/// declaration order. Pure Dart so tests can check it against the .frag.
class FilmUniformLayout {
  const FilmUniformLayout._();

  static const int floatCount = 23; // including uSize

  static List<double> floats(
    FilmProfile p, {
    required double time,
    required UnitRect crop,
    required GrainStrength grain,
    required double fps,
    double flash = 0,
  }) => [
    time,
    crop.left, crop.top, crop.width, crop.height,
    1.0, // exposure (the stock's own EV is baked into the LUT)
    p.vignette,
    flash * p.flashStrength,
    FilmLut.defaultSize.toDouble(),
    p.grainAmount * grain.factor,
    p.grainChroma,
    p.grainResolution,
    p.halation,
    p.halationColor[0], p.halationColor[1], p.halationColor[2],
    p.weave,
    p.flicker,
    p.dust,
    p.gate,
    fps,
  ];
}
