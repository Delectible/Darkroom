import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../core/providers.dart';
import '../../../../camera/application/camera_ui_state.dart' show PrefKeys;

/// Darkroom 98's high scores (the Games folder's High Scores): each game's
/// best, kept on the phone. Quietly does nothing where there's no app
/// around it (the games' own tests).
class HighScores {
  HighScores._();

  // (the keys live in PrefKeys: the prefs cache only allows its own)
  static const solitaireTime = PrefKeys.hsSolitaireTime;
  static const solitaireWins = PrefKeys.hsSolitaireWins;
  static const minesBeginner = PrefKeys.hsMinesBeginner;
  static const minesIntermediate = PrefKeys.hsMinesIntermediate;
  static const bricks = PrefKeys.hsBricks;
  static const pinball = PrefKeys.hsPinball;
  static const pinballRank = PrefKeys.hsPinballRank;

  static void _safely(void Function() write) {
    try {
      write();
    } catch (_) {
      // (a refused key: no score kept, nothing else hurt)
    }
  }

  static SharedPreferencesWithCache? _prefs(BuildContext context) {
    try {
      return ProviderScope.containerOf(context, listen: false).read(sharedPrefsProvider);
    } catch (_) {
      return null;
    }
  }

  /// Keeps [value] under [key] if it beats the best so far ([lower]: a time,
  /// less is better).
  static void best(BuildContext context, String key, int value, {bool lower = false}) {
    final p = _prefs(context);
    if (p == null || value <= 0) return;
    _safely(() {
      final old = p.getInt(key);
      if (old == null || (lower ? value < old : value > old)) unawaited(p.setInt(key, value));
    });
  }

  /// One more under [key] (wins).
  static void count(BuildContext context, String key) {
    final p = _prefs(context);
    if (p == null) return;
    _safely(() => unawaited(p.setInt(key, (p.getInt(key) ?? 0) + 1)));
  }

  /// Keeps [text] under [key] if [rank] beats the best rank so far.
  static void bestRank(BuildContext context, String key, int rank, String text) {
    final p = _prefs(context);
    if (p == null) return;
    _safely(() {
      if (rank > (p.getInt(PrefKeys.hsPinballRankN) ?? -1)) {
        unawaited(p.setInt(PrefKeys.hsPinballRankN, rank));
        unawaited(p.setString(key, text));
      }
    });
  }

  /// Every game's best, as (game, what, value) lines for the window.
  static List<(String, String, String)> table(BuildContext context) {
    final p = _prefs(context);
    // (a key the cache refuses throws: shown as no score, never a blank window)
    int? i(String k) {
      try {
        return p?.getInt(k);
      } catch (_) {
        return null;
      }
    }

    String? str(String k) {
      try {
        return p?.getString(k);
      } catch (_) {
        return null;
      }
    }

    String time(int? s) => s == null ? '-' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    String n(int? v) => v == null ? '-' : '$v';
    return [
      ('Solitaire', 'Fastest win', time(i(solitaireTime))),
      ('Solitaire', 'Games won', n(i(solitaireWins))),
      ('Minefield', 'Beginner', i(minesBeginner) == null ? '-' : '${i(minesBeginner)} s'),
      ('Minefield', 'Intermediate', i(minesIntermediate) == null ? '-' : '${i(minesIntermediate)} s'),
      ('Bricks', 'High score', n(i(bricks))),
      ('Pinball', 'High score', n(i(pinball))),
      ('Pinball', 'Best rank', str(pinballRank) ?? '-'),
    ];
  }
}
