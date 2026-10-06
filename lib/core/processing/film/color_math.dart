import 'dart:math' as math;

/// Colour-space helpers shared by the film model (pure Dart, isolate-safe).
class ColorMath {
  const ColorMath._();

  static double srgbToLinear(double c) {
    if (c <= 0.04045) return c / 12.92;
    return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static double linearToSrgb(double c) {
    if (c <= 0.0) return 0.0;
    if (c <= 0.0031308) return c * 12.92;
    return 1.055 * math.pow(c, 1 / 2.4) - 0.055;
  }

  /// Linear sRGB -> OKLab (Björn Ottosson). Writes into [out] (L, a, b).
  static void linearToOklab(double r, double g, double b, List<double> out) {
    final l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    final m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    final s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
    final l3 = _cbrt(l), m3 = _cbrt(m), s3 = _cbrt(s);
    out[0] = 0.2104542553 * l3 + 0.7936177850 * m3 - 0.0040720468 * s3;
    out[1] = 1.9779984951 * l3 - 2.4285922050 * m3 + 0.4505937099 * s3;
    out[2] = 0.0259040371 * l3 + 0.7827717662 * m3 - 0.8086757660 * s3;
  }

  /// OKLab -> linear sRGB. Writes into [out] (r, g, b), unclamped.
  static void oklabToLinear(double L, double a, double b, List<double> out) {
    final l3 = L + 0.3963377774 * a + 0.2158037573 * b;
    final m3 = L - 0.1055613458 * a - 0.0638541728 * b;
    final s3 = L - 0.0894841775 * a - 1.2914855480 * b;
    final l = l3 * l3 * l3, m = m3 * m3 * m3, s = s3 * s3 * s3;
    out[0] = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    out[1] = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    out[2] = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
  }

  static double _cbrt(double x) => x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

  static double smoothstep(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// Signed shortest difference between two hue angles in degrees.
  static double hueDelta(double a, double b) {
    var d = (a - b) % 360.0;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }
}
