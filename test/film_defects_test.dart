import 'dart:typed_data';

import 'package:darkroom/core/processing/film/film_defects.dart';
import 'package:flutter_test/flutter_test.dart';

/// Defects are the odd flaw on some frames, never a filter on every frame.
void main() {
  const w = 400, h = 300;
  Uint8List frame() => Uint8List(w * h * 3)..fillRange(0, w * h * 3, 110);

  test('same frame, same flaws; clean stocks stay clean', () {
    final a = frame(), b = frame();
    FilmDefects(amount: 1, negative: true, seed: 7).apply(a, w, h);
    FilmDefects(amount: 1, negative: true, seed: 7).apply(b, w, h);
    expect(a, b);
    final c = frame();
    FilmDefects(amount: 0, negative: true, seed: 7).apply(c, w, h);
    expect(c, frame());
  });

  test('a roll has variety and the flaws stay small', () {
    var clean = 0, leaks = 0;
    final kinds = <String>{};
    for (var seed = 0; seed < 300; seed++) {
      final f = frame();
      final d = FilmDefects(amount: 1, negative: true, seed: seed)..apply(f, w, h);
      if (d.applied.isEmpty) clean++;
      if (d.applied.contains('light leak')) {
        leaks++;
        continue;
      }
      kinds.addAll(d.applied.map((k) => k.split(' ').first));
      var changed = 0;
      for (var i = 0; i < f.length; i++) {
        if (f[i] != 110) changed++;
      }
      expect(changed / f.length, lessThan(0.03), reason: 'seed $seed: ${d.applied}');
    }
    expect(clean, inInclusiveRange(30, 120)); // some frames are spotless
    expect(leaks, lessThan(40)); // leaks are rare
    expect(kinds, containsAll(['dust', 'hair', 'scratch']));
  });
}
