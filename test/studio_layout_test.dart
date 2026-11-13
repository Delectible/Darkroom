import 'package:darkroom/features/studio/studio_layout.dart';
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
}
