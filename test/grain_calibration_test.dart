import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkroom/core/processing/film/film_profile.dart';
import 'package:darkroom/core/processing/film/film_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Film grain, measured the way Gabe's reference scans were: a bright
/// sky patch, seen at the scans' size (1612 px frame height), high-passed.
/// The references measure ~0.0076; weak should be barely there, strong
/// obviously film.
double _skyGrain(
  GrainStrength g, {
  String stock = 'ektar100',
  List<int> rgb = const [150, 205, 240],
  int target = 1612,
}) {
  const w = 300, h = 3000;
  final data = Uint8List(w * h * 3);
  for (var i = 0; i < data.length; i += 3) {
    data[i] = rgb[0];
    data[i + 1] = rgb[1];
    data[i + 2] = rgb[2];
  }
  FilmRenderer(FilmProfile.forStock(stock)!, seed: 3, grain: g).render(data, w, h, flash: 0);
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
  for (var ty = target ~/ 4; ty < target * 3 ~/ 4; ty += 2) {
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

  test('Portra 400 grain matches the reference scans at Normal (Lisbon sky)', () {
    final normal = _skyGrain(
      GrainStrength.normal,
      stock: 'portra400',
      rgb: const [57, 120, 164],
      target: 1353,
    );
    expect(normal, inInclusiveRange(0.027, 0.041)); // scans: ~0.034
  });

  test('HP5 grain matches the scans: heaviest in the highlights', () {
    double at(int v) => _skyGrain(GrainStrength.normal, stock: 'hp5plus400', rgb: [v, v, v], target: 1622);
    final mid = at(95), bright = at(215);
    expect(mid, inInclusiveRange(0.019, 0.031)); // scans: ~0.025 at mid-grey
    expect(bright, inInclusiveRange(0.042, 0.066)); // scans: ~0.047-0.061 in a bright sky
    expect(bright, greaterThan(mid * 1.7));
  });
}
