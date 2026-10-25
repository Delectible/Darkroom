import 'package:darkroom/core/processing/film/film_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// A slow film runs out of light in the dark long before a fast one.
void main() {
  double under(String id, double ev) => FilmProfile.forStock(id)!.process.underFor(ev);

  test('daylight: every 35 mm film is fine', () {
    for (final id in ['velvia50', 'ektar100', 'portra400', 'cinestill800t']) {
      expect(under(id, 14), 0, reason: id);
    }
  });

  test('a dim street: the slow films fall behind, the fast one copes', () {
    expect(under('ektar100', 4), closeTo(3.9, 0.05));
    expect(under('portra400', 4), closeTo(1.9, 0.05));
    expect(under('cinestill800t', 4), closeTo(0.9, 0.05));
    expect(under('velvia50', 1), 4); // capped: past that it's just black
  });
}
