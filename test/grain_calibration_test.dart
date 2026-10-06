import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkroom/core/processing/film/film_profile.dart';
import 'package:darkroom/core/processing/film/film_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ektar 100 grain, measured the way Gabe's reference scans were: a bright
/// sky patch, seen at the scans' size (1612 px frame height), high-passed.
/// The references measure ~0.0076; weak should be barely there, strong
/// obviously film.
double _skyGrain(GrainStrength g) {
  const w = 300, h = 3000, target = 1612;
  final data = Uint8List(w * h * 3);
  for (var i = 0; i < data.length; i += 3) {
    data[i] = 150;
    data[i + 1] = 205;
    data[i + 2] = 240;
  }
  FilmRenderer(FilmProfile.forStock('ektar100')!, seed: 3, grain: g).render(data, w, h, flash: 0);
  final s = h / target;
  final tw = (w / s).floor();
  final y = Float64List(tw * target);
  for (var ty = 0; ty < target; ty++) {
    for (var tx = 0; tx < tw; tx++) {
      var acc = 0.0, n = 0;
      for (var yy = (ty * s).floor(); yy < ((ty + 1) * s).floor(); yy++) {
        for (var xx = (tx * s).floor(); xx < ((tx + 1) * s).floor(); xx++) {
          final q = (yy * w + xx) * 3;
          acc += 0.2126 * data[q] + 0.7152 * data[q + 1] + 0.0722 * data[q + 2];
          n++;
        }
      }
      y[ty * tw + tx] = acc / n / 255;
    }
  }
  var sum2 = 0.0, cnt = 0;
  for (var ty = 300; ty < target - 300; ty += 2) {
    for (var tx = 20; tx < tw - 20; tx += 2) {
      var m = 0.0;
      for (var dy = -4; dy <= 4; dy++) {
        for (var dx = -4; dx <= 4; dx++) {
          m += y[(ty + dy) * tw + tx + dx];
        }
      }
      final d = y[ty * tw + tx] - m / 81;
      sum2 += d * d;
      cnt++;
    }
  }
  return math.sqrt(sum2 / cnt);
}

void main() {
  test('Ektar grain matches the reference scans at Normal', () {
    final weak = _skyGrain(GrainStrength.weak);
    final normal = _skyGrain(GrainStrength.normal);
    final strong = _skyGrain(GrainStrength.strong);
    expect(normal, inInclusiveRange(0.0060, 0.0100));
    expect(weak, lessThan(normal * 0.5));
    expect(strong, greaterThan(normal * 2));
  });
}
