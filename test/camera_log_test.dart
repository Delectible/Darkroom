import 'dart:io';

import 'package:darkroom/features/camera/application/camera_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the camera log is kept for the next launch, newest last, capped', () {
    final dir = Directory.systemTemp.createTempSync('camera_log');
    addTearDown(() => dir.deleteSync(recursive: true));
    CameraLog.init(dir);
    CameraLog.clear();
    CameraLog.add('open back max');
    CameraLog.add('app paused'); // (kept at once)
    expect(File('${dir.path}/camera_log.txt').readAsStringSync(), contains('app paused'));

    // The next launch: last run's lines first, then a marker.
    CameraLog.init(dir);
    final lines = CameraLog.lines;
    expect(lines[0], endsWith('open back max'));
    expect(lines[1], endsWith('app paused'));
    expect(lines[2], startsWith('---------- launch'));

    for (var i = 0; i < 400; i++) {
      CameraLog.add('ready $i');
    }
    expect(CameraLog.lines.length, 150);
    expect(CameraLog.lines.last, endsWith('ready 399'));
    CameraLog.flush();
  });
}
