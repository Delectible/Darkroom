// Dev-only smoke test for the CPU still pipeline (pure Dart, runs on the VM):
//   dart run tool/pipeline_smoke.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:darkroom/core/processing/crop_math.dart';
import 'package:darkroom/core/processing/photo_pipeline.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';

void main() {
  final dir = Directory.systemTemp.createTempSync('retro_smoke');
  // Synthetic 4000x3000 "sensor" frame stored landscape with EXIF orientation 6
  // (phone held portrait), like Android/iOS write it.
  const w = 4000, h = 3000;
  final src = img.Image(width: w, height: h);
  for (final p in src) {
    final x = p.x / w, y = p.y / h;
    p
      ..r = (255 * x).round()
      ..g = (255 * y).round()
      ..b = (128 + 127 * math.sin(x * 20)).round();
  }
  img.fillCircle(src, x: w ~/ 2, y: h ~/ 2, radius: 400, color: img.ColorRgb8(255, 255, 255));
  src.exif.imageIfd.orientation = 6;
  final rawBytes = img.encodeJpg(src, quality: 90);

  for (final spec in CameraCatalog.all) {
    for (final aspect in spec.aspects.take(2)) {
      final raw = File('${dir.path}/raw_${spec.id}.jpg')..writeAsBytesSync(rawBytes);
      final job = PhotoJob(
        id: '${spec.id}-${aspect.name}',
        cameraId: spec.id,
        rawPath: raw.path,
        outputPath: '${dir.path}/${spec.id}_${aspect.name}.jpg',
        thumbPath: '${dir.path}/${spec.id}_${aspect.name}_thumb.jpg',
        aspect: aspect,
        previewAspect: 16 / 9,
        flash: FlashSetting.auto,
        timestamp: true,
        capturedAtMs: DateTime(2026, 10, 5, 14, 32, 7).millisecondsSinceEpoch,
        rotationTurns: int.parse(Platform.environment['TURNS'] ?? '0'),
        originalCopyPath: spec.id == 'ektar100' ? '${dir.path}/orig.jpg' : null,
      );
      final sw = Stopwatch()..start();
      final r = PhotoPipeline.run(job);
      sw.stop();
      final out = img.decodeJpg(File(job.outputPath).readAsBytesSync())!;
      final expect = CropMath.stillCrop(width: 3000, height: 4000, previewAspect: 16 / 9, ratio: aspect);
      print(
        '${spec.id.padRight(12)} ${aspect.label.padRight(5)} -> ${r.width}x${r.height} '
        '(${(r.bytes / 1024).round()} KB, ${sw.elapsedMilliseconds} ms) '
        'portrait=${out.height > out.width} crop=${expect.width}x${expect.height} '
        'ratio=${(math.max(out.width, out.height) / math.min(out.width, out.height)).toStringAsFixed(3)} '
        'flash=${r.flashFired}',
      );
    }
  }
  print('outputs in ${dir.path}');
}
