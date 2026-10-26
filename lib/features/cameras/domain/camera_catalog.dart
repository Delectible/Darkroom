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
    subtitle: 'ISO 100: ultra-fine, punchy colour. Needs sun',
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
    subtitle: 'ISO 400 portrait film: soft skin, any light',
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
    subtitle: 'ISO 400 press B&W: gritty, copes with dusk',
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
    subtitle: 'Home movies on slow daylight film: go outside',
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
    subtitle: 'ISO 640 instant prints. Best with the flash',
    badge: 'ISO 640',
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 3072, jpegQuality: 90),
    aspects: [AspectRatioOption.r1x1],
    defaultAspect: AspectRatioOption.r1x1,
    artwork: 'assets/artwork/polaroid600.webp',
    developTime: Duration(seconds: 40),
    printStyle: PrintStyle.instant,
    roll: FilmRoll(prefix: 'PACK', frames: 8, counter: 'instant', countsDown: true),
    pickerTag: 'INSTANT · 20 S',
    boxColor: 0xFFF7F5EF,
    boxInk: 0xFF1A1A1A,
  );

  // --- Pro films (1.9). Artwork: placeholders until their renders are made.

  static const gold200 = CameraSpec(
    id: 'gold200',
    mode: AppMode.film,
    name: 'Golden 200',
    subtitle: 'ISO 200 drugstore classic: warm, golden days',
    badge: 'ISO 200',
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 8192, jpegQuality: 92),
    aspects: _filmAspects,
    defaultAspect: AspectRatioOption.r3x2,
    artwork: 'assets/artwork/gold200.webp',
    boxColor: 0xFFF2B705,
    boxInk: 0xFF8E1B12,
    pro: true,
  );

  static const night800 = CameraSpec(
    id: 'cinestill800t',
    mode: AppMode.film,
    name: 'Night 800T',
    subtitle: 'ISO 800 tungsten cine film: made for night',
    badge: 'ISO 800',
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 8192, jpegQuality: 92),
    aspects: _filmAspects,
    defaultAspect: AspectRatioOption.r3x2,
    artwork: 'assets/artwork/cinestill800t.webp',
    boxColor: 0xFF1E2A44,
    boxInk: 0xFFE8503A,
    pro: true,
  );

  static const chrome50 = CameraSpec(
    id: 'velvia50',
    mode: AppMode.film,
    name: 'Chrome 50',
    subtitle: 'ISO 50 slide film: vivid, needs strong light',
    badge: 'ISO 50',
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 8192, jpegQuality: 92),
    aspects: _filmAspects,
    defaultAspect: AspectRatioOption.r3x2,
    artwork: 'assets/artwork/velvia50.webp',
    boxColor: 0xFF2E7D4F,
    boxInk: 0xFFF5F0E0,
    pro: true,
  );

  static const singleUse = CameraSpec(
    id: 'superia400',
    mode: AppMode.film,
    name: 'Single-Use 27',
    subtitle: 'Disposable: fixed f/10, use the flash indoors',
    badge: '27 EXP',
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 4096, jpegQuality: 90),
    aspects: [AspectRatioOption.r3x2],
    defaultAspect: AspectRatioOption.r3x2,
    artwork: 'assets/artwork/superia400.webp',
    roll: FilmRoll(frames: 27, countsDown: true),
    pickerTag: 'DISPOSABLE',
    boxColor: 0xFF2F8F3E,
    boxInk: 0xFFF6F2E6,
    pro: true,
  );

  static const epic70 = CameraSpec(
    id: 'vision70',
    mode: AppMode.film,
    name: 'Epic 70',
    subtitle: '70mm cinema film: wide, rich, ultra-fine',
    badge: '24 FPS',
    quality: CaptureQuality.standard,
    output: OutputProfile(maxLongEdge: 1920, jpegQuality: 92),
    aspects: [AspectRatioOption.r16x9],
    defaultAspect: AspectRatioOption.r16x9,
    artwork: 'assets/artwork/vision70.webp',
    recordsVideo: true,
    videoPrefix: 'EPIC',
    videoMaxSeconds: 300,
    landscapeOnly: true,
    pickerTag: 'MOVIE · 70MM',
    boxColor: 0xFF101010,
    boxInk: 0xFFD8B25A,
    pro: true,
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
    subtitle: 'Soft VGA snaps in 4096 colours',
    badge: 'VGA',
    look: LookSpec(
      kind: ShaderKind.jpegPixel,
      matrix: [
        0.97, 0.0, 0.06, //
        0.0, 1.02, -0.04, //
        0.03, -0.03, 1.04,
      ],
      offset: [0.01, 0.0, 0.03],
      saturation: 1.15,
      exposure: 1.12,
      gamma: 0.92,
      contrast: 1.0,
      pivot: 0.5,
      black: 0.09,
      white: 0.9,
      vignette: 0.12,
      grainAmount: 0.025,
      grainSize: 1.0,
      sharpen: -0.3,
      flashStrength: 0.8,
      lowRes: 480,
      // 16 levels a channel: 4096 colours.
      posterize: 16,
      artifact: 0.5,
    ),
    quality: CaptureQuality.low,
    output: OutputProfile(
      maxLongEdge: 960,
      jpegQuality: 90,
      // A VGA sensor's square crop.
      lowResLongEdge: 480,
      lowResJpegQuality: 30,
      upscale: 2,
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
      // Tuned to the owner's tapes: bright (skies blow out), soft, pastel
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

  // --- Pro cameras (1.9). Artwork: placeholders until their renders are made.

  static const webcam = CameraSpec(
    id: 'webcam05',
    mode: AppMode.digital,
    name: '2005 Webcam',
    subtitle: 'Grainy 320x240 snaps off the top of a CRT',
    badge: '0.3MP',
    look: LookSpec(
      kind: ShaderKind.ccd,
      matrix: [
        0.96, 0.02, 0.06, //
        0.0, 1.0, 0.02, //
        0.04, 0.0, 1.08,
      ],
      offset: [0.02, 0.01, 0.05],
      saturation: 0.82,
      exposure: 1.08,
      gamma: 0.95,
      contrast: 1.02,
      pivot: 0.5,
      black: 0.06,
      white: 0.92,
      vignette: 0.22,
      grainAmount: 0.05,
      grainSize: 1.6,
      flashStrength: 0.0,
      sharpen: -0.2,
      chromaNoise: 0.14,
      bloom: 0.2,
      smear: 0.15,
      lowRes: 320,
    ),
    quality: CaptureQuality.low,
    output: OutputProfile(
      maxLongEdge: 960,
      jpegQuality: 88,
      lowResLongEdge: 320,
      lowResJpegQuality: 55,
      upscale: 3,
    ),
    aspects: [AspectRatioOption.r4x3],
    defaultAspect: AspectRatioOption.r4x3,
    artwork: 'assets/artwork/webcam05.webp',
    photoPrefix: 'SNAP',
    zoom: ZoomSpec(max: 2),
    pro: true,
  );

  static const dslr = CameraSpec(
    id: 'dslr08',
    mode: AppMode.digital,
    name: '2008 Starter DSLR',
    subtitle: 'Crisp 10MP with that kit-lens punch',
    badge: '10MP',
    look: LookSpec(
      kind: ShaderKind.ccd,
      matrix: [
        1.04, -0.02, -0.02, //
        -0.01, 1.03, -0.02, //
        -0.01, -0.03, 1.04,
      ],
      offset: [0.0, 0.0, 0.0],
      saturation: 1.12,
      exposure: 1.0,
      gamma: 1.0,
      contrast: 1.14,
      pivot: 0.5,
      black: 0.0,
      white: 1.0,
      vignette: 0.1,
      grainAmount: 0.006,
      grainSize: 1.0,
      flashStrength: 0.85,
      sharpen: 0.45,
      chromaNoise: 0.02,
      bloom: 0.06,
      smear: 0.0,
    ),
    quality: CaptureQuality.high,
    output: OutputProfile(maxLongEdge: 3888, jpegQuality: 92),
    aspects: [AspectRatioOption.r3x2, AspectRatioOption.r4x3, AspectRatioOption.r1x1],
    defaultAspect: AspectRatioOption.r3x2,
    artwork: 'assets/artwork/dslr08.webp',
    photoPrefix: 'IMG_',
    zoom: ZoomSpec(max: 3),
    pro: true,
  );

  static const toyCam = CameraSpec(
    id: 'toycam',
    mode: AppMode.digital,
    name: 'Toy Pixel Cam',
    subtitle: 'A keychain toy cam: chunky pixels, 4 colours',
    badge: '128px',
    look: LookSpec(
      kind: ShaderKind.jpegPixel,
      matrix: [
        1.0, 0.0, 0.0, //
        0.0, 1.0, 0.0, //
        0.0, 0.0, 1.0,
      ],
      offset: [0.0, 0.0, 0.0],
      saturation: 1.3,
      exposure: 1.1,
      gamma: 0.95,
      contrast: 1.15,
      pivot: 0.5,
      black: 0.04,
      white: 0.96,
      vignette: 0.1,
      grainAmount: 0.0,
      grainSize: 1.0,
      sharpen: 0.0,
      flashStrength: 0.7,
      lowRes: 128,
      posterize: 4,
      artifact: 0.2,
    ),
    quality: CaptureQuality.low,
    output: OutputProfile(
      maxLongEdge: 1024,
      jpegQuality: 92,
      lowResLongEdge: 128,
      lowResJpegQuality: 90,
      upscale: 8,
    ),
    aspects: [AspectRatioOption.r1x1],
    defaultAspect: AspectRatioOption.r1x1,
    artwork: 'assets/artwork/toycam.webp',
    photoPrefix: 'TOY_',
    zoom: ZoomSpec(max: 2),
    pro: true,
  );

  static const miniDv = CameraSpec(
    id: 'minidv04',
    mode: AppMode.digital,
    name: '2004 MiniDV',
    subtitle: 'Digital tape: sharp, saturated, interlaced',
    badge: 'DV',
    look: LookSpec(
      kind: ShaderKind.vhs,
      matrix: [
        1.02, 0.0, -0.02, //
        0.0, 1.02, 0.0, //
        -0.01, 0.0, 1.02,
      ],
      offset: [0.0, 0.0, 0.01],
      saturation: 1.1,
      exposure: 1.04,
      gamma: 0.95,
      contrast: 1.06,
      pivot: 0.5,
      black: 0.03,
      white: 0.98,
      vignette: 0.04,
      grainAmount: 0.012,
      grainSize: 1.0,
      flashStrength: 0.5,
      scanline: 0.08,
      bleed: 0.2,
      jitter: 0.05,
      tracking: 0.05,
      lines: 480,
    ),
    quality: CaptureQuality.standard,
    output: OutputProfile(
      maxLongEdge: 1440,
      jpegQuality: 90,
      lowResLongEdge: 720,
      lowResJpegQuality: 85,
      upscale: 2,
    ),
    aspects: [AspectRatioOption.r4x3, AspectRatioOption.r16x9],
    defaultAspect: AspectRatioOption.r16x9,
    artwork: 'assets/artwork/minidv04.webp',
    timestampStyle: TimestampStyle.camcorderOsd,
    recordsVideo: true,
    photoPrefix: 'DSCF',
    videoPrefix: 'MDV_',
    videoMaxSeconds: 900,
    zoom: ZoomSpec(max: 10, endToEnd: Duration(milliseconds: 3000)),
    pickerTag: 'VIDEO',
    pro: true,
  );

  static const List<CameraSpec> film = [
    ektar100, portra400, hp5, polaroid600, super8, //
    gold200, night800, chrome50, singleUse, epic70,
  ];
  static const List<CameraSpec> digital = [
    floppy, ccd2003, flipPhone, camcorder, //
    webcam, dslr, toyCam, miniDv,
  ];
  static const List<CameraSpec> all = [...film, ...digital];

  static List<CameraSpec> forMode(AppMode mode) => mode == AppMode.film ? film : digital;

  static CameraSpec byId(String id) => all.firstWhere((c) => c.id == id, orElse: () => ektar100);
}
