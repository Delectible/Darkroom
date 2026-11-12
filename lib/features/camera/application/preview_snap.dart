import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../core/processing/capture_processor.dart';
import '../../../core/processing/crop_math.dart';
import '../../cameras/domain/camera_spec.dart';
import 'camera_log.dart';

/// The digital cameras on an iPhone: the photo is the live picture's next
/// frame, taken at once (the phone's photo capture, with its pre-flash when
/// the flash is on, took about 2 s). The flash is the torch for that frame:
/// an iPhone only fires its real flash for its own photo capture.
///
/// Only where the frame holds the camera's whole resolution (the 2008 DSLR
/// keeps the photo capture), and only the back camera (the front's frames
/// are mirrored). The frames come upright like the photo would (the capture
/// is locked to portrait), and are the very picture the viewfinder showed,
/// so the usual crop applies.
class PreviewSnap {
  PreviewSnap._();

  /// How long the torch has to light the scene before the frame is kept.
  static const _torchLead = Duration(milliseconds: 150);

  /// The pixels [ctx]'s camera really records on its long edge.
  static int _needs(CameraSpec spec) => spec.output.lowResLongEdge ?? spec.output.maxLongEdge;

  /// Whether [ctx]'s photo on [c] is taken this way.
  static bool applies(CaptureContext ctx, CameraController c) {
    if (!Platform.isIOS ||
        ctx.spec.mode != AppMode.digital ||
        ctx.spec.recordsVideo ||
        c.description.lensDirection != CameraLensDirection.back) {
      return false;
    }
    final size = c.value.previewSize;
    if (size == null) return false;
    final long = math.max(size.width, size.height), short = math.min(size.width, size.height);
    final (cropLong, _) = CropMath.fitRatio(long, short, ctx.aspect.ratio);
    return cropLong >= _needs(ctx.spec);
  }

  /// The next frame as a JPEG file (null: none came, the caller takes a
  /// photo instead). [torch]: lit by the torch, then the flash back to
  /// [flashAfter].
  static Future<XFile?> take(CameraController c, {required bool torch, required FlashMode flashAfter}) async {
    final got = Completer<CameraImage>();
    var keepFrom = DateTime.now();
    try {
      if (torch) {
        await c.setFlashMode(FlashMode.torch);
        keepFrom = DateTime.now().add(_torchLead);
      }
      await c.startImageStream((frame) {
        if (!got.isCompleted && DateTime.now().isAfter(keepFrom)) got.complete(frame);
      });
      final frame = await got.future.timeout(const Duration(seconds: 1));
      unawaited(c.stopImageStream().catchError((_) {}));
      if (frame.format.group != ImageFormatGroup.bgra8888) {
        CameraLog.add('preview snap: ${frame.format.group.name} frames, photo instead');
        return null;
      }
      final plane = frame.planes.first;
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/snap_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await Isolate.run(() => writeJpeg(path, plane.bytes, frame.width, frame.height, plane.bytesPerRow));
      return XFile(path);
    } catch (e) {
      CameraLog.add('preview snap: $e');
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      return null;
    } finally {
      if (torch) {
        try {
          await c.setFlashMode(FlashMode.off);
          await c.setFlashMode(flashAfter);
        } catch (_) {}
      }
    }
  }

  /// BGRA rows (padded to [stride]) to a JPEG at [path].
  @visibleForTesting
  static void writeJpeg(String path, Uint8List bgra, int w, int h, int stride) {
    final out = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      var i = y * stride;
      for (var x = 0; x < w; x++, i += 4) {
        out.setPixelRgb(x, y, bgra[i + 2], bgra[i + 1], bgra[i]);
      }
    }
    File(path).writeAsBytesSync(img.encodeJpg(out, quality: 95));
  }
}
