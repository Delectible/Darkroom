import 'dart:io';

import 'package:darkroom/core/processing/cine_strip.dart';
import 'package:darkroom/core/processing/crop_math.dart';
import 'package:darkroom/core/processing/video_plan.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'lgpl_filters.dart';

/// Super 8 reels are full-gate scans: always landscape (even shot upright),
/// the picture inside a film strip with the sprocket hole on the left and
/// slivers of the neighbouring frames. Runs the real graph through a desktop
/// ffmpeg when one is installed. `SHOTS=dir` keeps a frame.
void main() {
  final ffmpeg = Platform.environment['FFMPEG'] ?? 'ffmpeg';
  final available = () {
    try {
      return Process.runSync(ffmpeg, ['-version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }();

  test('upright phone still gives a landscape crop', () {
    final c = CropMath.stillCrop(
      width: 480,
      height: 640,
      previewAspect: 640 / 480,
      ratio: AspectRatioOption.r4x3,
      acrossShortSide: true,
    );
    expect(c.width, greaterThan(c.height));
    expect(c.width / c.height, closeTo(4 / 3, 0.02));
    final m = CropMath.previewMask(
      previewAspect: 640 / 480,
      ratio: AspectRatioOption.r4x3,
      acrossShortSide: true,
    );
    // Same shape in the viewfinder (box is 1 x 4/3).
    expect(m.width / (m.height * 640 / 480), closeTo(4 / 3, 0.01));
  });

  for (final (name, turns) in [('upright', 0), ('sideways', 1)]) {
    test(
      'Super 8 reel ($name): landscape full-gate strip',
      () async {
        final dir = await Directory.systemTemp.createTemp('super8');
        final raw = '${dir.path}/raw.mp4';
        final gen = await Process.run(ffmpeg, [
          '-y', '-f', 'lavfi', '-i', 'testsrc=size=480x640:rate=30', //
          '-f', 'lavfi', '-i', 'sine=frequency=440', '-t', '2', '-shortest', '-pix_fmt', 'yuv420p', raw,
        ]);
        expect(gen.exitCode, 0, reason: gen.stderr.toString());
        final job = VideoJob(
          id: 'reel',
          cameraId: CameraCatalog.super8.id,
          rawPath: raw,
          outputPath: '${dir.path}/out.mp4',
          thumbPath: '${dir.path}/thumb.jpg',
          workDir: '${dir.path}/work',
          aspect: AspectRatioOption.r4x3,
          previewAspect: 640 / 480,
          timestamp: false,
          capturedAtMs: 0,
          durationMs: 2000,
          rotationTurns: turns,
        );
        final plan = VideoPlanner.prepare(job, probeWidth: 480, probeHeight: 640);
        final graph = plan.mainInputArgs[plan.mainInputArgs.indexOf('-filter_complex') + 1];
        for (final banned in notInMinBuild) {
          expect(graph, isNot(contains('$banned=')), reason: '$banned is not in the LGPL build');
        }
        // Landscape canvas with the strip's proportions.
        expect(plan.outW, greaterThan(plan.outH));
        expect(plan.outW / plan.outH, closeTo(CineStrip.canvasAspect(4 / 3), 0.03));

        final run = await Process.run(ffmpeg, [
          ...plan.mainInputArgs,
          '-c:v', 'mpeg4', '-b:v', '1500k', //
          ...plan.mainOutputArgs,
        ]);
        expect(
          run.exitCode,
          0,
          reason: run.stderr.toString().split('\n').reversed.take(25).toList().reversed.join('\n'),
        );
        final png = '${dir.path}/f.png';
        final grab = await Process.run(ffmpeg, [
          '-y',
          '-ss',
          '1',
          '-i',
          plan.pass1Path,
          '-frames:v',
          '1',
          png,
        ]);
        expect(grab.exitCode, 0, reason: grab.stderr.toString());
        final f = img.decodePng(File(png).readAsBytesSync())!;
        expect(f.width, plan.outW);
        // Sprocket hole is black, the film edge left of it near-black, and
        // the picture area is not.
        final hx = ((CineStrip.holeX + CineStrip.holeW / 2) * f.width).round();
        final hole = f.getPixel(hx, f.height ~/ 2);
        expect(hole.r + hole.g + hole.b, lessThan(60));
        final pic = f.getPixel(((CineStrip.picX + CineStrip.picW / 2) * f.width).round(), f.height ~/ 2);
        expect(pic.r + pic.g + pic.b, greaterThan(60));
        final shots = Platform.environment['SHOTS'];
        if (shots != null) File('$shots/super8_$name.png').writeAsBytesSync(File(png).readAsBytesSync());
        await dir.delete(recursive: true);
      },
      skip: available ? false : 'no ffmpeg on this machine',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
