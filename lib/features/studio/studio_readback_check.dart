import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'studio_render.dart';

/// Debug > Picture Readback Test: makes pictures the ways the Studio and
/// Photo Room do and reads their pixels back from the GPU, counting how
/// many come back as noise each way (the coloured snow some saves were),
/// and whether a second read after a frame puts it right. Drawn pictures
/// four ways; then [photos] (real files) read straight after decoding and
/// drawn into a picture; then [screen] (what's on screen now) captured as
/// it is and enlarged, as a greeting card is. Tells which step this phone
/// can't be trusted with.
Future<String> studioReadbackReport({
  int each = 20,
  List<String> photos = const [],
  RenderRepaintBoundary? screen,
  double screenRatio = 3,
}) async {
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
  Future<void> count(String name, int times, Future<ui.Image> Function(int i) make) async {
    var bad = 0, cured = 0, none = 0, failed = 0;
    final clock = Stopwatch()..start();
    for (var i = 0; i < times; i++) {
      final ui.Image image;
      try {
        image = await make(i);
      } catch (_) {
        failed++;
        continue;
      }
      final bytes = await rawStudioPixels(image, flat: false);
      if (bytes == null) {
        none++;
      } else if (looksScrambled(bytes, image.width, image.height)) {
        bad++;
        await settleGpu();
        final again = await rawStudioPixels(image, flat: false);
        if (again != null && !looksScrambled(again, image.width, image.height)) cured++;
      }
      image.dispose();
    }
    lines.add(
      '$name: $bad of $times scrambled${bad > 0 ? ' ($cured right on a second read)' : ''}'
      '${none > 0 ? ', $none gave nothing' : ''}${failed > 0 ? ', $failed failed' : ''}, '
      '${clock.elapsedMilliseconds ~/ math.max(1, times)} ms each',
    );
  }

  if (photos.isEmpty) {
    lines.add('photos: none on C: to try');
  } else {
    await count(
      'photo, read at once',
      each,
      (i) => loadStudioImage(photos[i % photos.length], maxSide: 1200),
    );
    await count('photo, drawn, read', each, (i) async {
      final photo = await loadStudioImage(photos[i % photos.length], maxSide: 1200);
      final rec = ui.PictureRecorder();
      final c = Canvas(rec, const Rect.fromLTWH(0, 0, 1080, 1350));
      c.drawRect(const Rect.fromLTWH(0, 0, 1080, 1350), Paint()..color = const Color(0xFFF2EADB));
      drawCover(c, photo, const Rect.fromLTWH(90, 120, 900, 1100));
      final picture = rec.endRecording();
      final image = await picture.toImage(w, h);
      picture.dispose();
      photo.dispose();
      return image;
    });
  }
  if (screen != null && screen.hasSize) {
    await count('screen, as it is', 8, (_) => screen.toImage(pixelRatio: screenRatio));
    final big = 1500 / screen.size.width;
    await count('screen, 1500 across', 8, (_) => screen.toImage(pixelRatio: big));
    await count('screen, 1500, after a frame', 8, (_) async {
      final image = await screen.toImage(pixelRatio: big);
      await settleGpu();
      return image;
    });
  }
  return lines.join('\n');
}
