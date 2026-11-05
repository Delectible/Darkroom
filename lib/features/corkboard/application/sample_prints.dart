import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/db/media_repository.dart';
import '../../../core/paths/app_paths.dart';
import '../../camera/application/camera_ui_state.dart';

/// Three sample prints pinned to a new corkboard, so the idea shows on day
/// one: real photos developed through the app's own looks (Golden 200 in
/// the darkroom frame, Portrait 400, an instant print with a note).
///
/// Never saved to the phone's photos: they count as saved already, and the
/// viewer offers no Save or Share on them; the photo library check leaves
/// them alone. Thrown away like any other print. Put up once per install.
class SamplePrints {
  SamplePrints._();

  static const prefix = 'sample-';

  static bool isSample(MediaItem m) => m.id.startsWith(prefix);

  static const _prints = [
    (
      name: 'bridge',
      camera: 'polaroid600',
      file: 'INSTANT_01.JPG',
      w: 826,
      h: 826,
      day: 12,
      note: "Sydney Trip '26",
    ),
    (name: 'autumn', camera: 'portra400', file: 'ROLL000_12.JPG', w: 1000, h: 1500, day: 20, note: null),
    (name: 'sunset', camera: 'gold200', file: 'ROLL000_24.JPG', w: 1500, h: 1000, day: 31, note: null),
  ];

  /// Puts them up, if they never have been on this install.
  static Future<void> seed(MediaRepository repo, AppPaths paths, SharedPreferencesWithCache prefs) async {
    if (prefs.getBool(PrefKeys.samplesSeeded) == true) return;
    // (first: never twice, even if this is cut short)
    await prefs.setBool(PrefKeys.samplesSeeded, true);
    try {
      for (final s in _prints) {
        final out = File('${paths.filmDir.path}/sample_${s.name}.jpg');
        final thumb = File('${paths.thumbsDir.path}/sample_${s.name}.jpg');
        await out.writeAsBytes((await rootBundle.load('assets/samples/${s.name}.jpg')).buffer.asUint8List());
        await thumb.writeAsBytes(
          (await rootBundle.load('assets/samples/${s.name}_thumb.jpg')).buffer.asUint8List(),
        );
        await repo.insertReady(
          id: '$prefix${s.name}',
          cameraId: s.camera,
          fileName: s.file,
          outputPath: out.path,
          thumbPath: thumb.path,
          width: s.w,
          height: s.h,
          capturedAt: DateTime(2026, 10, s.day, 17, 30),
          note: s.note,
        );
      }
      // The sunset shows off a frame (print_frames.dart).
      final frames = prefs.getString(PrefKeys.printFrames);
      final m = frames == null ? <String, dynamic>{} : (jsonDecode(frames) as Map).cast<String, dynamic>();
      m['${prefix}sunset'] = 'darkroom';
      await prefs.setString(PrefKeys.printFrames, jsonEncode(m));
    } catch (_) {
      // (a board without samples is fine)
    }
  }
}
