import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Win98 Help > Debug > Speed Tests: switches that each take one costly
/// piece of drawing away (or change how it's done), to measure what it
/// costs on a phone. While one is on, the Performance Report labels the
/// frames with it ("idle camera [no CRT]"), so one recording compares the
/// two. Only Quick Launch is kept across launches (it can't be measured
/// otherwise); the rest reset when the app restarts.
class SpeedTests {
  SpeedTests._();

  /// The 3D body's edges smoothed by a cheap filter (FXAA) instead of
  /// multisampling (MSAA, the library's choice where the GPU has it).
  static final cheapEdges = ValueNotifier<bool>(false);

  /// The 3D body drawn at 70% of its size (then scaled up).
  static final small3d = ValueNotifier<bool>(false);

  /// The viewfinder without its film / digital look (the plain feed).
  static final noLook = ValueNotifier<bool>(false);

  /// The viewfinder without halation (as on low-RAM phones).
  static final noHalation = ValueNotifier<bool>(false);

  /// Darkroom 98 without the CRT bulge (a full-screen filter).
  static final noCrt = ValueNotifier<bool>(false);

  /// The launch curtain lifts as soon as things are in (no fixed holds,
  /// a shorter fade). Saved: it acts on the next launch.
  static final quickLaunch = ValueNotifier<bool>(false);

  /// (also in PrefKeys.all, the prefs allow-list)
  static const quickLaunchKey = 'debug.quickLaunch';
  static SharedPreferencesWithCache? _prefs;

  /// Reads the saved switch (main.dart, once prefs are open).
  static void load(SharedPreferencesWithCache prefs) {
    _prefs = prefs;
    quickLaunch.value = prefs.getBool(quickLaunchKey) ?? false;
  }

  static void setQuickLaunch(bool on) {
    quickLaunch.value = on;
    _prefs?.setBool(quickLaunchKey, on);
  }

  /// The switches that change drawing (frames are labelled with these).
  static final Map<String, ValueNotifier<bool>> _named = {
    'cheap edges': cheapEdges,
    '3D 70%': small3d,
    'no look': noLook,
    'no halation': noHalation,
    'no CRT': noCrt,
  };

  /// Any drawing switch flipped.
  static final Listenable changed = Listenable.merge(_named.values.toList());

  /// For the report's header.
  static String get summary {
    final t = tag.trim();
    return 'Speed tests on: ${t.isEmpty ? 'none' : t.substring(1, t.length - 1)}'
        '${quickLaunch.value ? ' (and quick launch)' : ''}';
  }

  /// The switches that are on, for labels ("" when none).
  static String get tag {
    final on = [
      for (final MapEntry(key: name, value: v) in _named.entries)
        if (v.value) name,
    ];
    return on.isEmpty ? '' : ' [${on.join(', ')}]';
  }
}
