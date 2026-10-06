import 'dart:io';

import 'package:darkroom/core/processing/instant_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('frame proportions match an integral instant print', () {
    // 88 x 107 mm with a 79 mm square picture.
    expect(InstantFrame.aspect, closeTo(88 / 107, 0.01));
    const s = 1000.0;
    final pic = InstantFrame.pictureRect(s);
    final strip = InstantFrame.noteRect(s);
    expect(pic.width, s);
    expect(strip.top, pic.bottom);
    expect(strip.height, greaterThan(pic.top * 3), reason: 'deep writing strip under the picture');
  });

  testWidgets('export bakes the border (and note) around the picture', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('instant_test');
      final src = File('${dir.path}/pic.jpg');
      // A red square picture, slightly non-square to exercise the centre crop.
      final pic = img.Image(width: 420, height: 400);
      img.fill(pic, color: img.ColorRgb8(220, 30, 30));
      await src.writeAsBytes(img.encodeJpg(pic));

      for (final note in [null, 'summer at the lake, 2026 — with everyone']) {
        final out = await InstantFrame.exportJpeg(
          picturePath: src.path,
          note: note,
          outPath: '${dir.path}/out_${note == null ? 'plain' : 'note'}.jpg',
        );
        final framed = img.decodeJpg(await File(out).readAsBytes())!;
        expect(framed.width, (400 * (1 + 2 * InstantFrame.side)).round());
        expect(framed.height, (400 * (1 + InstantFrame.top + InstantFrame.bottom)).round());
        // Paper at the corner, picture in the middle.
        final corner = framed.getPixel(3, 3);
        // Off-white textured paper, not paper-white.
        expect(corner.r, inInclusiveRange(215, 246));
        expect(corner.b, inInclusiveRange(210, 246));
        final mid = framed.getPixel(framed.width ~/ 2, (InstantFrame.top * 400 + 200).round());
        expect(mid.r, greaterThan(180));
        expect(mid.g, lessThan(80));
      }
      await dir.delete(recursive: true);
    });
  });
}
