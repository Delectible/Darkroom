import 'dart:io';

import 'package:darkroom/core/processing/crop_math.dart';
import 'package:darkroom/core/processing/video_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'lgpl_filters.dart';

/// Runs the Epic 70 (cinema print) filtergraph through a desktop ffmpeg,
/// when one is installed: the real 1.43 frame, a clean print (no gate, no
/// weave), and the reel-change cue marks before the end. `SRC=photo.jpg`
/// films a slow push-in on a photo instead of the test pattern; `SHOTS=dir`
/// keeps a few frames.
void main() {
  final ffmpeg = Platform.environment['FFMPEG'] ?? 'ffmpeg';
  final available = () {
    try {
      return Process.runSync(ffmpeg, ['-version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }();

  test(
    'Epic 70 renders a clean 1.43 print with cue marks before the end',
    () async {
      final dir = await Directory.systemTemp.createTemp('cinema');
      final raw = '${dir.path}/raw.mp4';
      final src = Platform.environment['SRC'];
      final gen = await Process.run(ffmpeg, [
        '-y',
        if (src == null) ...['-f', 'lavfi', '-i', 'testsrc=size=1280x720:rate=30'] else ...['-loop', '1', '-i', src],
        '-f', 'lavfi', '-i', 'sine=frequency=220', '-t', '13', '-shortest', //
        if (src != null) ...['-vf', "scale=2560:-2,zoompan=z='1+0.0006*on':d=1:s=1280x720:fps=30"],
        '-pix_fmt', 'yuv420p', raw,
      ]);
      expect(gen.exitCode, 0, reason: gen.stderr.toString());

      final job = VideoJob(
        id: 'cinema',
        cameraId: 'vision70',
        rawPath: raw,
        outputPath: '${dir.path}/out.mp4',
        thumbPath: '${dir.path}/thumb.jpg',
        workDir: '${dir.path}/work',
        aspect: AspectRatioOption.r143,
        previewAspect: 1280 / 720,
        timestamp: false,
        capturedAtMs: 0,
        durationMs: 13000,
      );
      final plan = VideoPlanner.prepare(job, probeWidth: 1280, probeHeight: 720);
      final graph = plan.mainInputArgs[plan.mainInputArgs.indexOf('-filter_complex') + 1];
      for (final banned in notInMinBuild) {
        expect(graph, isNot(contains('$banned=')), reason: '$banned is not in the LGPL build');
      }
      expect(plan.outW / plan.outH, closeTo(1.43, 0.02));

      final out = '${dir.path}/out.mp4';
      final run = await Process.run(ffmpeg, [
        ...plan.mainInputArgs,
        '-c:v', 'mpeg4', '-q:v', '3', //
        ...plan.mainOutputArgs,
      ]);
      expect(
        run.exitCode,
        0,
        reason: run.stderr.toString().split('\n').reversed.take(25).toList().reversed.join('\n'),
      );

      Future<img.Image> frameAt(double t, String name) async {
        final png = '${dir.path}/$name.png';
        final r = await Process.run(ffmpeg, ['-y', '-ss', '$t', '-i', out, '-frames:v', '1', png]);
        expect(r.exitCode, 0, reason: r.stderr.toString());
        final shots = Platform.environment['SHOTS'];
        if (shots != null) File(png).copySync('$shots/epic70_$name.png');
        return img.decodePng(File(png).readAsBytesSync())!;
      }

      // The changeover cue sits top right for four frames, 1 s before the end.
      double cueLuma(img.Image im) {
        final s = im.height < im.width ? im.height : im.width;
        final p = im.getPixel((im.width - s * 0.11).round(), (s * 0.11).round());
        return p.luminanceNormalized.toDouble();
      }

      final plain = await frameAt(2, 'mid');
      final cue = await frameAt(12.05, 'cue');
      expect(cueLuma(cue), greaterThan(0.75));
      expect(cueLuma(cue) - cueLuma(plain), greaterThan(0.1));
      await dir.delete(recursive: true);
    },
    skip: available ? false : 'no desktop ffmpeg',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
