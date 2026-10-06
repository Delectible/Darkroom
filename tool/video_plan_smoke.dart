// Dev-only: runs VideoPlanner's FFmpeg plan with a desktop ffmpeg binary
// (software mpeg4 encoder = the app's always-available fallback path).
//   dart run tool/video_plan_smoke.dart <clip.mp4> <probeW> <probeH>
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:darkroom/core/processing/video_plan.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';

Future<void> main(List<String> args) async {
  final clip = args[0];
  final pw = int.parse(args[1]), ph = int.parse(args[2]);
  final out = Directory.systemTemp.createTempSync('retro_vid');
  for (final spec in CameraCatalog.all.where((c) => c.recordsVideo || Platform.environment['ALL'] == '1')) {
    final job = VideoJob(
      id: spec.id,
      cameraId: spec.id,
      rawPath: clip,
      outputPath: '${out.path}/${spec.id}.mp4',
      thumbPath: '${out.path}/${spec.id}.jpg',
      workDir: '${out.path}/work_${spec.id}',
      aspect: spec.defaultAspect,
      previewAspect: 16 / 9,
      timestamp: true,
      capturedAtMs: DateTime(2026, 10, 5, 14, 32, 7).millisecondsSinceEpoch,
      durationMs: 3000,
      rotationTurns: int.parse(Platform.environment['TURNS'] ?? '0'),
    );
    final plan = VideoPlanner.prepare(job, probeWidth: pw, probeHeight: ph);
    final enc = [
      '-c:v',
      'mpeg4',
      '-b:v',
      '${plan.bitrateKbps}k',
      '-maxrate',
      '${(plan.bitrateKbps * 1.5).round()}k',
      '-bufsize',
      '${plan.bitrateKbps * 2}k',
      '-vtag',
      'mp4v',
    ];
    var r = await Process.run('ffmpeg', [
      '-hide_banner',
      '-loglevel',
      'error',
      ...plan.mainInputArgs,
      ...enc,
      ...plan.mainOutputArgs,
    ]);
    if (r.exitCode == 0 && plan.upscale > 1) {
      r = await Process.run('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        ...plan.upscaleInputArgs(),
        '-c:v',
        'mpeg4',
        '-b:v',
        '1500k',
        '-vtag',
        'mp4v',
        '-movflags',
        '+faststart',
        job.outputPath,
      ]);
    }
    if (r.exitCode != 0) {
      print('FAIL ${spec.id}: ${r.stderr}');
      print('graph: ${plan.mainInputArgs}');
      continue;
    }
    await Process.run('ffmpeg', [
      '-y',
      '-loglevel',
      'error',
      '-ss',
      '1.5',
      '-i',
      job.outputPath,
      '-frames:v',
      '1',
      job.thumbPath,
    ]);
    final probe = await Process.run('ffprobe', [
      '-v',
      'error',
      '-show_entries',
      'stream=codec_name,width,height,r_frame_rate,sample_rate,channels',
      '-of',
      'compact',
      job.outputPath,
    ]);
    print(
      'OK   ${spec.id.padRight(12)} ${plan.finalW}x${plan.finalH}  ${(probe.stdout as String).trim().replaceAll('\n', ' | ')}',
    );
  }
  print(out.path);
}
