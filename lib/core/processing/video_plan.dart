import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../features/cameras/domain/camera_catalog.dart';
import '../../features/cameras/domain/camera_spec.dart';
import '../utils/pixel_font.dart';
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

    final crop = CropMath.stillCrop(
      width: probeWidth,
      height: probeHeight,
      previewAspect: job.previewAspect,
      ratio: job.aspect,
    );
    final turns = (probeHeight > probeWidth) ? job.rotationTurns % 4 : 0;
    final (cw, ch) = VideoFilters.outputSize(crop, profile);
    final (outW, outH) = turns.isOdd ? (ch, cw) : (cw, ch);

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
      File(p.join(job.workDir, 'gate.png')).writeAsBytesSync(_gatePng(outW, outH, film.gate));
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
      outW: outW,
      outH: outH,
      upscale: profile.upscale,
      pass1Path: pass1,
    );
  }

  /// 36 frames of dust specks, the odd hair and a wandering scratch, looped
  /// over the clip (dark marks: dirt on reversal film projects black).
  static void _renderDustFrames(String dir, int w, int h, {required int seed}) {
    final rnd = math.Random(seed);
    const frames = 36;
    final scratchStart = rnd.nextInt(frames), scratchLen = 8 + rnd.nextInt(10);
    var scratchX = rnd.nextDouble() * w;
    final unit = h / 480.0;
    for (var f = 0; f < frames; f++) {
      final im = img.Image(width: w, height: h, numChannels: 4);
      // specks
      final specks = rnd.nextDouble() < 0.45 ? 0 : 1 + rnd.nextInt(3);
      for (var k = 0; k < specks; k++) {
        final cx = rnd.nextInt(w), cy = rnd.nextInt(h);
        final r = ((0.8 + rnd.nextDouble() * 2.6) * unit).round().clamp(1, 12);
        img.fillCircle(
          im,
          x: cx,
          y: cy,
          radius: r,
          color: img.ColorRgba8(8, 6, 4, 210 + rnd.nextInt(40)),
          antialias: true,
        );
        if (rnd.nextBool()) {
          img.fillCircle(
            im,
            x: cx + r,
            y: cy + (r ~/ 2),
            radius: math.max(1, r ~/ 2),
            color: img.ColorRgba8(8, 6, 4, 200),
            antialias: true,
          );
        }
      }
      // a hair now and then
      if (rnd.nextDouble() < 0.14) {
        var x = rnd.nextDouble() * w, y = rnd.nextDouble() * h;
        var a = rnd.nextDouble() * math.pi * 2;
        final len = (40 + rnd.nextInt(90)) * unit;
        for (var t = 0.0; t < len; t += 1) {
          a += (rnd.nextDouble() - 0.5) * 0.12;
          x += math.cos(a);
          y += math.sin(a);
          if (x < 0 || y < 0 || x >= w || y >= h) break;
          im.setPixelRgba(x.toInt(), y.toInt(), 10, 8, 6, 230);
          if (unit > 1.2) im.setPixelRgba((x + 1).toInt().clamp(0, w - 1), y.toInt(), 10, 8, 6, 150);
        }
      }
      // a fine vertical scratch for a few frames
      final inScratch = (f - scratchStart) % frames < scratchLen && (f - scratchStart) % frames >= 0;
      if (inScratch) {
        scratchX = (scratchX + (rnd.nextDouble() - 0.5) * 2).clamp(0, w - 1);
        for (var y = 0; y < h; y++) {
          if (rnd.nextDouble() < 0.85) im.setPixelRgba(scratchX.toInt(), y, 235, 235, 225, 110);
        }
      }
      File(
        p.join(dir, 'dust_${f.toString().padLeft(3, '0')}.png'),
      ).writeAsBytesSync(img.encodePng(im, level: 1));
    }
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
