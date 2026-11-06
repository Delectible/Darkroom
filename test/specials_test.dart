import 'dart:typed_data';

import 'package:darkroom/core/processing/specials.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every camera has a special; the movie cameras slow motion', () {
    for (final c in [...CameraCatalog.film, ...CameraCatalog.digital]) {
      expect(c.special, isNotNull, reason: c.id);
      if (c.recordsVideo) expect(c.special, CameraSpecial.slow, reason: c.id);
    }
  });

  test('a light leak warms one side of the frame, differently each frame', () {
    Uint8List grey() => Uint8List(120 * 80 * 3)..fillRange(0, 120 * 80 * 3, 90);
    final a = grey(), b = grey();
    Specials.lightLeak(a, 120, 80, seed: 1);
    Specials.lightLeak(b, 120, 80, seed: 2);
    expect(a, isNot(equals(grey())));
    expect(a, isNot(equals(b)));
    // warm: red gains most
    var r = 0, bl = 0;
    for (var i = 0; i < a.length; i += 3) {
      r += a[i] - 90;
      bl += a[i + 2] - 90;
    }
    expect(r, greaterThan(bl));
  });

  test('colour modes: B&W is grey, sepia warm', () {
    final px = Uint8List.fromList([200, 80, 40]);
    Specials.colorFx(px, ColorFx.mono);
    expect(px[0], px[1]);
    expect(px[1], px[2]);
    final s = Uint8List.fromList([200, 80, 40]);
    Specials.colorFx(s, ColorFx.sepia);
    expect(s[0], greaterThan(s[1]));
    expect(s[1], greaterThan(s[2]));
  });

  test('slow motion: the sound stretched to match, after the camera sound', () {
    expect(Specials.slowFactor, 2);
    expect(Specials.slowAudio(null), 'atempo=0.5');
    expect(Specials.slowAudio('highpass=f=150'), 'highpass=f=150,atempo=0.5');
  });
}
