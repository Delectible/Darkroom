import 'dart:io';

import 'package:darkroom/core/processing/crop_math.dart';
import 'package:darkroom/core/processing/photo_pipeline.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A multiple exposure keeps each frame's own lens, and the darkroom's
/// preview of a queued shot has the lens and both exposures in.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('me_lens'));
  tearDown(() => dir.deleteSync(recursive: true));

  String jpg(String name, int v) {
    final i = img.Image(width: 400, height: 300);
    img.fill(i, color: img.ColorRgb8(v, v, v));
    final f = File('${dir.path}/$name')..writeAsBytesSync(img.encodeJpg(i, quality: 95));
    return f.path;
  }

  PhotoJob job({String? first, LensKind firstLens = LensKind.standard, LensKind lens = LensKind.standard}) =>
      PhotoJob(
        id: 'me1',
        cameraId: 'portra400',
        rawPath: jpg('raw.jpg', 120),
        outputPath: '${dir.path}/out.jpg',
        thumbPath: '${dir.path}/thumb.jpg',
        aspect: AspectRatioOption.r4x3,
        previewAspect: 4 / 3,
        flash: FlashSetting.off,
        timestamp: false,
        capturedAtMs: 0,
        lens: lens,
        firstPath: first,
        firstLens: firstLens,
      );

  img.Image preview(PhotoJob j) {
    PhotoPipeline.preview(j);
    return img.decodeJpg(File(PhotoJob.previewPathOf(j.rawPath)).readAsBytesSync())!;
  }

  test('the preview carries the lens: a fish-eye leaves its corners black', () {
    final p = preview(job(lens: LensKind.fisheye));
    expect(p.getPixel(2, 2).r, lessThan(20));
    expect(p.getPixel(p.width ~/ 2, p.height ~/ 2).r, greaterThan(60));
  });

  test('a fish-eye first exposure under a standard second: corners lit by the second only', () {
    final first = jpg('first.jpg', 200);
    final both = preview(job(first: first, firstLens: LensKind.fisheye));
    final plain = preview(job(lens: LensKind.standard));
    final corner = both.getPixel(2, 2).r, centre = both.getPixel(both.width ~/ 2, both.height ~/ 2).r;
    // the corner has only the second exposure; the middle both (brighter)
    expect(corner, greaterThan(40));
    expect(centre, greaterThan(corner + 20));
    expect((corner - plain.getPixel(2, 2).r).abs(), lessThan(40));
  });

  test('the job keeps its first exposure through JSON', () {
    final j = job(first: '/x/first.jpg', firstLens: LensKind.wide);
    final back = PhotoJob.fromJson(j.toJson());
    expect(back.firstPath, '/x/first.jpg');
    expect(back.firstLens, LensKind.wide);
  });
}
