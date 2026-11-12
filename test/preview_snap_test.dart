import 'dart:io';
import 'dart:typed_data';

import 'package:darkroom/features/camera/application/preview_snap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The iPhone's preview frame to a photo: BGRA rows with padding at their
/// ends become an upright JPEG of the frame's own size, colours in place.
void main() {
  test('BGRA frame with padded rows to JPEG', () {
    const w = 64, h = 48, stride = 64 * 4 + 32;
    final bgra = Uint8List(stride * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * stride + x * 4;
        // left half red, right half blue (B, G, R, A)
        bgra
          ..[i] = x < w / 2 ? 0 : 255
          ..[i + 1] = 0
          ..[i + 2] = x < w / 2 ? 255 : 0
          ..[i + 3] = 255;
      }
    }
    final dir = Directory.systemTemp.createTempSync('snap');
    final path = '${dir.path}/f.jpg';
    PreviewSnap.writeJpeg(path, bgra, w, h, stride);
    final out = img.decodeJpg(File(path).readAsBytesSync())!;
    expect((out.width, out.height), (w, h));
    final left = out.getPixel(8, 24), right = out.getPixel(56, 24);
    expect(left.r, greaterThan(200));
    expect(left.b, lessThan(60));
    expect(right.b, greaterThan(200));
    expect(right.r, lessThan(60));
  });
}
