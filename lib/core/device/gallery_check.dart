import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One file in a photo album: the phone's own id for it (stays the same
/// when the file is renamed elsewhere) and its current name.
typedef GalleryEntry = ({String id, String name});

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

  /// The files in [album] with their ids; null when the phone won't say.
  static Future<List<GalleryEntry>?> entries(String album) async {
    try {
      final list = await _channel.invokeListMethod<Map<Object?, Object?>>('entries', {'album': album});
      return list
          ?.map((e) => (id: e['id']! as String, name: e['name']! as String))
          .where((e) => e.name.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Renames entry [id] to [to] in the photo library (Android 10+, the
  /// app's own entries); false where the phone can't (iOS keeps names).
  static Future<bool> rename(String id, String to) async {
    try {
      return await _channel.invokeMethod<bool>('rename', {'id': id, 'to': to}) ?? false;
    } catch (_) {
      return false;
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

/// Which photo-library entry holds each saved file (media id -> gallery
/// entry id), so a copy renamed in another app is still recognised.
class GalleryLinks {
  GalleryLinks(SharedPreferencesWithCache this._prefs);

  /// Kept in memory only (tests).
  GalleryLinks.memory() : _prefs = null;

  final SharedPreferencesWithCache? _prefs;
  Map<String, String> _mem = {};

  static const key = 'gallery.links';

  Map<String, String> get _map {
    final prefs = _prefs;
    if (prefs == null) return _mem;
    final raw = prefs.getString(key);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } on FormatException {
      return {};
    }
  }

  String? operator [](String mediaId) => _map[mediaId];

  Future<void> set(Map<String, String> links) async {
    if (links.isEmpty) return;
    final all = {..._map, ...links};
    final prefs = _prefs;
    if (prefs == null) {
      _mem = all;
    } else {
      await prefs.setString(key, jsonEncode(all));
    }
  }
}
