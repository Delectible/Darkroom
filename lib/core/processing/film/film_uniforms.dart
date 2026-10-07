import '../crop_math.dart';
import 'film_lut.dart';
import 'film_profile.dart';

/// Float uniforms of shaders/film.frag after `uSize` (indices 2..30), in
/// declaration order. Pure Dart so tests can check it against the .frag.
class FilmUniformLayout {
  const FilmUniformLayout._();

  static const int floatCount = 31; // including uSize

  static List<double> floats(
    FilmProfile p, {
    required double time,
    required UnitRect crop,
    required GrainStrength grain,
    required double fps,
    double flash = 0,
    UnitRect? canvas,
    int turns = 0,
    double spin = 0,
    double spinScale = 1,
  }) => [
    time,
    crop.left, crop.top, crop.width, crop.height,
    1.0, // exposure (the stock's own EV is baked into the LUT)
    p.vignette,
    flash * p.flashStrength,
    FilmLut.defaultSize.toDouble(),
    p.grainAmount * grain.factor,
    p.grainChroma,
    p.grainResolution * grain.resolution,
    p.halation,
    p.halationColor[0], p.halationColor[1], p.halationColor[2],
    p.weave,
    p.flicker,
    p.dust,
    p.gate,
    fps,
    p.grainHighlights,
    // Super 8 strip: canvas in the box, and the viewer's quarter turns.
    (canvas ?? crop).left, (canvas ?? crop).top, (canvas ?? crop).width, (canvas ?? crop).height,
    turns.toDouble(),
    // Super 8: the strip swinging round when the phone turns (radians,
    // clockwise on screen, about the box centre; and its scale).
    spin, spinScale,
  ];
}
