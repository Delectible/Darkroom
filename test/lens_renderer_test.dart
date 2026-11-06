import 'dart:io';
import 'dart:typed_data';

import 'package:darkroom/core/processing/lens_renderer.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Every lens draws into a photo (the sample prints' sunset), keeps its
/// size, and changes it; the shader declares the uniforms the preview sets.
/// SHOTS=dir saves each.
void main() {
  final shots = Platform.environment['SHOTS'];

  test('each lens renders', () {
    final base = img.decodeJpg(File('assets/samples/sunset.jpg').readAsBytesSync())!;
    final small = img.copyResize(base, width: 600);
    final w = small.width, h = small.height;
    final src = small.convert(numChannels: 3).toUint8List();
    for (final lens in LensKind.values) {
      final data = Uint8List.fromList(src);
      final clock = Stopwatch()..start();
      LensRenderer(lens).render(data, w, h);
      expect(data.length, src.length);
      if (lens != LensKind.standard) expect(data, isNot(equals(src)), reason: lens.name);
      expect(clock.elapsed, lessThan(const Duration(seconds: 10)), reason: '${lens.name} too slow');
      if (shots != null) {
        final out = img.Image.fromBytes(width: w, height: h, bytes: data.buffer, numChannels: 3);
        File('$shots/lens_${lens.name}.jpg').writeAsBytesSync(img.encodeJpg(out, quality: 88));
      }
    }
  });

  test('soft focus only where the plastic lens is not; every lens camera starts standard', () {
    for (final c in [...CameraCatalog.film, ...CameraCatalog.digital]) {
      expect(c.lenses.first, LensKind.standard, reason: c.id);
      expect(c.lenses.contains(LensKind.soft) && c.lenses.contains(LensKind.plastic), isFalse, reason: c.id);
    }
  });

  test('fish-eye: a circle on black, the black untouched by the film after', () {
    final base = img.decodeJpg(File('assets/samples/bridge.jpg').readAsBytesSync())!;
    final small = img.copyResize(base, width: 450, height: 300);
    final w = small.width, h = small.height;
    final data = small.convert(numChannels: 3).toUint8List();
    const fish = LensRenderer(LensKind.fisheye);
    fish.render(data, w, h);
    int at(int x, int y) => data[(y * w + x) * 3] + data[(y * w + x) * 3 + 1] + data[(y * w + x) * 3 + 2];
    expect(at(2, 2), 0); // a corner: black
    expect(at(w ~/ 2, h ~/ 2), greaterThan(0)); // the middle: picture
    // the film's grain and fade land everywhere: the finish blacks it out again
    for (var i = 0; i < data.length; i++) {
      data[i] = (data[i] + 18 + (i * 7919) % 23).clamp(0, 255);
    }
    fish.finish(data, w, h);
    expect(at(2, 2), 0);
    expect(at(w - 3, h - 3), 0);
    // the outside stays dark (a faint rainbow at most)
    final i = ((h ~/ 2) * w + (w ~/ 2 + (0.48 * h).round() + 6)) * 3;
    expect(data[i] + data[i + 1] + data[i + 2], lessThan(120));
    if (shots != null) {
      final out = img.Image.fromBytes(width: w, height: h, bytes: data.buffer, numChannels: 3);
      File('$shots/lens_fisheye_finished.jpg').writeAsBytesSync(img.encodeJpg(out, quality: 92));
    }
  });

  test('shaders/lens.frag: size, lens, frame, picture; no GLES flip', () {
    final src = File('shaders/lens.frag').readAsStringSync();
    expect(RegExp(r'^uniform vec2 uSize;', multiLine: true).hasMatch(src), isTrue);
    expect(RegExp(r'^uniform float uLens;', multiLine: true).hasMatch(src), isTrue);
    expect(RegExp(r'^uniform vec4 uCrop;', multiLine: true).hasMatch(src), isTrue);
    // the fish-eye's numbers are the photo's
    for (final (name, v) in [
      ('FISH_FILL', LensRenderer.fishFill),
      ('FISH_FILL_WIDE', LensRenderer.fishFillWide),
      ('FISH_CAP', LensRenderer.fishCap),
      ('FISH_CA', LensRenderer.fishCa),
      ('FISH_BEVEL', LensRenderer.fishBevel),
      ('FISH_JOG', LensRenderer.fishJog),
      ('FISH_RAINBOW', LensRenderer.fishRainbow),
    ]) {
      expect(src, contains('#define $name $v'), reason: name);
    }
    expect(RegExp(r'^uniform sampler2D', multiLine: true).allMatches(src).length, 1);
    expect(src, isNot(contains('IMPELLER_TARGET_OPENGLES')));
    // every lens the app knows has its branch
    for (final l in LensKind.values.skip(1)) {
      expect(src, contains('lens == ${l.index}'), reason: l.name);
    }
    expect(src, isNot(contains('lens == ${LensKind.values.length}')));
  });
}
