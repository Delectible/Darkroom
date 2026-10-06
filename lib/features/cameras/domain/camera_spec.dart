import '../../../core/processing/crop_math.dart';
import '../../../core/processing/film/film_profile.dart';
import '../../../core/processing/look_spec.dart';

/// Top-level app mode. The whole UI re-skins when this flips.
enum AppMode { film, digital }

/// Capture resolution class. Mapped to the camera plugin's ResolutionPreset
/// in the camera layer so this file stays pure Dart (it is also used by the
/// background isolate / WorkManager entrypoint).
enum CaptureQuality {
  /// Film: 1080p-class sensor stream by default (smooth on old phones); the
  /// "High-resolution film" setting raises it to 2160p-class.
  high,

  /// ~1080p class: authentic for 2000s digicams and keeps processing cheap.
  standard,

  /// ~480p class: VGA phones, floppy cameras, tape and Super 8. Cheapest
  /// preview and the fastest video processing.
  low,
}

/// How the date/time is burned into digital captures.
enum TimestampStyle { none, ledDate, phone, camcorderOsd }

/// Export parameters for stills.
class OutputProfile {
  const OutputProfile({
    required this.maxLongEdge,
    required this.jpegQuality,
    this.lowResLongEdge,
    this.lowResJpegQuality,
    this.upscale = 1,
  });

  /// Long edge cap for the exported frame (memory + authenticity).
  final int maxLongEdge;
  final int jpegQuality;

  /// When set, the frame is rendered at this size, really JPEG-compressed at
  /// [lowResJpegQuality], then nearest-neighbour upscaled by [upscale] so the
  /// fat pixels / scanlines survive modern image viewers.
  final int? lowResLongEdge;
  final int? lowResJpegQuality;
  final int upscale;
}

class CameraSpec {
  const CameraSpec({
    required this.id,
    required this.mode,
    required this.name,
    required this.subtitle,
    required this.badge,
    required this.quality,
    required this.output,
    required this.aspects,
    required this.defaultAspect,
    required this.artwork,
    this.look,
    this.timestampStyle = TimestampStyle.none,
    this.recordsVideo = false,
    this.photoPrefix = 'IMG_',
    this.videoPrefix = 'MOV',
    this.videoMaxSeconds = 600,
  });

  final String id;
  final AppMode mode;
  final String name;
  final String subtitle;

  /// Short text in the viewfinder HUD ("ISO 400", "2.0MP", ...).
  final String badge;

  /// Digital looks (matrix + curve shaders). Film stocks use [film] instead.
  final LookSpec? look;
  final CaptureQuality quality;
  final OutputProfile output;
  final List<AspectRatioOption> aspects;
  final AspectRatioOption defaultAspect;

  /// Rendered product shot used by the stock picker (asset path).
  final String artwork;
  final TimestampStyle timestampStyle;

  /// The camera style decides the medium: video cameras (camcorder, Super 8)
  /// only record clips, everything else only takes stills.
  final bool recordsVideo;

  /// 8.3 file name prefixes on the virtual SD card (DSC0, MOV0, ...).
  final String photoPrefix;
  final String videoPrefix;
  final int videoMaxSeconds;

  /// Film stocks: the emulsion model shared by shader, stills and video.
  FilmProfile? get film => FilmProfile.forStock(id);

  bool get isFilm => mode == AppMode.film;
  bool get isMono => film?.mono ?? look?.mono ?? false;
  bool get aspectLocked => aspects.length == 1;
  bool get supportsTimestamp => timestampStyle != TimestampStyle.none;
}
