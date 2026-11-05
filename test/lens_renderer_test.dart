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

  test('shaders/lens.frag: size, lens, picture; no GLES flip', () {
    final src = File('shaders/lens.frag').readAsStringSync();
    expect(RegExp(r'^uniform vec2 uSize;', multiLine: true).hasMatch(src), isTrue);
    expect(RegExp(r'^uniform float uLens;', multiLine: true).hasMatch(src), isTrue);
    expect(RegExp(r'^uniform sampler2D', multiLine: true).allMatches(src).length, 1);
    expect(src, isNot(contains('IMPELLER_TARGET_OPENGLES')));
    // every lens the app knows has its branch
    for (final l in LensKind.values.skip(1)) {
      expect(src, contains('lens == ${l.index}'), reason: l.name);
    }
  });
}
