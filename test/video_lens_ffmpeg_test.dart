import 'dart:io';

import 'package:darkroom/core/processing/video_plan.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lgpl_filters.dart';

/// The movie cameras' lenses (VideoLens) in the real graph: LGPL filters
/// only, and the take encodes. Runs through a desktop ffmpeg when one is
/// installed. `SHOTS=dir` keeps a frame of each.
void main() {
  final ffmpeg = Platform.environment['FFMPEG'] ?? 'ffmpeg';
  final available = () {
    try {
      return Process.runSync(ffmpeg, ['-version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }();

  test('every movie camera offers the movie lenses', () {
    for (final c in [...CameraCatalog.film, ...CameraCatalog.digital].where((c) => c.recordsVideo)) {
      expect(c.lenses, containsAll([LensKind.fisheye, LensKind.mist, LensKind.anamorphic]), reason: c.id);
    }
  });

  for (final camera in [CameraCatalog.super8, CameraCatalog.camcorder]) {
    for (final lens in [LensKind.fisheye, LensKind.mist, LensKind.anamorphic]) {
      test(
        '${camera.id} through the ${lens.name} lens',
        () async {
          final dir = await Directory.systemTemp.createTemp('vlens');
          final raw = '${dir.path}/raw.mp4';
          final gen = await Process.run(ffmpeg, [
            '-y', '-f', 'lavfi', '-i', 'testsrc=size=480x640:rate=30', //
            '-f', 'lavfi', '-i', 'sine=frequency=440', '-t', '2', '-shortest', '-pix_fmt', 'yuv420p', raw,
          ]);
          expect(gen.exitCode, 0, reason: gen.stderr.toString());
          final job = VideoJob(
            id: 'take',
            cameraId: camera.id,
            rawPath: raw,
            outputPath: '${dir.path}/out.mp4',
            thumbPath: '${dir.path}/thumb.jpg',
            workDir: '${dir.path}/work',
            aspect: camera.defaultAspect,
            previewAspect: 640 / 480,
            timestamp: false,
            capturedAtMs: 0,
            durationMs: 2000,
            lens: lens,
          );
          final plan = VideoPlanner.prepare(job, probeWidth: 480, probeHeight: 640);
          final graph = plan.mainInputArgs[plan.mainInputArgs.indexOf('-filter_complex') + 1];
          for (final banned in notInMinBuild) {
            expect(graph, isNot(contains('$banned=')), reason: '$banned is not in the LGPL build');
          }
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
          final shots = Platform.environment['SHOTS'];
          if (shots != null) {
            await Process.run(ffmpeg, [
              '-y', '-ss', '1', '-i', plan.pass1Path, '-frames:v', '1', //
              '$shots/vlens_${camera.id}_${lens.name}.png',
            ]);
          }
          await dir.delete(recursive: true);
        },
        skip: available ? false : 'no ffmpeg on this machine',
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  }
}
