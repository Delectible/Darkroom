import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'studio_render.dart';

/// Debug > Picture Readback Test: draws pictures off screen and reads their
/// pixels back from the GPU four ways, counting how many come back as
/// noise each way (the coloured snow some saves were), and whether a
/// second read after a frame puts it right. Tells which way this phone can
/// be trusted with.
Future<String> studioReadbackReport({int each = 20}) async {
  const w = 1080, h = 1350;
  ui.Picture draw(int seed) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, const Rect.fromLTWH(0, 0, 1080, 1350));
    final rnd = math.Random(seed);
    c.drawRect(
      const Rect.fromLTWH(0, 0, 1080, 1350),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(1080, 1350), [
          Color.fromARGB(255, rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256)),
          Color.fromARGB(255, rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256)),
        ]),
    );
    for (var i = 0; i < 40; i++) {
      c.drawCircle(
        Offset(rnd.nextDouble() * w, rnd.nextDouble() * h),
        20 + rnd.nextDouble() * 160,
        Paint()..color = Color.fromARGB(160, rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256)),
      );
    }
    return rec.endRecording();
  }

  final lines = <String>['PICTURE READBACK TEST ($w x $h, $each each)'];
  for (final (name, sync, wait, flat) in [
    ('drawn, read at once', false, false, false),
    ('drawn, a frame, read', false, true, false),
    ('drawn in step, read', true, false, false),
    ('drawn, copied, read', false, false, true),
  ]) {
    var bad = 0, cured = 0, none = 0;
    final clock = Stopwatch()..start();
    for (var i = 0; i < each; i++) {
      final picture = draw(i * 31 + name.length);
      final image = sync ? picture.toImageSync(w, h) : await picture.toImage(w, h);
      picture.dispose();
      if (wait) await settleGpu();
      final bytes = await rawStudioPixels(image, flat: flat);
      if (bytes == null) {
        none++;
      } else if (looksScrambled(bytes, w, h)) {
        bad++;
        await settleGpu();
        final again = await rawStudioPixels(image, flat: false);
        if (again != null && !looksScrambled(again, w, h)) cured++;
      }
      image.dispose();
    }
    lines.add(
      '$name: $bad scrambled${bad > 0 ? ' ($cured right on a second read)' : ''}'
      '${none > 0 ? ', $none gave nothing' : ''}, ${clock.elapsedMilliseconds ~/ each} ms each',
    );
  }
  return lines.join('\n');
}
