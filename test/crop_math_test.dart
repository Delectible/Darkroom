import 'package:flutter_test/flutter_test.dart';
import 'package:darkroom/core/processing/crop_math.dart';

void main() {
  group('CropMath.stillCrop', () {
    test('4:3 still under a 16:9 preview only uses the visible band', () {
      // Portrait still 3000x4000 (4:3), preview 16:9. The preview stream is
      // the wider crop of the sensor: it spans the still's full long edge but
      // only 4000 / (16/9) = 2250 px of its short edge.
      final r = CropMath.stillCrop(
        width: 3000,
        height: 4000,
        previewAspect: 16 / 9,
        ratio: AspectRatioOption.r1x1,
      );
      expect(r.width, 2250);
      expect(r.height, 2250);
      expect(r.x, (3000 - 2250) ~/ 2);
      expect(r.y, (4000 - 2250) ~/ 2);
    });

    test('same aspect as preview => identical to the on-screen mask', () {
      for (final ratio in AspectRatioOption.values) {
        const w = 1080, h = 1920; // portrait still with the preview's 16:9
        final crop = CropMath.stillCrop(width: w, height: h, previewAspect: 16 / 9, ratio: ratio);
        final mask = CropMath.previewMask(previewAspect: 16 / 9, ratio: ratio);
        expect(crop.width / w, closeTo(mask.width, 0.003), reason: ratio.label);
        expect(crop.height / h, closeTo(mask.height, 0.003), reason: ratio.label);
      }
    });

    test('landscape capture keeps the crop landscape', () {
      final r = CropMath.stillCrop(
        width: 4000,
        height: 3000,
        previewAspect: 4 / 3,
        ratio: AspectRatioOption.r16x9,
      );
      expect(r.width > r.height, isTrue);
      expect(r.width / r.height, closeTo(16 / 9, 0.01));
    });

    test('dimensions are even (4:2:0 friendly)', () {
      final r = CropMath.stillCrop(
        width: 3001,
        height: 4003,
        previewAspect: 4 / 3,
        ratio: AspectRatioOption.r3x2,
      );
      expect(r.width.isEven && r.height.isEven, isTrue);
    });
  });

  test('toRawSpace swaps dimensions for rotated EXIF orientations', () {
    const oriented = PixelRect(0, 0, 3000, 2000);
    final raw = CropMath.toRawSpace(oriented: oriented, rawWidth: 4000, rawHeight: 3000, exifOrientation: 6);
    expect(raw.width, 2000);
    expect(raw.height, 3000);
    expect(raw.x, 1000);
    expect(raw.y, 0);
  });

  test('fitLongEdge', () {
    expect(CropMath.fitLongEdge(4000, 3000, 1600), (1600, 1200));
    expect(CropMath.fitLongEdge(800, 600, 1600), (800, 600));
  });
}
