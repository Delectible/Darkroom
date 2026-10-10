import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../features/cameras/domain/camera_catalog.dart';
import '../../features/cameras/domain/camera_spec.dart';
import '../utils/pixel_font.dart';
import 'crop_math.dart';
import 'film/film_profile.dart';
import 'film/film_renderer.dart';
import 'look_renderer.dart';
import 'look_spec.dart';

enum FlashSetting { auto, on, off }

/// Everything needed to turn one raw capture into a finished file.
///
/// Plain data + JSON so it can (a) cross an isolate boundary and (b) be
/// persisted next to the queue row, letting a cold start or the WorkManager
/// worker finish a job that was interrupted by the app being killed.
class PhotoJob {
  const PhotoJob({
    required this.id,
    required this.cameraId,
    required this.rawPath,
    required this.outputPath,
    required this.thumbPath,
    required this.aspect,
    required this.previewAspect,
    required this.flash,
    required this.timestamp,
    required this.capturedAtMs,
    this.rotationTurns = 0,
    this.originalCopyPath,
    this.grain = GrainStrength.normal,
  });

  final String id;
  final String cameraId;
  final String rawPath;
  final String outputPath;
  final String thumbPath;
  final AspectRatioOption aspect;

  /// Preview stream long/short ratio at capture time (CameraValue.aspectRatio).
  final double previewAspect;
  final FlashSetting flash;
  final bool timestamp;
  final int capturedAtMs;

  /// Clockwise quarter turns to apply to a portrait capture so that a photo
  /// taken with the phone held sideways comes out landscape. Capture
  /// orientation is locked to portrait (it keeps the preview stable in our
  /// portrait-only UI); this re-applies the physical orientation.
  final int rotationTurns;

  /// Where to write an un-graded (but cropped) copy, if the user enabled
  /// "Save original unfiltered copy".
  final String? originalCopyPath;

  /// Film stocks: grain strength chosen in settings.
  final GrainStrength grain;

  int get seed => id.hashCode & 0x7fffffff;

  Map<String, Object?> toJson() => {
    'id': id,
    'cameraId': cameraId,
    'rawPath': rawPath,
    'outputPath': outputPath,
    'thumbPath': thumbPath,
    'aspect': aspect.name,
    'previewAspect': previewAspect,
    'flash': flash.name,
    'timestamp': timestamp,
    'capturedAtMs': capturedAtMs,
    'rotationTurns': rotationTurns,
    'originalCopyPath': originalCopyPath,
    'grain': grain.name,
  };

  factory PhotoJob.fromJson(Map<String, Object?> j) => PhotoJob(
    id: j['id']! as String,
    cameraId: j['cameraId']! as String,
    rawPath: j['rawPath']! as String,
    outputPath: j['outputPath']! as String,
    thumbPath: j['thumbPath']! as String,
    aspect: AspectRatioOption.fromName(j['aspect'] as String?, AspectRatioOption.r4x3),
    previewAspect: (j['previewAspect']! as num).toDouble(),
    flash: FlashSetting.values.byName(j['flash']! as String),
    timestamp: j['timestamp']! as bool,
    capturedAtMs: j['capturedAtMs']! as int,
    rotationTurns: j['rotationTurns'] as int? ?? 0,
    originalCopyPath: j['originalCopyPath'] as String?,
    grain: GrainStrength.fromName(j['grain'] as String?),
  );
}

class PhotoResult {
  const PhotoResult({
    required this.width,
    required this.height,
    required this.bytes,
    required this.flashFired,
    this.originalCopyPath,
  });

  final int width;
  final int height;
  final int bytes;
  final bool flashFired;
  final String? originalCopyPath;
}

/// Full-resolution still renderer. Must be called off the UI isolate
/// (use `renderPhotoInIsolate(job)` from isolate_jobs.dart).
///
/// Memory strategy for 12MP+ captures:
///  * decode once, then *crop before anything else* so the working image is
///    only the exported area;
///  * downscale to the camera's output cap before grading;
///  * bake EXIF rotation on the already-small image (bakeOrientation on the
///    full frame would allocate a second full-size copy);
///  * grade in place on the RGB byte buffer (see LookRenderer).
/// Peak usage is ~2x the decoded frame for a moment (decode + crop), then
/// drops to the output size.
class PhotoPipeline {
  const PhotoPipeline._();

  static PhotoResult run(PhotoJob job) {
    final spec = CameraCatalog.byId(job.cameraId);
    final profile = spec.output;

    final raw = File(job.rawPath).readAsBytesSync();
    img.Image? decoded = img.decodeJpg(raw) ?? img.decodeImage(raw);
    if (decoded == null) {
      throw const FormatException('Capture could not be decoded');
    }
    final orientation = decoded.exif.imageIfd.orientation ?? 1;
    final swap = orientation >= 5 && orientation <= 8;
    final ow = swap ? decoded.height : decoded.width;
    final oh = swap ? decoded.width : decoded.height;

    final crop = CropMath.stillCrop(
      width: ow,
      height: oh,
      previewAspect: job.previewAspect,
      ratio: job.aspect,
    );
    final rawCrop = CropMath.toRawSpace(
      oriented: crop,
      rawWidth: decoded.width,
      rawHeight: decoded.height,
      exifOrientation: orientation,
    );
    var image = img.copyCrop(
      decoded,
      x: rawCrop.x,
      y: rawCrop.y,
      width: rawCrop.width,
      height: rawCrop.height,
    );
    decoded = null; // let the full frame be collected before we allocate more

    // Target size: low-res pipelines render small then upscale at the end.
    final targetLong = profile.lowResLongEdge ?? profile.maxLongEdge;
    final (tw, th) = CropMath.fitLongEdge(image.width, image.height, targetLong);
    if (tw != image.width || th != image.height) {
      image = img.copyResize(image, width: tw, height: th, interpolation: img.Interpolation.average);
    }
    image = _bakeOrientation(image, orientation);
    // Only re-orient if the platform honoured the portrait lock (a landscape
    // buffer means it already applied the device orientation itself).
    if (job.rotationTurns % 4 != 0 && oh > ow) {
      image = img.copyRotate(image, angle: (job.rotationTurns % 4) * 90);
    }
    image = _ensureRgb8(image);
    image.exif = img.ExifData();

    String? originalPath;
    if (job.originalCopyPath != null) {
      _writeAtomic(job.originalCopyPath!, img.encodeJpg(image, quality: 92));
      originalPath = job.originalCopyPath;
    }

    final w = image.width, h = image.height;
    var data = image.toUint8List();
    final flashFired = switch (job.flash) {
      FlashSetting.on => true,
      FlashSetting.off => false,
      FlashSetting.auto => LookRenderer.meanLuma(data, w, h) < 0.22,
    };
    final flash = flashFired ? 1.0 : 0.0;

    final film = spec.film;
    if (film != null) {
      FilmRenderer(film, seed: job.seed, grain: job.grain).render(data, w, h, flash: flash);
    } else {
      final look = spec.look!;
      final renderer = LookRenderer(look, seed: job.seed);
      switch (look.kind) {
        case ShaderKind.ccd:
          renderer.sharpen(data, w, h, radius: math.max(1, (w / LookSpec.referenceWidth).round()));
          renderer.grade(data, w, h, flash: flash);
        case ShaderKind.vhs:
          renderer.vhsSignal(data, w, h);
          renderer.grade(data, w, h, flash: flash);
        case ShaderKind.jpegPixel:
          // Negative sharpen = the soft plastic lens.
          renderer.sharpen(data, w, h);
          renderer.grade(data, w, h, flash: flash);
        case ShaderKind.film:
          renderer.grade(data, w, h, flash: flash);
      }
    }

    if (job.timestamp && spec.timestampStyle != TimestampStyle.none) {
      _drawTimestamp(data, w, h, spec.timestampStyle, DateTime.fromMillisecondsSinceEpoch(job.capturedAtMs));
    }

    // Real JPEG at a terrible quality => genuine 8x8 block artefacts.
    if (profile.lowResJpegQuality != null) {
      final lowJpeg = img.encodeJpg(
        image,
        quality: profile.lowResJpegQuality!,
        chroma: img.JpegChroma.yuv420,
      );
      image = _ensureRgb8(img.decodeJpg(lowJpeg)!);
      data = image.toUint8List();
    }

    if (profile.upscale > 1) {
      image = img.copyResize(
        image,
        width: image.width * profile.upscale,
        height: image.height * profile.upscale,
        interpolation: img.Interpolation.nearest,
      );
    }

    // Camera tags, like a real body writes them (the Win98 viewer reads the
    // model back for its status bar).
    image.exif = img.ExifData();
    image.exif.imageIfd
      ..make = 'Darkroom'
      ..model = spec.name
      ..software = 'Darkroom';
    final out = img.encodeJpg(image, quality: profile.jpegQuality);
    _writeAtomic(job.outputPath, out);

    final (thw, thh) = CropMath.fitLongEdge(image.width, image.height, 480);
    final thumb = img.copyResize(
      image,
      width: thw,
      height: thh,
      interpolation: profile.upscale > 1 ? img.Interpolation.nearest : img.Interpolation.average,
    );
    _writeAtomic(job.thumbPath, img.encodeJpg(thumb, quality: 80));

    return PhotoResult(
      width: image.width,
      height: image.height,
      bytes: out.length,
      flashFired: flashFired,
      originalCopyPath: originalPath,
    );
  }

  static img.Image _ensureRgb8(img.Image i) {
    if (i.numChannels == 3 && i.format == img.Format.uint8 && !i.hasPalette) return i;
    return i.convert(format: img.Format.uint8, numChannels: 3);
  }

  /// Same transforms as image's bakeOrientation, without the defensive
  /// full-size copy (we already own [i]).
  static img.Image _bakeOrientation(img.Image i, int orientation) {
    switch (orientation) {
      case 2:
        return img.flipHorizontal(i);
      case 3:
        return img.flip(i, direction: img.FlipDirection.both);
      case 4:
        return img.flipHorizontal(img.copyRotate(i, angle: 180));
      case 5:
        return img.flipHorizontal(img.copyRotate(i, angle: 90));
      case 6:
        return img.copyRotate(i, angle: 90);
      case 7:
        return img.flipHorizontal(img.copyRotate(i, angle: -90));
      case 8:
        return img.copyRotate(i, angle: -90);
      default:
        return i;
    }
  }

  static void _drawTimestamp(Uint8List data, int w, int h, TimestampStyle style, DateTime t) {
    final short = math.min(w, h);
    switch (style) {
      case TimestampStyle.ledDate:
        final text = TimestampFormat.ledDate(t);
        final dot = math.max(1, (short / 170).round());
        final tw = PixelFont.measureDots(text) * dot;
        PixelFont.drawToBuffer(
          data,
          width: w,
          height: h,
          channels: 3,
          text: text,
          left: w - tw - (w * 0.05).round(),
          top: h - PixelFont.glyphHeight * dot - (h * 0.05).round(),
          dot: dot,
          rgb: const [255, 156, 48],
          glow: const [255, 80, 0],
        );
      case TimestampStyle.phone:
        final text = TimestampFormat.phone(t);
        final dot = math.max(1, (short / 220).round());
        final tw = PixelFont.measureDots(text) * dot;
        PixelFont.drawToBuffer(
          data,
          width: w,
          height: h,
          channels: 3,
          text: text,
          left: w - tw - 3 * dot,
          top: h - PixelFont.glyphHeight * dot - 3 * dot,
          dot: dot,
          rgb: const [255, 255, 255],
          shadow: const [20, 20, 20],
        );
      case TimestampStyle.camcorderOsd:
        final lines = TimestampFormat.camcorder(t);
        final dot = math.max(1, (short / 150).round());
        final lineH = (PixelFont.glyphHeight + 3) * dot;
        for (var k = 0; k < lines.length; k++) {
          final tw = PixelFont.measureDots(lines[k]) * dot;
          PixelFont.drawToBuffer(
            data,
            width: w,
            height: h,
            channels: 3,
            text: lines[k],
            left: w - tw - (w * 0.06).round(),
            top: h - (lines.length - k) * lineH - (h * 0.06).round(),
            dot: dot,
            rgb: const [240, 240, 240],
            shadow: const [10, 10, 10],
          );
        }
      case TimestampStyle.none:
        break;
    }
  }

  static void _writeAtomic(String path, List<int> bytes) {
    final tmp = File('$path.part');
    tmp.parent.createSync(recursive: true);
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(path);
  }
}
