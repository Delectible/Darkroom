import 'dart:io';

import 'package:darkroom/core/processing/video_filters.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every camera's audio chain (Super 8 sound stripe, camcorder tape...)
/// runs through a desktop ffmpeg, when one is installed, with the same
/// encoder settings the phone uses.
void main() {
  final ffmpeg = Platform.environment['FFMPEG'] ?? 'ffmpeg';
  final available = () {
    try {
      return Process.runSync(ffmpeg, ['-version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }();

  for (final spec in CameraCatalog.all) {
    final profile = VideoProfile.forSpec(spec);
    if (profile.audioFilter == null) continue;
    test('${spec.id} audio chain runs', () async {
      final dir = Directory.systemTemp.createTempSync('audio');
      final out = '${dir.path}/out.m4a';
      final r = await Process.run(ffmpeg, [
        '-loglevel', 'error', '-y', //
        // A burst of NaN up front: a Super 8 take once died with "Input
        // contains (near) NaN" at the AAC encoder.
        '-t', '1', '-f', 'lavfi', //
        '-i', "aevalsrc=exprs='if(lt(t,0.1),0/0,sin(2*PI*330*t))':s=48000,aformat=channel_layouts=stereo",
        '-af', profile.audioFilter!,
        ...profile.audioArgs,
        out,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(File(out).lengthSync(), greaterThan(1000));
      dir.deleteSync(recursive: true);
    }, skip: available ? false : 'no ffmpeg');
  }
}
