import 'dart:math' as math;

/// Output aspect ratios offered by the cameras. [long] / [short] is always
/// >= 1; the orientation of the crop follows the orientation of the frame it
/// is applied to (portrait UI => portrait crop, landscape photo => landscape).
enum AspectRatioOption {
  r4x3('4:3', 4, 3),
  r16x9('16:9', 16, 9),
  r1x1('1:1', 1, 1),
  r3x2('3:2', 3, 2);

  const AspectRatioOption(this.label, this.long, this.short);

  final String label;
  final int long;
  final int short;

  double get ratio => long / short;

  static AspectRatioOption fromName(String? name, AspectRatioOption fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}

/// Integer pixel rectangle.
class PixelRect {
  const PixelRect(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;

  @override
  String toString() => 'PixelRect($x, $y, ${width}x$height)';
}

/// Normalised rectangle (0..1) inside a frame.
class UnitRect {
  const UnitRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;
}

/// Maps the aspect-ratio mask shown over the live preview onto the pixels of
/// the captured still (or video), so that the exported frame contains exactly
/// what was visible inside the unmasked viewport.
///
/// Why this is not just "centre-crop the photo to the ratio":
/// the preview stream and the still-capture stream are usually configured with
/// *different* aspect ratios (e.g. a 16:9 preview over a 4:3 still). Camera2 /
/// CameraX and AVFoundation produce every stream as the largest centred crop of
/// the sensor's active array that matches that stream's aspect ratio. So a
/// 16:9 preview shows only the middle 75% of a 4:3 still's height. A naive
/// centred 1:1 crop of the still would include image content that was never
/// visible in the viewfinder.
///
/// The fix is to (1) locate the preview's field of view inside the still,
/// (2) place the mask rect inside that field of view exactly as the UI did.
/// Both steps are centred crops, so only aspect ratios are needed — no
/// device-specific sensor geometry.
class CropMath {
  const CropMath._();

  /// Size of the preview's field of view expressed in still-image pixels.
  ///
  /// [previewAspect] is the preview stream's long/short ratio (CameraValue's
  /// aspectRatio is already sensor-landscape, i.e. >= 1).
  /// Returned as (long, short) in still pixels.
  static (double, double) previewFovInStill({
    required int stillLong,
    required int stillShort,
    required double previewAspect,
  }) {
    final stillAspect = stillLong / stillShort;
    final ap = previewAspect >= 1 ? previewAspect : 1 / previewAspect;
    // Preview wider than still => preview spans the still's full long edge
    // and a reduced part of the short edge, and vice versa.
    final long = stillLong.toDouble() * math.min(1.0, ap / stillAspect);
    final short = stillShort.toDouble() * math.min(1.0, stillAspect / ap);
    return (long, short);
  }

  /// Largest centred rect with long/short == [ratio] that fits inside
  /// (fovLong x fovShort). Returns (long, short).
  static (double, double) fitRatio(double fovLong, double fovShort, double ratio) {
    if (fovLong / fovShort >= ratio) {
      return (fovShort * ratio, fovShort);
    }
    return (fovLong, fovLong / ratio);
  }

  /// Computes the crop rectangle in *oriented* still pixels (after EXIF
  /// rotation has been applied).
  ///
  /// The crop's long side is always aligned with the sensor's long axis
  /// because the UI is locked to portrait and the mask's long side is drawn
  /// along the preview's long (vertical) side.
  static PixelRect stillCrop({
    required int width,
    required int height,
    required double previewAspect,
    required AspectRatioOption ratio,
  }) {
    final landscape = width >= height;
    final stillLong = landscape ? width : height;
    final stillShort = landscape ? height : width;
    final (fovLong, fovShort) = previewFovInStill(
      stillLong: stillLong,
      stillShort: stillShort,
      previewAspect: previewAspect,
    );
    final (cropLong, cropShort) = fitRatio(fovLong, fovShort, ratio.ratio);
    // Round to even numbers: keeps chroma-subsampled encoders (JPEG 4:2:0,
    // H.264 yuv420p) happy and avoids a 1px drift between runs.
    int even(double v) => math.max(2, (v.floor() ~/ 2) * 2);
    final cw = even(landscape ? cropLong : cropShort);
    final ch = even(landscape ? cropShort : cropLong);
    final w = math.min(cw, width - width % 2);
    final h = math.min(ch, height - height % 2);
    return PixelRect((width - w) ~/ 2, (height - h) ~/ 2, w, h);
  }

  /// The unmasked area of the preview box, normalised to the box.
  ///
  /// The preview box is drawn portrait (width/height == 1/previewAspect), the
  /// mask is the largest centred rect of width/height == 1/ratio inside it.
  /// This is the *same* computation as [stillCrop] when the still has the
  /// preview's aspect ratio, which is what guarantees viewport/export parity.
  static UnitRect previewMask({required double previewAspect, required AspectRatioOption ratio}) {
    final ap = previewAspect >= 1 ? previewAspect : 1 / previewAspect;
    // Work in a box of width 1 and height ap (portrait).
    final (cropLong, cropShort) = fitRatio(ap, 1.0, ratio.ratio);
    final w = cropShort; // portrait: short side is horizontal
    final h = cropLong / ap;
    return UnitRect((1 - w) / 2, (1 - h) / 2, w, h);
  }

  /// Raw (pre-EXIF-rotation) rect for an oriented crop. The crop is centred,
  /// so rotation/flip only swaps the dimensions for EXIF orientations 5..8.
  static PixelRect toRawSpace({
    required PixelRect oriented,
    required int rawWidth,
    required int rawHeight,
    required int exifOrientation,
  }) {
    final swap = exifOrientation >= 5 && exifOrientation <= 8;
    final w = swap ? oriented.height : oriented.width;
    final h = swap ? oriented.width : oriented.height;
    return PixelRect((rawWidth - w) ~/ 2, (rawHeight - h) ~/ 2, w, h);
  }

  /// Scales (w, h) down so the long edge is <= [maxLong], keeping it even.
  static (int, int) fitLongEdge(int w, int h, int maxLong) {
    final long = math.max(w, h);
    if (long <= maxLong) return (w, h);
    final s = maxLong / long;
    int even(double v) => math.max(2, (v.round() ~/ 2) * 2);
    return (even(w * s), even(h * s));
  }
}
