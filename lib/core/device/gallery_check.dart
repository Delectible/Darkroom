import 'package:flutter/services.dart';

/// What's still in the app's photo albums (channel `darkroom/gallery`), so a
/// print or file the user deleted from the phone's photos can be offered
/// again. Android lists the app's own album entries without a permission;
/// iOS needs full (or limited) library access, asked for with an
/// explanation first ([GalleryCheck.access] / [GalleryCheck.request]).
class GalleryCheck {
  GalleryCheck._();

  static const _channel = MethodChannel('darkroom/gallery');

  /// Lower-cased file names in [album]; null when the phone won't say (no
  /// access, no channel), in which case nothing should be assumed gone.
  static Future<Set<String>?> names(String album) async {
    try {
      final list = await _channel.invokeListMethod<String>('names', {'album': album});
      return list?.map((n) => n.toLowerCase()).toSet();
    } catch (_) {
      return null;
    }
  }

  /// 'full', 'limited', 'undetermined' or 'denied' (Android: always full).
  static Future<String> access() async {
    try {
      return await _channel.invokeMethod<String>('access') ?? 'denied';
    } catch (_) {
      return 'denied';
    }
  }

  /// Asks for library access (iOS); true when granted.
  static Future<bool> request() async {
    try {
      return await _channel.invokeMethod<bool>('request') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether [saved] (the name the file was saved under) is among [names]:
  /// the photo library may have added a number before the extension when
  /// the name was taken ("ROLL001_07.JPG" -> "ROLL001_071.JPG").
  static bool contains(Set<String> names, String saved) {
    final name = saved.toLowerCase();
    if (names.contains(name)) return true;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    final suffixed = RegExp('^${RegExp.escape(stem)}\\d+${RegExp.escape(ext)}\$');
    return names.any(suffixed.hasMatch);
  }
}
