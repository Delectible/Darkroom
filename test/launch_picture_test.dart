import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/app_info.dart';
import 'package:darkroom/features/camera/presentation/launch_picture.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a saved picture loads, matches only the same camera and box, and hands over', (tester) async {
    final dir = Directory.systemTemp.createTempSync('launch_picture');
    addTearDown(() => dir.deleteSync(recursive: true));
    final want = LaunchPicture.wantOf(
      mode: AppMode.film,
      skin: 'classic',
      camera: 'film_classic',
      video: false,
    );
    await tester.runAsync(() async {
      // a 40 x 60 picture, as the camera screen would save it
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 40, 60), Paint()..color = const Color(0xFF884422));
      final image = await rec.endRecording().toImage(40, 60);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${dir.path}/launch_body.png').writeAsBytesSync(png!.buffer.asUint8List());
      File(
        '${dir.path}/launch_body.json',
      ).writeAsStringSync(jsonEncode({...want, 'poses': 'shutter:0,0,0,'}));
      LaunchPicture.init(dir);
      await LaunchPicture.loaded;
    });
    expect(want['version'], AppInfo.version);
    expect(LaunchPicture.candidate(want), isTrue);
    expect(LaunchPicture.candidate({...want, 'skin': 'black'}), isFalse);
    LaunchPicture.want = want;
    expect(LaunchPicture.covers(AppMode.film), isTrue);
    expect(LaunchPicture.covers(AppMode.digital), isFalse);
    // only exactly the body's box
    expect(LaunchPicture.forBox(AppMode.film, const Size(80, 120)), isNull);
    expect(LaunchPicture.shown, isFalse);
    expect(LaunchPicture.forBox(AppMode.film, const Size(40, 60)), isNotNull);
    expect(LaunchPicture.shown, isTrue);
    // the launch lifts on it only with the body's parts where they were
    expect(LaunchPicture.liftOn('shutter:0,0,0,'), isTrue);
    expect(LaunchPicture.liftOn('shutter:0,0,0,down'), isFalse);
    expect(LaunchPicture.liftOn(''), isFalse);
    LaunchPicture.done();
    expect(LaunchPicture.shown, isFalse);
    expect(LaunchPicture.covers(AppMode.film), isFalse);
  });
}
