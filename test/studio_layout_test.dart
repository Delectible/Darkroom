import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkroom/features/studio/studio_layout.dart';
import 'package:darkroom/features/studio/studio_render.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('book layout: pages hold several pieces, a scrapbook alone, nothing tiny', () {
    BookPiece p(double a, [bool full = false]) => (aspect: a, fullPage: full);
    final pieces = [p(0.3), p(1.0), p(0.38), p(1.4), p(0.8), p(0.75), p(0.75, true), p(0.3), p(1.0)];
    final pages = layBook(pieces);
    for (final pg in pages) {
      // ignore: avoid_print
      print(
        '${pg.pieces} ${pg.rects.map((r) => '(${r.left.toStringAsFixed(2)},${r.top.toStringAsFixed(2)} ${r.width.toStringAsFixed(2)}x${r.height.toStringAsFixed(2)})').join(' ')}',
      );
    }
    expect(pages.first.pieces.length, greaterThanOrEqualTo(3));
    expect(pages.where((pg) => pg.pieces.contains(6)).single.pieces, [6]);
    expect([for (final pg in pages) ...pg.pieces]..sort(), List.generate(pieces.length, (i) => i));
    for (final pg in pages) {
      for (final r in pg.rects) {
        expect(r.left, greaterThanOrEqualTo(-1e-9));
        expect(r.right, lessThanOrEqualTo(1 + 1e-9));
        expect(r.bottom, lessThanOrEqualTo(4 / 3 + 1e-9));
      }
    }
  });

  test('noise read back from the GPU is told from a picture', () {
    const w = 200, h = 160;
    final rnd = math.Random(4);
    final noise = Uint8List.fromList([for (var i = 0; i < w * h * 4; i++) rnd.nextInt(256)]);
    expect(looksScrambled(noise, w, h), isTrue);
    // a picture, grainy: a gradient with +-20 of grain
    final picture = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        for (var c = 0; c < 3; c++) {
          picture[i + c] = (x + y * (c + 1) ~/ 2 + rnd.nextInt(41) - 20).clamp(0, 255);
        }
        picture[i + 3] = 255;
      }
    }
    expect(looksScrambled(picture, w, h), isFalse);
    // half noise (the top of a frame): still caught
    final half = Uint8List.fromList(picture)..setRange(0, w * h * 2, noise);
    expect(looksScrambled(half, w, h), isTrue);
  });
}
