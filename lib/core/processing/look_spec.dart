import 'dart:math' as math;

/// Which fragment shader (and which CPU/FFmpeg renderer branch) a look uses.
enum ShaderKind {
  /// Film stocks: LUT + grain + halation (see film/film_profile.dart).
  film('shaders/film.frag'),
  ccd('shaders/ccd_color.frag'),
  jpegPixel('shaders/jpeg_pixel.frag'),
  vhs('shaders/vhs_scanline.frag');

  const ShaderKind(this.asset);
  final String asset;
}

/// A *digital* camera look (film stocks use FilmProfile instead), evaluated
/// by three renderers:
///
///  * the live GLSL preview shader (GPU, every frame),
///  * the full-resolution CPU renderer in a background isolate (stills),
///  * an FFmpeg filtergraph (video).
///
/// All three implement the same per-pixel maths in the same order:
///
///   rgb  = M * rgb + offset                (M = saturation x colour matrix)
///   rgb *= exposure * vignette(r) * flash(r)
///   rgb  = clamp(rgb, 0, 1)                (hard clip => CCD blown highlights)
///   rgb  = pow(rgb, gamma)
///   rgb  = black + (white - black) * sCurve(rgb, contrast, pivot)
///   rgb += grain * amount * midtoneWeight(luma)
///
/// so what you see in the viewfinder is what ends up in the file.
class LookSpec {
  const LookSpec({
    required this.kind,
    required this.matrix,
    this.offset = const [0, 0, 0],
    this.saturation = 1,
    this.mono = false,
    this.monoWeights = const [0.2126, 0.7152, 0.0722],
    this.exposure = 1,
    this.gamma = 1,
    this.contrast = 1,
    this.pivot = 0.5,
    this.black = 0,
    this.white = 1,
    this.vignette = 0,
    this.grainAmount = 0,
    this.grainSize = 1,
    this.grainChroma = 0,
    this.flashStrength = 0.7,
    this.sharpen = 0,
    this.chromaNoise = 0,
    this.bloom = 0,
    this.smear = 0,
    this.lowRes = 240,
    this.posterize = 64,
    this.artifact = 0,
    this.scanline = 0,
    this.bleed = 0,
    this.jitter = 0,
    this.tracking = 0,
    this.lines = 240,
  });

  final ShaderKind kind;

  /// Row-major 3x3 colour matrix applied before saturation.
  final List<double> matrix;
  final List<double> offset;
  final double saturation;
  final bool mono;
  final List<double> monoWeights;

  final double exposure;
  final double gamma;
  final double contrast;
  final double pivot;
  final double black;
  final double white;
  final double vignette;

  final double grainAmount;

  /// Grain cell size in pixels at a reference width of 1080px. Renderers scale
  /// it with the actual frame width so grain looks the same on screen and in
  /// a 12MP export.
  final double grainSize;
  final double grainChroma;

  /// How hard the simulated point-and-shoot flash hits (0..1).
  final double flashStrength;

  // CCD
  final double sharpen;
  final double chromaNoise;
  final double bloom;

  /// Vertical CCD smear: bright lights bleed a streak up and down the column.
  final double smear;

  // JPEG / flip phone
  /// Number of (fat) pixels across the frame width, e.g. 240 for a VGA-era
  /// phone sensor shown at 1/3 resolution.
  final double lowRes;
  final double posterize;
  final double artifact;

  // VHS
  final double scanline;
  final double bleed;
  final double jitter;
  final double tracking;
  final double lines;

  static const double referenceWidth = 1080;

  /// Saturation (or mono conversion) folded into the colour matrix: both are
  /// linear, so S * M is applied as a single 3x3 multiply everywhere.
  List<double> combinedMatrix() {
    final w = monoWeights;
    final s = mono ? 0.0 : saturation;
    // S = s*I + (1-s) * [w; w; w]
    final sm = List<double>.generate(9, (i) {
      final r = i ~/ 3, c = i % 3;
      return (r == c ? s : 0.0) + (1 - s) * w[c];
    });
    final out = List<double>.filled(9, 0);
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        var v = 0.0;
        for (var k = 0; k < 3; k++) {
          v += sm[r * 3 + k] * matrix[k * 3 + c];
        }
        out[r * 3 + c] = v;
      }
    }
    return out;
  }

  /// Offset transformed by the saturation matrix (offset is added after M).
  List<double> combinedOffset() {
    final w = monoWeights;
    final s = mono ? 0.0 : saturation;
    final l = w[0] * offset[0] + w[1] * offset[1] + w[2] * offset[2];
    return [for (var i = 0; i < 3; i++) s * offset[i] + (1 - s) * l];
  }

  /// The shared tone curve. Input must already be clamped to [0, 1].
  double tone(double x) {
    final g = math.pow(x, gamma).toDouble();
    final p = pivot;
    final k = contrast;
    final s = g < p ? p * math.pow(g / p, k) : 1 - (1 - p) * math.pow((1 - g) / (1 - p), k);
    return black + (white - black) * s;
  }

  /// Exposure falloff for vignette + flash at a normalised radius
  /// (0 = centre, 1 = corner).
  double spatialExposure(double r, double flash) {
    final v = 1 - vignette * _smoothstep(0.35, 1.0, r);
    final hot = 1 - _smoothstep(0.0, 0.85, r);
    final f = 1 + flash * flashStrength * (0.9 * hot - 0.45 * (1 - hot));
    return exposure * v * f;
  }

  /// Cool-white cast of a xenon flash tube.
  List<double> flashTint(double flash) => [
    1 - 0.03 * flash * flashStrength,
    1.0,
    1 + 0.06 * flash * flashStrength,
  ];

  /// Grain strength weighting: film grain is most visible in the mid-tones.
  static double midtoneWeight(double luma) => 0.35 + 2.6 * luma * (1 - luma);

  static double _smoothstep(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// Floats for the uniforms shared by every look shader, in declaration
  /// order *after* `uniform vec2 uSize` (float indices 2..28).
  ///
  /// [crop] is the unmasked viewport rect (normalised x, y, w, h) so that
  /// vignette, flash fall-off and grain scale are computed relative to the
  /// exported frame rather than the whole sensor preview.
  List<double> commonUniforms({
    required double time,
    double flash = 0,
    List<double> crop = const [0, 0, 1, 1],
  }) {
    final m = combinedMatrix();
    final o = combinedOffset();
    return [
      time,
      m[0], m[1], m[2], //
      m[3], m[4], m[5], //
      m[6], m[7], m[8], //
      o[0], o[1], o[2],
      exposure, gamma, contrast, pivot, black, white, vignette,
      grainAmount, grainSize, flash * flashStrength,
      crop[0], crop[1], crop[2], crop[3],
    ];
  }

  /// Index of the first shader-specific uniform.
  static const int extraUniformStart = 29;

  /// Shader-specific uniforms that follow the common block (index 29+).
  List<double> extraUniforms() => switch (kind) {
    ShaderKind.film => const [],
    ShaderKind.ccd => [sharpen, chromaNoise, bloom, smear],
    ShaderKind.jpegPixel => [lowRes, posterize, artifact],
    ShaderKind.vhs => [scanline, bleed, jitter, tracking, lines],
  };
}
