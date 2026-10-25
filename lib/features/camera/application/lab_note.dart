import 'dart:io';

import 'package:image/image.dart' as img;

import '../../../core/processing/photo_pipeline.dart' show sceneEvOf;
import '../../cameras/domain/camera_spec.dart';

/// "Note from the Lab": after a film shot in light too dim for the stock
/// (no flash), a word on why the print will come back thin and grainy.
class LabNote {
  const LabNote._();

  /// Stops under before the lab says anything.
  static const double threshold = 1.5;

  static String? forShot(CameraSpec spec, double? sceneEv, {required bool flash}) {
    final film = spec.film;
    if (film == null || flash || sceneEv == null || spec.recordsVideo) return null;
    final under = film.process.underFor(sceneEv);
    if (under < threshold) return null;
    final stops = under >= 3.5 ? 'about 4 stops' : 'about ${under.round()} stops';
    return 'Note from the Lab: too dark for ${spec.name} ($stops under). '
        'Try a faster film or the flash.';
  }

  /// Reads the phone's exposure from the capture at [path].
  static Future<String?> forFile(CameraSpec spec, String path, {required bool flash}) async {
    if (spec.film == null || flash) return null;
    try {
      final exif = img.decodeJpgExif(await File(path).readAsBytes());
      return exif == null ? null : forShot(spec, sceneEvOf(exif), flash: flash);
    } on Object {
      return null;
    }
  }
}
