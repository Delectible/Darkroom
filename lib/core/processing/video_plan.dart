import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../features/cameras/domain/camera_catalog.dart';
import '../../features/cameras/domain/camera_spec.dart';
import '../utils/pixel_font.dart';
import 'cine_strip.dart';
import 'crop_math.dart';
import 'film/film_lut.dart';
import 'film/film_profile.dart';
import 'look_spec.dart';
import 'video_filters.dart';

class VideoJob {
  const VideoJob({
    required this.id,
    required this.cameraId,
    required this.rawPath,
    required this.outputPath,
    required this.thumbPath,
    required this.workDir,
    required this.aspect,
    required this.previewAspect,
    required this.timestamp,
    required this.capturedAtMs,
    required this.durationMs,
    this.rotationTurns = 0,
    this.grain = GrainStrength.normal,
    this.zoomTrack = const [],
  });

  final String id;
  final String cameraId;
  final String rawPath;
  final String outputPath;
  final String thumbPath;

  /// Scratch dir for probe frames / OSD PNGs / pass-1 files. Deleted after.
  final String workDir;
  final AspectRatioOption aspect;
  final double previewAspect;
  final bool timestamp;
  final int capturedAtMs;
  final int durationMs;

  /// Clockwise quarter turns (see PhotoJob.rotationTurns).
  final int rotationTurns;

  /// Film (Super 8) grain strength.
  final GrainStrength grain;

  /// Zoom motor during the take, flattened [ms, position, ms, position, ...]
  /// with position 0 (wide) .. 1 (tele). Empty: never zoomed. Drives the
  /// burned-in camcorder zoom bar.
  final List<double> zoomTrack;

  Map<String, Object?> toJson() => {
    'id': id,
    'cameraId': cameraId,
    'rawPath': rawPath,
    'outputPath': outputPath,
    'thumbPath': thumbPath,
    'workDir': workDir,
    'aspect': aspect.name,
    'previewAspect': previewAspect,
    'timestamp': timestamp,
    'capturedAtMs': capturedAtMs,
    'durationMs': durationMs,
    'rotationTurns': rotationTurns,
    'grain': grain.name,
    'zoomTrack': zoomTrack,
  };

  factory VideoJob.fromJson(Map<String, Object?> j) => VideoJob(
    id: j['id']! as String,
    cameraId: j['cameraId']! as String,
    rawPath: j['rawPath']! as String,
    outputPath: j['outputPath']! as String,
    thumbPath: j['thumbPath']! as String,
    workDir: j['workDir']! as String,
    aspect: AspectRatioOption.fromName(j['aspect'] as String?, AspectRatioOption.r4x3),
    previewAspect: (j['previewAspect']! as num).toDouble(),
    timestamp: j['timestamp']! as bool,
    capturedAtMs: j['capturedAtMs']! as int,
    durationMs: j['durationMs']! as int,
    rotationTurns: j['rotationTurns'] as int? ?? 0,
    grain: GrainStrength.fromName(j['grain'] as String?),
    zoomTrack: [for (final v in (j['zoomTrack'] as List<Object?>? ?? const [])) (v! as num).toDouble()],
  );
}

/// Everything FFmpeg needs for one clip, minus the encoder choice (which is
/// platform-dependent and negotiated at run time by VideoPipeline).
class VideoPlan {
  const VideoPlan({
    required this.mainInputArgs,
    required this.mainOutputArgs,
    required this.bitrateKbps,
    required this.outW,
    required this.outH,
    required this.upscale,
    required this.pass1Path,
  });

  /// Inputs, filtergraph, stream maps and audio settings.
  final List<String> mainInputArgs;

  /// Container flags + output path of the first pass.
  final List<String> mainOutputArgs;
  final int bitrateKbps;
  final int outW;
  final int outH;
  final int upscale;

  /// Where pass 1 writes (== job output when there is no upscale pass).
  final String pass1Path;

  int get finalW => outW * upscale;
  int get finalH => outH * upscale;

  List<String> upscaleInputArgs() => [
    '-y',
    '-i',
    pass1Path,
    '-vf',
    'scale=$finalW:$finalH:flags=neighbor,format=yuv420p',
    '-c:a',
    'copy',
  ];
}

/// Pure-Dart planning step (no plugins): computes the crop from the probed,
/// autorotated frame size, writes the side inputs (scanline mask, timestamp
/// OSD frames) and assembles the FFmpeg arguments. Runs in an isolate.
class VideoPlanner {
  const VideoPlanner._();

  static VideoPlan prepare(VideoJob job, {required int probeWidth, required int probeHeight}) {
    final spec = CameraCatalog.byId(job.cameraId);
    final profile = VideoProfile.forSpec(spec);
    Directory(job.workDir).createSync(recursive: true);

    final turns = (probeHeight > probeWidth) ? job.rotationTurns % 4 : 0;
    final crop = CropMath.stillCrop(
      width: probeWidth,
      height: probeHeight,
      previewAspect: job.previewAspect,
      ratio: job.aspect,
      // Super 8 is landscape even with the phone upright.
      acrossShortSide: spec.landscapeOnly && probeHeight > probeWidth && turns.isEven,
    );
    final (cw, ch) = VideoFilters.outputSize(crop, profile);
    final (outW, outH) = turns.isOdd ? (ch, cw) : (cw, ch);
    // What gets encoded: the picture, or the full-gate film strip around it.
    var (planW, planH) = (outW, outH);

    final inputs = <String>['-y', '-i', job.rawPath];
    final String graph;
    final film = spec.film;
    if (film != null) {
      // Super 8: LUT (sRGB input), dust/hair loop and projector gate.
      final cube = p.join(job.workDir, 'stock.cube');
      File(
        cube,
      ).writeAsStringSync(FilmLut.build(film, input: LutInput.srgb, size: 33).toCube(title: spec.name));
      _renderDustFrames(job.workDir, outW, outH, seed: job.id.hashCode);
      if (film.gate > 0) (planW, planH) = CineStrip.canvasSize(outW, outH);
      File(
        p.join(job.workDir, 'gate.png'),
      ).writeAsBytesSync(film.gate > 0 ? _stripPng(planW, planH) : _gatePng(outW, outH, 0));
      inputs
        ..addAll([
          '-stream_loop',
          '-1',
          '-framerate',
          profile.fps,
          '-i',
          p.join(job.workDir, 'dust_%03d.png'),
        ])
        ..addAll(['-loop', '1', '-framerate', profile.fps, '-i', p.join(job.workDir, 'gate.png')]);
      graph = VideoFilters.filmGraph(
        film: film,
        grain: job.grain,
        cubePath: cube,
        crop: crop,
        outW: outW,
        outH: outH,
        profile: profile,
        rotateTurns: turns,
        canvasW: planW,
        canvasH: planH,
      );
    } else {
      final look = spec.look!;
      var nextInput = 1;
      if (look.kind == ShaderKind.vhs) {
        final scan = p.join(job.workDir, 'scan.png');
        File(scan).writeAsBytesSync(_scanlinePng(outW, outH, look.scanline));
        inputs.addAll(['-loop', '1', '-i', scan]);
        nextInput++;
      }
      final hasOsd = VideoFilters.wantsOsd(spec, job.timestamp);
      var osdW = 0, osdH = 0;
      if (hasOsd) {
        (osdW, osdH) = _renderOsdFrames(
          dir: job.workDir,
          style: spec.timestampStyle,
          start: DateTime.fromMillisecondsSinceEpoch(job.capturedAtMs),
          frames: (job.durationMs / 1000).ceil() + 1,
          frameHeight: outH,
        );
        inputs.addAll(['-framerate', '1', '-start_number', '0', '-i', p.join(job.workDir, 'osd_%05d.png')]);
      }
      // Camcorder tape OSD: blinking REC, SP + battery, and the zoom bar
      // exactly as it moved during the take.
      final extras = <String>[];
      if (hasOsd && spec.timestampStyle == TimestampStyle.camcorderOsd) {
        var idx = nextInput + 1;
        for (final o in CamcorderOsd.render(job.workDir, outW, outH, job.zoomTrack)) {
          inputs.addAll(['-loop', '1', '-framerate', profile.fps, '-i', o.path]);
          extras.add(o.overlay(idx++));
        }
      }
      graph = VideoFilters.graph(
        look: look,
        crop: crop,
        outW: outW,
        outH: outH,
        profile: profile,
        hasOsd: hasOsd,
        osdInputIndex: nextInput,
        osdW: osdW,
        osdH: osdH,
        rotateTurns: turns,
        extraOverlays: extras,
      );
    }

    final pass1 = profile.upscale > 1 ? p.join(job.workDir, 'pass1.mp4') : job.outputPath;
    return VideoPlan(
      mainInputArgs: [
        ...inputs,
        '-filter_complex',
        graph,
        '-map',
        '[vout]',
        '-map',
        '0:a?',
        if (profile.audioFilter != null) ...['-af', profile.audioFilter!],
        ...profile.audioArgs,
      ],
      mainOutputArgs: ['-movflags', '+faststart', '-shortest', pass1],
      bitrateKbps: profile.bitrateKbps,
      outW: planW,
      outH: planH,
      upscale: profile.upscale,
      pass1Path: pass1,
    );
  }

  /// 54 frames of dirt looped over the clip: specks (dark dirt and bright
  /// emulsion pinholes), the odd hair, a wandering scratch or two that lasts
  /// a while, and now and then a warm flare creeping in from an edge.
  static void _renderDustFrames(String dir, int w, int h, {required int seed}) {
    final rnd = math.Random(seed);
    const frames = 54;
    final scratches = [
      for (var i = 0; i < 1 + rnd.nextInt(2); i++)
        (start: rnd.nextInt(frames), len: 12 + rnd.nextInt(24), x: rnd.nextDouble() * w),
    ];
    final scratchX = [for (final sc in scratches) sc.x];
    final flare = rnd.nextDouble() < 0.6
        ? (start: rnd.nextInt(frames), len: 6 + rnd.nextInt(10), left: rnd.nextBool(), y: rnd.nextDouble())
        : null;
    final unit = h / 480.0;
    bool inRun(int f, int start, int len) => ((f - start) % frames + frames) % frames < len;
    for (var f = 0; f < frames; f++) {
      final im = img.Image(width: w, height: h, numChannels: 4);
      // specks
      final specks = rnd.nextDouble() < 0.3 ? 0 : 1 + rnd.nextInt(5);
      for (var k = 0; k < specks; k++) {
        final cx = rnd.nextInt(w), cy = rnd.nextInt(h);
        final r = ((0.7 + rnd.nextDouble() * 2.4) * unit).round().clamp(1, 12);
        final light = rnd.nextDouble() < 0.4;
        final c = light ? img.ColorRgba8(240, 236, 222, 170) : img.ColorRgba8(8, 6, 4, 210 + rnd.nextInt(40));
        img.fillCircle(im, x: cx, y: cy, radius: r, color: c, antialias: true);
        if (rnd.nextBool()) {
          img.fillCircle(
            im,
            x: cx + r,
            y: cy + (r ~/ 2),
            radius: math.max(1, r ~/ 2),
            color: c,
            antialias: true,
          );
        }
      }
      // a hair now and then
      if (rnd.nextDouble() < 0.22) {
        var x = rnd.nextDouble() * w, y = rnd.nextDouble() * h;
        var a = rnd.nextDouble() * math.pi * 2;
        final len = (40 + rnd.nextInt(110)) * unit;
        for (var t = 0.0; t < len; t += 1) {
          a += (rnd.nextDouble() - 0.5) * 0.12;
          x += math.cos(a);
          y += math.sin(a);
          if (x < 0 || y < 0 || x >= w || y >= h) break;
          im.setPixelRgba(x.toInt(), y.toInt(), 10, 8, 6, 230);
          if (unit > 1.2) im.setPixelRgba((x + 1).toInt().clamp(0, w - 1), y.toInt(), 10, 8, 6, 150);
        }
      }
      // fine scratches along the film, for a stretch of frames
      for (var i = 0; i < scratches.length; i++) {
        final sc = scratches[i];
        if (!inRun(f, sc.start, sc.len)) continue;
        scratchX[i] = (scratchX[i] + (rnd.nextDouble() - 0.5) * 2).clamp(0, w - 1);
        for (var y = 0; y < h; y++) {
          if (rnd.nextDouble() < 0.85) im.setPixelRgba(scratchX[i].toInt(), y, 235, 235, 225, 110);
        }
      }
      // warm flare from one side (light struck the film end)
      if (flare != null && inRun(f, flare.start, flare.len)) {
        final u = ((f - flare.start) % frames + frames) % frames / flare.len;
        final strength = math.sin(math.pi * u) * 150;
        final cy = flare.y * h, reach = w * 0.35;
        for (var y = 0; y < h; y += 1) {
          final dy = (y - cy) / (h * 0.45);
          for (var x = 0; x < reach; x++) {
            final a = strength * math.exp(-x / (reach * 0.35)) * math.exp(-dy * dy);
            if (a < 2) continue;
            im.setPixelRgba(flare.left ? x : w - 1 - x, y, 255, 120, 40, a.round().clamp(0, 255));
          }
        }
      }
      File(
        p.join(dir, 'dust_${f.toString().padLeft(3, '0')}.png'),
      ).writeAsBytesSync(img.encodePng(im, level: 1));
    }
  }

  /// The film around the frame, for a full-gate scan [w]x[h] (CineStrip
  /// layout): opaque near-black edges and frame lines with the sprocket hole
  /// and its glowing rim, see-through where the frames are (rounded corners).
  static Uint8List _stripPng(int w, int h) {
    final im = img.Image(width: w, height: h, numChannels: 4);
    double smooth(double e0, double e1, double x) {
      final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    }

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final (cov, r, g, b) = CineStripPixel.at((x + 0.5) / w, (y + 0.5) / h, w / h, 1 / h, smooth);
        if (cov <= 0) continue;
        im.setPixelRgba(x, y, r, g, b, (cov * 255).round());
      }
    }
    return img.encodePng(im, level: 1);
  }

  /// Black frame with a soft, rounded opening (the projector gate).
  static Uint8List _gatePng(int w, int h, double strength) {
    final im = img.Image(width: w, height: h, numChannels: 4);
    final r = h * 0.06, inset = h * 0.012, soft = h * 0.03;
    final hx = w / 2 - inset, hy = h / 2 - inset;
    for (var y = 0; y < h; y++) {
      final py = (y + 0.5 - h / 2).abs();
      for (var x = 0; x < w; x++) {
        final px = (x + 0.5 - w / 2).abs();
        final qx = px - hx + r, qy = py - hy + r;
        final d =
            math.sqrt(math.pow(math.max(qx, 0), 2) + math.pow(math.max(qy, 0), 2)) +
            math.min(math.max(qx, qy), 0) -
            r;
        final t = ((d + soft) / (soft + h * 0.004)).clamp(0.0, 1.0);
        final a = (t * t * (3 - 2 * t) * 255 * strength).round();
        if (a > 0) im.setPixelRgba(x, y, 0, 0, 0, a);
      }
    }
    return img.encodePng(im, level: 1);
  }

  static Uint8List _scanlinePng(int w, int h, double strength) {
    final im = img.Image(width: w, height: h, numChannels: 4);
    final a = (strength.clamp(0.0, 1.0) * 255).round();
    for (var y = 1; y < h; y += 2) {
      for (var x = 0; x < w; x++) {
        im.setPixelRgba(x, y, 0, 0, 0, a);
      }
    }
    return img.encodePng(im);
  }

  /// Writes osd_00000.png ... one per second of footage. Returns (w, h).
  static (int, int) _renderOsdFrames({
    required String dir,
    required TimestampStyle style,
    required DateTime start,
    required int frames,
    required int frameHeight,
  }) {
    List<String> textAt(DateTime t) => switch (style) {
      TimestampStyle.ledDate => [TimestampFormat.ledDate(t)],
      TimestampStyle.phone => [TimestampFormat.phone(t)],
      TimestampStyle.camcorderOsd => TimestampFormat.camcorder(t),
      TimestampStyle.none => const <String>[],
    };
    final dot = math.max(1, (frameHeight / (style == TimestampStyle.phone ? 120 : 150)).round());
    final sample = textAt(start);
    final widest = sample.map(PixelFont.measureDots).fold<int>(0, math.max);
    final lineH = (PixelFont.glyphHeight + 3) * dot;
    final w = (widest + 4) * dot, h = sample.length * lineH + dot;
    final isLed = style == TimestampStyle.ledDate;
    final count = isLed ? 1 : frames; // the LED date doesn't change mid-clip
    for (var n = 0; n < count; n++) {
      final lines = textAt(start.add(Duration(seconds: n)));
      final im = img.Image(width: w, height: h, numChannels: 4);
      final data = im.toUint8List();
      for (var k = 0; k < lines.length; k++) {
        final tw = PixelFont.measureDots(lines[k]) * dot;
        PixelFont.drawToBuffer(
          data,
          width: w,
          height: h,
          channels: 4,
          text: lines[k],
          left: w - tw - 2 * dot,
          top: k * lineH,
          dot: dot,
          rgb: isLed ? const [255, 156, 48] : const [240, 240, 240],
          glow: isLed ? const [255, 80, 0] : null,
          shadow: isLed ? null : const [10, 10, 10],
        );
      }
      File(p.join(dir, 'osd_${n.toString().padLeft(5, '0')}.png')).writeAsBytesSync(img.encodePng(im));
    }
    return (w, h);
  }
}

/// One burned-in decal: a PNG and how it is overlaid.
class OsdLayer {
  const OsdLayer(this.path, {required this.x, required this.y, this.enable});

  final String path;

  /// FFmpeg expressions (may use t).
  final String x;
  final String y;

  /// When the decal shows (FFmpeg expression of t); null = always.
  final String? enable;

  String overlay(int input) =>
      '[$input:v]overlay=x=\'$x\':y=\'$y\':eval=frame:shortest=1:format=auto'
      '${enable == null ? '' : ':enable=\'$enable\''}';
}

/// The 90s camcorder's on-screen display, burned into the tape like the
/// found footage it imitates.
class CamcorderOsd {
  const CamcorderOsd._();

  /// How long the zoom bar lingers after the motor stops (matches the
  /// viewfinder).
  static const zoomLinger = 1.5;

  static const _white = [240, 240, 240];
  static const _shadow = [10, 10, 10];

  static List<OsdLayer> render(String dir, int w, int h, List<double> zoomTrack) {
    final dot = math.max(1, (h / 150).round());
    final margin = (h * 0.06).round();
    final layers = <OsdLayer>[];

    // "● REC" top left, blinking once a second.
    final rec = _canvas(PixelFont.measureDots('REC') * dot + 12 * dot, (PixelFont.glyphHeight + 2) * dot);
    final r = (PixelFont.glyphHeight * dot / 2).round();
    img.fillCircle(rec, x: r + dot, y: r + dot, radius: r, color: img.ColorRgba8(10, 10, 10, 255));
    img.fillCircle(rec, x: r, y: r, radius: r, color: img.ColorRgba8(235, 30, 30, 255));
    _text(rec, 'REC', left: 2 * r + 4 * dot, dot: dot);
    layers.add(
      OsdLayer(_save(dir, 'osd_rec.png', rec), x: '$margin', y: '$margin', enable: 'lt(mod(t,1),0.6)'),
    );

    // "SP" and a battery gauge, top right.
    final spW = PixelFont.measureDots('SP') * dot;
    final batW = 14 * dot, batH = PixelFont.glyphHeight * dot;
    final sp = _canvas(spW + 4 * dot + batW + 3 * dot, batH + 2 * dot);
    _text(sp, 'SP', left: 0, dot: dot);
    final bx = spW + 4 * dot;
    for (final (ox, c) in [(dot, _shadow), (0, _white)]) {
      void box(int x, int y, int bw, int bh) => img.fillRect(
        sp,
        x1: x + ox,
        y1: y + ox,
        x2: x + ox + bw - 1,
        y2: y + ox + bh - 1,
        color: img.ColorRgba8(c[0], c[1], c[2], 255),
      );
      box(bx, 0, batW, dot); // outline
      box(bx, batH - dot, batW, dot);
      box(bx, 0, dot, batH);
      box(bx + batW - dot, 0, dot, batH);
      box(bx + batW, batH ~/ 3, dot * 2, batH ~/ 3); // terminal
      for (var k = 0; k < 3; k++) {
        box(bx + 2 * dot + k * 4 * dot, 2 * dot, 3 * dot, batH - 4 * dot); // three bars: full
      }
    }
    layers.add(OsdLayer(_save(dir, 'osd_sp.png', sp), x: '${w - sp.width - margin}', y: '$margin'));

    // Zoom bar: shown while the motor runs (and briefly after).
    final keys = _simplify(zoomTrack);
    final visible = _zoomIntervals(zoomTrack);
    if (keys.length >= 2 && visible.isNotEmpty) {
      final trackW = (w * 0.42).round(), barH = 7 * dot;
      final wDots = PixelFont.measureDots('W') * dot, gap = 3 * dot;
      final bar = _canvas(wDots * 2 + gap * 2 + trackW + dot, barH + dot);
      _text(bar, 'W', left: 0, top: dot, dot: dot);
      _text(bar, 'T', left: wDots + gap * 2 + trackW, top: dot, dot: dot);
      final tx = wDots + gap, mid = barH ~/ 2;
      for (final (o, c) in [(dot, _shadow), (0, _white)]) {
        final col = img.ColorRgba8(c[0], c[1], c[2], 255);
        img.fillRect(
          bar,
          x1: tx + o,
          y1: mid - dot ~/ 2 + o,
          x2: tx + trackW - 1 + o,
          y2: mid + (dot - 1) ~/ 2 + o,
          color: col,
        );
        for (var i = 0; i <= 10; i++) {
          final x = tx + ((trackW - dot) * i / 10).round();
          final th = i == 0 || i == 10 ? barH : (barH * 0.55).round();
          img.fillRect(
            bar,
            x1: x + o,
            y1: mid - th ~/ 2 + o,
            x2: x + dot - 1 + o,
            y2: mid + th ~/ 2 + o,
            color: col,
          );
        }
      }
      final barX = (w - bar.width) ~/ 2, barY = (h * 0.12).round();
      final show = visible.map((v) => 'between(t,${_f(v.$1)},${_f(v.$2)})').join('+');
      layers.add(OsdLayer(_save(dir, 'osd_zbar.png', bar), x: '$barX', y: '$barY', enable: show));

      final mark = _canvas(4 * dot, barH + dot);
      img.fillRect(mark, x1: dot, y1: dot, x2: 4 * dot - 1, y2: barH, color: img.ColorRgba8(10, 10, 10, 255));
      img.fillRect(
        mark,
        x1: 0,
        y1: 0,
        x2: 3 * dot - 1,
        y2: barH - 1,
        color: img.ColorRgba8(240, 240, 240, 255),
      );
      final x0 = barX + tx, span = trackW - 3 * dot;
      layers.add(
        OsdLayer(
          _save(dir, 'osd_zmark.png', mark),
          x: '$x0+$span*(${positionExpr(keys)})',
          y: '$barY',
          enable: show,
        ),
      );
    }
    return layers;
  }

  /// Piecewise-linear position over time as a flat sum (no deep nesting).
  static String positionExpr(List<(double, double)> keys) {
    final terms = <String>[];
    for (var i = 0; i + 1 < keys.length; i++) {
      final (t0, f0) = keys[i];
      final (t1, f1) = keys[i + 1];
      if (t1 <= t0) continue;
      final slope = (f1 - f0) / (t1 - t0);
      terms.add('gte(t,${_f(t0)})*lt(t,${_f(t1)})*(${_f(f0)}+${_f(slope)}*(t-${_f(t0)}))');
    }
    terms.add('gte(t,${_f(keys.last.$1)})*${_f(keys.last.$2)}');
    return terms.join('+');
  }

  /// [ms, f, ...] -> (seconds, f) keyframes, collinear runs merged, at most
  /// ~120 points (Ramer-Douglas-Peucker with a growing tolerance).
  static List<(double, double)> _simplify(List<double> track) {
    final pts = <(double, double)>[
      for (var i = 0; i + 1 < track.length; i += 2) (track[i] / 1000, track[i + 1]),
    ];
    if (pts.length <= 2) return pts;
    var eps = 0.002;
    var out = _rdp(pts, eps);
    while (out.length > 120) {
      eps *= 2;
      out = _rdp(pts, eps);
    }
    return out;
  }

  static List<(double, double)> _rdp(List<(double, double)> pts, double eps) {
    if (pts.length < 3) return pts;
    final (ax, ay) = pts.first;
    final (bx, by) = pts.last;
    var worst = 0.0, at = 0;
    for (var i = 1; i < pts.length - 1; i++) {
      final (x, y) = pts[i];
      // Vertical distance from the chord (time is the x axis).
      final yi = bx == ax ? ay : ay + (by - ay) * (x - ax) / (bx - ax);
      final d = (y - yi).abs();
      if (d > worst) {
        worst = d;
        at = i;
      }
    }
    if (worst <= eps) return [pts.first, pts.last];
    final left = _rdp(pts.sublist(0, at + 1), eps);
    final right = _rdp(pts.sublist(at), eps);
    return [...left.sublist(0, left.length - 1), ...right];
  }

  /// Seconds ranges in which the bar is visible: each burst of zoom samples
  /// (gaps under [zoomLinger] merge) plus the linger after it.
  static List<(double, double)> _zoomIntervals(List<double> track) {
    final times = [for (var i = 2; i + 1 < track.length; i += 2) track[i] / 1000];
    final out = <(double, double)>[];
    for (final t in times) {
      if (out.isNotEmpty && t <= out.last.$2) {
        out[out.length - 1] = (out.last.$1, t + zoomLinger);
      } else {
        out.add((t, t + zoomLinger));
      }
    }
    return out;
  }

  static img.Image _canvas(int w, int h) => img.Image(width: w + 1, height: h + 1, numChannels: 4);

  static void _text(img.Image im, String text, {required int left, int top = 0, required int dot}) {
    PixelFont.drawToBuffer(
      im.toUint8List(),
      width: im.width,
      height: im.height,
      channels: 4,
      text: text,
      left: left,
      top: top,
      dot: dot,
      rgb: _white,
      shadow: _shadow,
    );
  }

  static String _save(String dir, String name, img.Image im) {
    final path = p.join(dir, name);
    File(path).writeAsBytesSync(img.encodePng(im));
    return path;
  }

  static String _f(double v) => v.toStringAsFixed(4);
}
