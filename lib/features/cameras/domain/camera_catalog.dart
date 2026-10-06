import '../../../core/processing/crop_math.dart';
import '../../../core/processing/look_spec.dart';
import 'camera_spec.dart';

/// Every stock / body that ships in the app. Pure data: shared by the UI,
/// the processing isolate and the background worker.
///
/// Film looks live in core/processing/film/film_profile.dart (keyed by id).
/// Stock names describe which emulsion a look is modelled on; the artwork is
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
    name: 'Ektar 100',
    subtitle: 'Punchy colour for bright days',
    badge: 'ISO 100',
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 4096, jpegQuality: 92),
    aspects: _filmAspects,
    defaultAspect: AspectRatioOption.r3x2,
    artwork: 'assets/artwork/ektar100.webp',
  );

  static const portra400 = CameraSpec(
    id: 'portra400',
    mode: AppMode.film,
    name: 'Portra 400',
    subtitle: 'Warm, soft tones for people',
    badge: 'ISO 400',
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 4096, jpegQuality: 92),
    aspects: _filmAspects,
    defaultAspect: AspectRatioOption.r3x2,
    artwork: 'assets/artwork/portra400.webp',
  );

  static const hp5 = CameraSpec(
    id: 'hp5plus400',
    mode: AppMode.film,
    name: 'HP5 Plus 400',
    subtitle: 'Gritty, classic black & white',
    badge: 'ISO 400',
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 4096, jpegQuality: 92),
    aspects: _filmAspects,
    defaultAspect: AspectRatioOption.r3x2,
    artwork: 'assets/artwork/hp5plus400.webp',
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
        1.04, 0.00, -0.02, //
        -0.02, 0.98, 0.04, //
        0.02, -0.03, 0.96,
      ],
      offset: [0.025, 0.0, 0.02],
      saturation: 0.86,
      exposure: 1.18, // tiny sensor, tiny dynamic range: highlights clip early
      gamma: 0.9,
      contrast: 1.12,
      pivot: 0.5,
      black: 0.035,
      white: 0.985,
      vignette: 0.22,
      grainAmount: 0.022,
      grainSize: 1.6,
      flashStrength: 0.95,
      sharpen: -0.35, // soft plastic lens
      chromaNoise: 0.10,
      bloom: 0.55,
      smear: 0.65, // vertical CCD smear from bright lights
    ),
    quality: CaptureQuality.low,
    output: OutputProfile(maxLongEdge: 640, jpegQuality: 88, lowResLongEdge: 640, lowResJpegQuality: 48),
    aspects: [AspectRatioOption.r4x3],
    defaultAspect: AspectRatioOption.r4x3,
    artwork: 'assets/artwork/floppy99.webp',
    photoPrefix: 'FLP0',
  );

  static const ccd2003 = CameraSpec(
    id: 'ccd2003',
    mode: AppMode.digital,
    name: '2003 CCD Compact',
    subtitle: 'Cool, crunchy 2000s point-and-shoot',
    badge: '4.0MP',
    look: LookSpec(
      kind: ShaderKind.ccd,
      matrix: [
        0.95, 0.03, 0.02, //
        0.00, 1.00, 0.02, //
        0.00, 0.05, 1.08,
      ],
      offset: [-0.012, 0.0, 0.03],
      saturation: 1.12,
      exposure: 1.13, // pushes the top of the histogram into hard clip
      gamma: 0.92,
      contrast: 1.2,
      pivot: 0.5,
      vignette: 0.08,
      grainAmount: 0.012,
      grainSize: 1.0,
      flashStrength: 0.9,
      sharpen: 0.6,
      chromaNoise: 0.06,
      bloom: 0.35,
      smear: 0.25,
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
  );

  static const camcorder = CameraSpec(
    id: 'camcorder90',
    mode: AppMode.digital,
    name: '90s Camcorder',
    subtitle: 'Home video on tape, with sound',
    badge: 'SP',
    look: LookSpec(
      kind: ShaderKind.vhs,
      matrix: [
        1.05, 0.00, 0.00, //
        0.00, 0.95, 0.03, //
        0.02, 0.00, 0.95,
      ],
      offset: [0.02, 0.0, 0.02],
      saturation: 1.15,
      exposure: 1.05,
      gamma: 0.95,
      contrast: 1.05,
      pivot: 0.5,
      black: 0.05,
      white: 0.95,
      vignette: 0.2,
      grainAmount: 0.035,
      grainSize: 1.2,
      flashStrength: 0.5,
      scanline: 0.28,
      bleed: 0.55,
      jitter: 0.6,
      tracking: 0.55,
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
  );

  static const List<CameraSpec> film = [ektar100, portra400, hp5, super8];
  static const List<CameraSpec> digital = [floppy, ccd2003, flipPhone, camcorder];
  static const List<CameraSpec> all = [...film, ...digital];

  static List<CameraSpec> forMode(AppMode mode) => mode == AppMode.film ? film : digital;

  static CameraSpec byId(String id) => all.firstWhere((c) => c.id == id, orElse: () => ektar100);
}
