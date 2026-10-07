import '../../../core/processing/crop_math.dart';
import '../../../core/processing/film/film_profile.dart';
import '../../../core/processing/look_spec.dart';

/// Top-level app mode. The whole UI re-skins when this flips.
enum AppMode { film, digital }

/// Capture resolution class. Mapped to the camera plugin's ResolutionPreset
/// in the camera layer so this file stays pure Dart (it is also used by the
/// background isolate / WorkManager entrypoint).
enum CaptureQuality {
  /// Film: 1080p-class sensor stream (smooth shader preview).
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

/// How a developed film still is presented on the corkboard, in the viewer
/// and in exported files.
enum PrintStyle {
  /// Glossy print with a thin white border (the border is display-only).
  print,

  /// Instant print: square picture, deep bottom border you can write on. The
  /// frame and the note are baked into saved / shared files.
  instant,
}

/// The roll or pack a film body shoots (file names and the frame counter).
class FilmRoll {
  const FilmRoll({this.prefix = 'ROLL', this.frames = 36, this.counter = 'film', this.countsDown = false});

  /// File names read PREFIX001_07.JPG (roll 1, frame 7).
  final String prefix;
  final int frames;

  /// Shared numbering key: bodies using the same key share one roll.
  final String counter;

  /// Counter shows shots left (instant packs) instead of the next frame.
  final bool countsDown;
}

/// Where a digital body's files turn up in the Win98 explorer.
enum DigitalStorage {
  /// SD Card (E:).
  sdCard,

  /// 3½ Floppy (A:): tape captured onto floppies, copied off disk by disk.
  floppy,
}

/// Motorised zoom on digital bodies: held W/T buttons drive it at a fixed rate.
class ZoomSpec {
  const ZoomSpec({required this.max, this.endToEnd = const Duration(milliseconds: 2400)});

  /// Longest focal length as a multiple of the widest (clamped to what the
  /// phone's camera supports).
  final double max;

  /// Time for a full W-to-T sweep.
  final Duration endToEnd;
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
    this.landscapeOnly = false,
    this.developTime = defaultDevelopTime,
    this.printStyle = PrintStyle.print,
    this.roll = const FilmRoll(),
    this.zoom,
    this.pickerTag,
    this.storage = DigitalStorage.sdCard,
    this.boxColor = 0xFFE3D8C3,
    this.boxInk = 0xFF2A2420,
  });

  /// Darkroom time for film shots unless a stock says otherwise.
  static const defaultDevelopTime = Duration(minutes: 5);

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

  /// Always frames landscape, even with the phone held upright (a landscape
  /// slice of the view). Super 8.
  final bool landscapeOnly;

  /// Film: how long a shot spends in the darkroom.
  final Duration developTime;

  /// Film stills: plain print or instant print.
  final PrintStyle printStyle;

  /// Film stills: roll / pack naming and the frame counter.
  final FilmRoll roll;

  /// Digital: motorised zoom range. Film bodies never zoom (null).
  final ZoomSpec? zoom;

  /// Optional tag under the name in the picker (e.g. "MOVIE · 18 FPS").
  final String? pickerTag;

  /// Digital: which drive the files land on in the explorer.
  final DigitalStorage storage;

  /// Film: colours of the box end slipped into the camera's memo holder
  /// (ARGB; kept as ints so this file stays pure Dart).
  final int boxColor;
  final int boxInk;

  /// Film stocks: the emulsion model shared by shader, stills and video.
  FilmProfile? get film => FilmProfile.forStock(id);

  bool get isFilm => mode == AppMode.film;
  bool get isMono => film?.mono ?? look?.mono ?? false;
  bool get aspectLocked => aspects.length == 1;
  bool get supportsTimestamp => timestampStyle != TimestampStyle.none;
  bool get isInstant => printStyle == PrintStyle.instant;
}
