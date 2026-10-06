import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:darkroom/core/processing/crop_math.dart';
import 'package:darkroom/core/processing/isolate_jobs.dart';
import 'package:darkroom/core/processing/photo_pipeline.dart';

/// Mimics CaptureProcessor: an object holding something that can never cross
/// an isolate boundary, calling the isolate helper from an instance method
/// that also creates a closure capturing `this` (the retry callback). Before
/// the fix this exact shape failed with "Illegal argument in isolate message"
/// and every shot was marked ruined.
class _Processor {
  final RawReceivePort unsendable = RawReceivePort();

  Future<PhotoResult> run(PhotoJob job) async {
    try {
      return await renderPhotoInIsolate(job);
    } catch (e) {
      _retryLater(() => run(job));
      rethrow;
    }
  }

  void _retryLater(Future<PhotoResult> Function() retry) {}

  void close() => unsendable.close();
}

void main() {
  test('stills render through the isolate helper from a stateful owner', () async {
    final dir = Directory.systemTemp.createTempSync('retro_iso');
    final src = img.Image(width: 400, height: 300);
    for (final p in src) {
      p
        ..r = p.x % 256
        ..g = p.y % 256
        ..b = 128;
    }
    final raw = File('${dir.path}/raw.jpg')..writeAsBytesSync(img.encodeJpg(src));
    final job = PhotoJob(
      id: 'iso1',
      cameraId: 'portra400',
      rawPath: raw.path,
      outputPath: '${dir.path}/out.jpg',
      thumbPath: '${dir.path}/thumb.jpg',
      aspect: AspectRatioOption.r3x2,
      previewAspect: 4 / 3,
      flash: FlashSetting.off,
      timestamp: false,
      capturedAtMs: 0,
    );
    final processor = _Processor();
    final result = await processor.run(job);
    processor.close();
    expect(result.width > 0 && result.height > 0, isTrue);
    expect(File(job.outputPath).existsSync(), isTrue);
    expect(File(job.thumbPath).existsSync(), isTrue);
    dir.deleteSync(recursive: true);
  });
}
