import 'dart:io';

import 'package:darkroom/core/processing/crop_math.dart';
import 'package:darkroom/core/processing/video_plan.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'lgpl_filters.dart';

/// Runs the real camcorder filtergraph (tape OSD, REC, battery and the
/// zoom bar) through a desktop ffmpeg, when one is installed. The phone uses
/// FFmpegKit's LGPL build; the deny-list test guards the filter choice, this
/// one guards the graph syntax and the zoom-bar expressions.
void main() {
  final ffmpeg = Platform.environment['FFMPEG'] ?? 'ffmpeg';
  final available = () {
    try {
      return Process.runSync(ffmpeg, ['-version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }();

  test('zoom position expression is piecewise linear', () {
    final e = CamcorderOsd.positionExpr([(0, 0), (1, 0), (2, 0.5), (3, 0.5)]);
    expect(e, contains('gte(t,1.0000)*lt(t,2.0000)*(0.0000+0.5000*(t-1.0000))'));
    expect(e.split('+gte').length, 4);
  });

  test(
    'camcorder take renders with tape OSD and zoom bar',
    () async {
      final dir = await Directory.systemTemp.createTemp('camcorder_osd');
      final raw = '${dir.path}/raw.mp4';
      // A 4 s portrait phone clip with sound.
      final gen = await Process.run(ffmpeg, [
        '-y', '-f', 'lavfi', '-i', 'testsrc=size=480x640:rate=30', //
        '-f', 'lavfi', '-i', 'sine=frequency=440', '-t', '4', '-shortest', '-pix_fmt', 'yuv420p', raw,
      ]);
      expect(gen.exitCode, 0, reason: gen.stderr.toString());

      final job = VideoJob(
        id: 'test',
        cameraId: CameraCatalog.camcorder.id,
        rawPath: raw,
        outputPath: '${dir.path}/out.mp4',
        thumbPath: '${dir.path}/thumb.jpg',
        workDir: '${dir.path}/work',
        aspect: AspectRatioOption.r4x3,
        previewAspect: 640 / 480,
        timestamp: true,
        capturedAtMs: DateTime(2026, 10, 6, 21, 30).millisecondsSinceEpoch,
        durationMs: 4000,
        // Wide, zoom in from 0.5 s to 1.7 s, hold, back out a little at 2.5 s.
        zoomTrack: [0, 0, 500, 0, 1100, 0.5, 1700, 1, 2500, 1, 2900, 0.7],
      );
      final plan = VideoPlanner.prepare(job, probeWidth: 480, probeHeight: 640);
      final graph = plan.mainInputArgs[plan.mainInputArgs.indexOf('-filter_complex') + 1];
      for (final banned in notInMinBuild) {
        expect(graph, isNot(contains('$banned=')), reason: '$banned is not in the LGPL build');
      }
      for (final png in ['osd_rec.png', 'osd_sp.png', 'osd_zbar.png', 'osd_zmark.png']) {
        expect(File('${job.workDir}/$png').existsSync(), isTrue, reason: png);
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

      // Zoom bar is up mid-zoom (1.2 s) and gone well after it (2.0 s is
      // inside the linger, 4 s of footage ends before the second linger ends,
      // so sample the gap-free frame at 0.2 s instead).
      Future<img.Image> frameAt(String t) async {
        final out = '${dir.path}/f_$t.png';
        final r = await Process.run(ffmpeg, ['-y', '-ss', t, '-i', plan.pass1Path, '-frames:v', '1', out]);
        expect(r.exitCode, 0);
        return img.decodePng(await File(out).readAsBytes())!;
      }

      double whiteness(img.Image f) {
        // Bright pixels in the band where the bar sits (12% down, centred).
        final y0 = (f.height * 0.12).round(), y1 = (f.height * 0.17).round();
        var n = 0;
        for (var y = y0; y < y1; y++) {
          for (var x = (f.width * 0.25).round(); x < (f.width * 0.75).round(); x++) {
            final p = f.getPixel(x, y);
            if (p.r > 225 && p.g > 225 && p.b > 225) n++;
          }
        }
        return n / ((y1 - y0) * f.width * 0.5);
      }

      final before = whiteness(await frameAt('0.2'));
      final during = whiteness(await frameAt('1.2'));
      expect(during, greaterThan(before + 0.01), reason: 'zoom bar burned in while zooming');
      // OSD_KEEP=1 keeps the clip and frames for a look.
      if (Platform.environment['OSD_KEEP'] == null) await dir.delete(recursive: true);
    },
    skip: available ? false : 'ffmpeg not installed',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
