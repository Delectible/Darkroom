import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../features/camera/application/camera_ui_state.dart' show PrefKeys;
import '../monetization/pro.dart' show prefsOf;

/// The store's own rating prompt (Google Play / App Store, no leaving the
/// app), asked once: after the 5th launch and the 10th developed print, a
/// moment after a print comes out of the developer.
class ReviewPrompt {
  ReviewPrompt(this._ref);

  final Ref _ref;

  static const launchesNeeded = 5;
  static const printsNeeded = 10;

  /// Counts this launch (main.dart).
  void launched() {
    final prefs = prefsOf(_ref);
    if (prefs == null) return;
    unawaited(prefs.setInt(PrefKeys.launches, (prefs.getInt(PrefKeys.launches) ?? 0) + 1));
  }

  /// Prints just came out of the developer while the app was open; [total]
  /// is how many developed prints there are now (catches ones developed
  /// while the app was closed).
  void developed(int fresh, {required int total}) {
    final prefs = prefsOf(_ref);
    if (prefs == null) return;
    final before = prefs.getInt(PrefKeys.developed) ?? 0;
    final now = before + fresh > total ? before + fresh : total;
    unawaited(prefs.setInt(PrefKeys.developed, now));
    if (prefs.getBool(PrefKeys.reviewAsked) ?? false) return;
    if ((prefs.getInt(PrefKeys.launches) ?? 0) < launchesNeeded || now < printsNeeded) return;
    unawaited(prefs.setBool(PrefKeys.reviewAsked, true));
    // Let the print-ready moment land first.
    Timer(const Duration(seconds: 3), () => unawaited(show()));
  }

  /// Asks the store to show its prompt (Debug calls this directly). The
  /// store decides: Play only shows it to installs from Play, at most a few
  /// times a year; Apple never shows it in TestFlight builds.
  static Future<void> show() async {
    try {
      final review = InAppReview.instance;
      if (await review.isAvailable()) await review.requestReview();
    } catch (e) {
      debugPrint('Rating prompt unavailable: $e');
    }
  }
}

final reviewPromptProvider = Provider<ReviewPrompt>(ReviewPrompt.new);
