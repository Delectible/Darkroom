import 'package:darkroom/core/processing/taken_date.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Saved shots carry when they were taken (photo apps sort by it).
void main() {
  test('EXIF date taken survives a JPEG round trip', () {
    final t = DateTime(2026, 10, 30, 14, 5, 9);
    final image = img.Image(width: 8, height: 8);
    TakenDate.stamp(image.exif, t);
    final back = img.decodeJpg(img.encodeJpg(image))!;
    expect(back.exif.exifIfd['DateTimeOriginal']?.toString(), '2026:10:30 14:05:09');
    expect(back.exif.imageIfd['DateTime']?.toString(), '2026:10:30 14:05:09');
  });

  test('video creation time is UTC ISO 8601', () {
    final args = TakenDate.ffmpegArgs(DateTime.utc(2026, 10, 30, 4, 5, 9));
    expect(args, ['-metadata', 'creation_time=2026-10-30T04:05:09.000Z']);
  });
}
