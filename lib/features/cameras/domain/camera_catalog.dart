import '../../../core/processing/crop_math.dart';
import '../../../core/processing/look_spec.dart';
import 'camera_spec.dart';

/// Every stock / body that ships in the app. Pure data: shared by the UI,
/// the processing isolate and the background worker.
///
/// Film looks live in core/processing/film/film_profile.dart (keyed by id).
/// Stock names are our own (ids keep the emulsion each look is modelled on,
/// for the code only); the artwork is
/// original (no logos or trade dress).
class CameraCatalog {
  const CameraCatalog._();

  static const _filmAspects = [
    AspectRatioOption.r3x2,
    AspectRatioOption.r4x3,
    AspectRatioOption.r1x1,
    AspectRatioOption.r16x9,
  ];

  // --------------------------------------------------------------------------
  // FILM
  // --------------------------------------------------------------------------

  static const ektar100 = CameraSpec(
    id: 'ektar100',
    mode: AppMode.film,
    name: 'Vivid 100',
    subtitle: 'Punchy colour for bright days',
    badge: 'ISO 100',
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 8192, jpegQuality: 92),
    aspects: _filmAspects,
    defaultAspect: AspectRatioOption.r3x2,
    artwork: 'assets/artwork/ektar100.webp',
    boxColor: 0xFFE8B323,
    boxInk: 0xFFB0201B,
  );

  static const portra400 = CameraSpec(
    id: 'portra400',
    mode: AppMode.film,
    name: 'Portrait 400',
    subtitle: 'Warm, soft tones for people',
    badge: 'ISO 400',
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 8192, jpegQuality: 92),
    aspects: _filmAspects,
    defaultAspect: AspectRatioOption.r3x2,
    artwork: 'assets/artwork/portra400.webp',
    boxColor: 0xFFF1EBDD,
    boxInk: 0xFF8C5A2B,
  );

  static const hp5 = CameraSpec(
    id: 'hp5plus400',
    mode: AppMode.film,
    name: 'Classic 400',
    subtitle: 'Gritty, classic black & white',
    badge: 'ISO 400',
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 8192, jpegQuality: 92),
    aspects: _filmAspects,
    defaultAspect: AspectRatioOption.r3x2,
    artwork: 'assets/artwork/hp5plus400.webp',
    boxColor: 0xFF1C1C1C,
    boxInk: 0xFFF2F2F2,
  );

  static const super8 = CameraSpec(
    id: 'super8',
    mode: AppMode.film,
    name: 'Super 8',
    subtitle: 'Home movies on daylight reversal film',
    badge: '18 FPS',
    quality: CaptureQuality.low,
    output: OutputProfile(maxLongEdge: 960, jpegQuality: 90),
    aspects: [AspectRatioOption.r4x3],
    defaultAspect: AspectRatioOption.r4x3,
    artwork: 'assets/artwork/super8.webp',
    recordsVideo: true,
    videoPrefix: 'REEL',
    // One 50 ft cartridge runs 3 min 20 s at 18 fps.
    videoMaxSeconds: 200,
    landscapeOnly: true,
    pickerTag: 'MOVIE · 18 FPS',
    boxColor: 0xFF22447A,
    boxInk: 0xFFF4C542,
  );

  static const polaroid600 = CameraSpec(
    id: 'polaroid600',
    mode: AppMode.film,
    name: 'Instant 600',
    subtitle: 'Instant prints you can write on',
    badge: 'ISO 640',
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 3072, jpegQuality: 90),
    aspects: [AspectRatioOption.r1x1],
    defaultAspect: AspectRatioOption.r1x1,
    artwork: 'assets/artwork/polaroid600.webp',
    developTime: Duration(seconds: 20),
    printStyle: PrintStyle.instant,
    roll: FilmRoll(prefix: 'PACK', frames: 8, counter: 'instant', countsDown: true),
    pickerTag: 'INSTANT · 20 S',
    boxColor: 0xFFF7F5EF,
    boxInk: 0xFF1A1A1A,
  );

  // --------------------------------------------------------------------------
  // DIGITAL
  // --------------------------------------------------------------------------

  static const floppy = CameraSpec(
    id: 'floppy99',
    mode: AppMode.digital,
    name: '1999 Floppy Cam',
    subtitle: 'Soft VGA snaps saved to a 1.44MB disk',
    badge: '640x480',
    look: LookSpec(
      kind: ShaderKind.ccd,
      matrix: [
        1.0, -0.02, 0.06, //
        -0.02, 0.95, 0.02, //
        0.03, -0.03, 0.97,
      ],
      offset: [0.035, 0.015, 0.035],
      saturation: 0.74,
      exposure: 0.97,
      gamma: 1.0,
      contrast: 1.06,
      pivot: 0.5,
      black: 0.065,
      white: 0.9,
      vignette: 0.08,
      grainAmount: 0.015,
      grainSize: 1.4,
      flashStrength: 0.95,
      sharpen: 0.35,
      chromaNoise: 0.06,
      bloom: 0.12,
      smear: 0.1,
    ),
    quality: CaptureQuality.low,
    output: OutputProfile(maxLongEdge: 640, jpegQuality: 88, lowResLongEdge: 640, lowResJpegQuality: 60),
    aspects: [AspectRatioOption.r4x3],
    defaultAspect: AspectRatioOption.r4x3,
    artwork: 'assets/artwork/floppy99.webp',
    photoPrefix: 'FLP0',
    zoom: ZoomSpec(max: 3),
  );

  static const ccd2003 = CameraSpec(
    id: 'ccd2003',
    mode: AppMode.digital,
    name: '2003 CCD Compact',
    subtitle: 'Warm, natural 2000s point-and-shoot',
    badge: '4.0MP',
    look: LookSpec(
      kind: ShaderKind.ccd,
      matrix: [
        1.02, 0.0, -0.02, //
        0.0, 1.0, 0.0, //
        0.0, 0.02, 0.94,
      ],
      offset: [0.0, 0.0, -0.005],
      saturation: 0.9,
      exposure: 0.98,
      gamma: 1.0,
      contrast: 1.08,
      pivot: 0.5,
      black: 0.015,
      white: 0.97,
      vignette: 0.06,
      grainAmount: 0.01,
      grainSize: 1.0,
      flashStrength: 0.9,
      sharpen: 0.3,
      chromaNoise: 0.04,
      bloom: 0.12,
      smear: 0.08,
    ),
    quality: CaptureQuality.standard,
    output: OutputProfile(maxLongEdge: 1600, jpegQuality: 82),
    aspects: [
      AspectRatioOption.r4x3,
      AspectRatioOption.r3x2,
      AspectRatioOption.r16x9,
      AspectRatioOption.r1x1,
    ],
    defaultAspect: AspectRatioOption.r4x3,
    artwork: 'assets/artwork/ccd2003.webp',
    timestampStyle: TimestampStyle.ledDate,
    photoPrefix: 'DSC0',
    zoom: ZoomSpec(max: 3),
  );

  static const flipPhone = CameraSpec(
    id: 'flipphone',
    mode: AppMode.digital,
    name: 'Y2K Flip Phone',
    subtitle: 'Blocky VGA snaps, square crop',
    badge: 'VGA',
    look: LookSpec(
      kind: ShaderKind.jpegPixel,
      matrix: [
        1.00, 0.05, -0.05, //
        0.02, 1.02, -0.04, //
        0.03, 0.00, 0.90,
      ],
      offset: [0.02, 0.03, 0.0],
      saturation: 0.9,
      exposure: 1.06,
      gamma: 0.9,
      contrast: 1.3,
      pivot: 0.55,
      black: 0.06,
      white: 0.94,
      vignette: 0.25,
      grainAmount: 0.03,
      grainSize: 1.0,
      flashStrength: 0.8,
      lowRes: 240,
      posterize: 48,
      artifact: 0.65,
    ),
    quality: CaptureQuality.low,
    output: OutputProfile(
      maxLongEdge: 720,
      jpegQuality: 90,
      lowResLongEdge: 240,
      lowResJpegQuality: 18,
      upscale: 3,
    ),
    aspects: [AspectRatioOption.r1x1],
    defaultAspect: AspectRatioOption.r1x1,
    artwork: 'assets/artwork/flipphone.webp',
    timestampStyle: TimestampStyle.phone,
    photoPrefix: 'IMG_',
    // Phone-camera digital zoom.
    zoom: ZoomSpec(max: 4, endToEnd: Duration(milliseconds: 1600)),
  );

  static const camcorder = CameraSpec(
    id: 'camcorder90',
    mode: AppMode.digital,
    name: '90s Camcorder',
    subtitle: 'Home video on tape, with sound',
    badge: 'SP',
    look: LookSpec(
      // Tuned to Gabe's tapes: bright (skies blow out), soft, pastel
      // colour with blue-cyan skies, lifted blacks, no visible scanlines;
      // edge halos and the odd dropout come from the signal path.
      kind: ShaderKind.vhs,
      matrix: [
        1.0, 0.0, 0.0, //
        0.0, 1.0, 0.02, //
        0.0, 0.03, 1.04,
      ],
      offset: [0.01, 0.01, 0.03],
      saturation: 0.72,
      exposure: 1.12,
      gamma: 0.88,
      contrast: 0.92,
      pivot: 0.5,
      black: 0.07,
      white: 1.0,
      vignette: 0.05,
      grainAmount: 0.025,
      grainSize: 1.2,
      flashStrength: 0.5,
      scanline: 0.06,
      bleed: 0.7,
      jitter: 0.35,
      // dropouts / tears: how often (TapeDropouts, the shader's glitches)
      tracking: 0.5,
      lines: 240,
    ),
    quality: CaptureQuality.low,
    output: OutputProfile(
      maxLongEdge: 1280,
      jpegQuality: 88,
      lowResLongEdge: 640,
      lowResJpegQuality: 80,
      upscale: 2,
    ),
    aspects: [AspectRatioOption.r4x3, AspectRatioOption.r16x9],
    defaultAspect: AspectRatioOption.r4x3,
    artwork: 'assets/artwork/camcorder90.webp',
    timestampStyle: TimestampStyle.camcorderOsd,
    recordsVideo: true,
    photoPrefix: 'PICT',
    videoPrefix: 'CLIP',
    videoMaxSeconds: 900,
    // Slow, steady motor zoom of a 90s camcorder.
    zoom: ZoomSpec(max: 10, endToEnd: Duration(milliseconds: 4200)),
    pickerTag: 'VIDEO',
    // Tapes are captured onto floppies; copying them off takes disk swaps.
    storage: DigitalStorage.floppy,
  );

  static const List<CameraSpec> film = [ektar100, portra400, hp5, polaroid600, super8];
  static const List<CameraSpec> digital = [floppy, ccd2003, flipPhone, camcorder];
  static const List<CameraSpec> all = [...film, ...digital];

  static List<CameraSpec> forMode(AppMode mode) => mode == AppMode.film ? film : digital;

  static CameraSpec byId(String id) => all.firstWhere((c) => c.id == id, orElse: () => ektar100);
}
