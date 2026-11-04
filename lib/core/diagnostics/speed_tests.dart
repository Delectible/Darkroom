import 'package:flutter/foundation.dart';

/// Win98 Help > Debug > Speed Tests: switches that each take one costly
/// piece of drawing away (or change how it's done), to measure what it
/// costs on a phone. While one is on, the Performance Report labels the
/// frames with it ("idle camera [no look]"), so one recording compares the
/// two. They reset when the app restarts.
///
/// Measured and dropped (Pixel 9 Pro): the CRT bulge, Darkroom 98's scan
/// lines, glass, colour filter and rounded screen (no change: it redraws at
/// 117 fps), halation (small; off on low RAM anyway); Quick Launch became
/// the normal launch.
class SpeedTests {
  SpeedTests._();

  /// The 3D body's edges smoothed by a cheap filter (FXAA) instead of
  /// multisampling (MSAA). Always so on low-RAM phones.
  static final cheapEdges = ValueNotifier<bool>(false);

  /// The 3D body drawn at 70% of its size (then scaled up).
  static final small3d = ValueNotifier<bool>(false);

  /// The viewfinder without its film / digital look (the plain feed).
  static final noLook = ValueNotifier<bool>(false);

  /// The film grain moves 12 times a second instead of 24 (each move is a
  /// redraw of the viewfinder, on top of the camera's 30).
  static final slowGrain = ValueNotifier<bool>(false);

  /// Swipes show one still of the viewfinder instead of retaking it every
  /// frame to keep it live under the turn.
  static final stillSwipe = ValueNotifier<bool>(false);

  /// Swipes without the hanging strap (its rope is simulated every frame).
  static final noStrap = ValueNotifier<bool>(false);

  /// The switches, by their label in the report.
  static final Map<String, ValueNotifier<bool>> _named = {
    'cheap edges': cheapEdges,
    '3D 70%': small3d,
    'no look': noLook,
    'slow grain': slowGrain,
    'still swipe': stillSwipe,
    'no strap': noStrap,
  };

  /// Every switch.
  static Iterable<ValueNotifier<bool>> get all => _named.values;

  static void allOff() {
    for (final f in all) {
      f.value = false;
    }
  }

  /// [flag]'s label in the report.
  static String nameOf(ValueNotifier<bool> flag) => _named.entries.firstWhere((e) => e.value == flag).key;

  /// Any switch flipped.
  static final Listenable changed = Listenable.merge(_named.values.toList());

  /// For the report's header.
  static String get summary {
    final t = tag.trim();
    return 'Speed tests on: ${t.isEmpty ? 'none' : t.substring(1, t.length - 1)}';
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
