import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/processing/photo_pipeline.dart' show sceneEvOf;
import '../../cameras/domain/camera_spec.dart';
import 'camera_ui_state.dart' show PrefKeys;

/// "Note from the Lab": a film shot in light too dim for the stock (no
/// flash) comes back with a word on why it's thin and grainy. Worked out at
/// capture (the phone's exposure), kept until the print is developed, and
/// shown as it comes out: the lab can't know before.
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

  static Map<String, String> _read(SharedPreferencesWithCache prefs) {
    try {
      final raw = prefs.getString(PrefKeys.labNotes);
      return raw == null ? {} : (jsonDecode(raw) as Map).cast<String, String>();
    } on Object {
      return {};
    }
  }

  /// Keeps [note] for the shot [id] until its print is developed.
  static Future<void> keep(SharedPreferencesWithCache prefs, String id, String note) async {
    final all = _read(prefs)..[id] = note;
    await prefs.setString(PrefKeys.labNotes, jsonEncode(all));
  }

  /// The notes for the developed shots in [ids] (each once), oldest first.
  static Future<List<String>> take(SharedPreferencesWithCache prefs, Iterable<String> ids) async {
    final all = _read(prefs);
    final out = <String>[];
    for (final id in ids) {
      final n = all.remove(id);
      if (n != null) out.add(n);
    }
    if (out.isNotEmpty) await prefs.setString(PrefKeys.labNotes, jsonEncode(all));
    return out;
  }
}
