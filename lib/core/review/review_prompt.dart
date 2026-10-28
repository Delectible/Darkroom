import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../features/camera/application/camera_ui_state.dart' show PrefKeys;
import '../../features/review/rating_sheet.dart';
import '../monetization/pro.dart' show prefsOf;
import '../navigation.dart';

/// Asks for a rating once: after the 5th launch and the 10th developed
/// print, a moment after a print comes out of the developer. Our own sheet
/// first ("Give us a shoutout!"); "Yea!" opens the store's own prompt
/// (Google Play / App Store, no leaving the app).
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
    Timer(const Duration(seconds: 3), () => unawaited(ask()));
  }

  /// Our sheet, then the store's prompt if they say yes. [context] defaults
  /// to the app's navigator.
  static Future<void> ask([BuildContext? context]) async {
    final ctx = context ?? appNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    if (!await showRatingSheet(ctx)) return;
    if (await show() || !ctx.mounted) return;
    // The store said no (not installed from the store, TestFlight, no
    // services): a quiet word so "Yea!" isn't a dud.
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
        content: Text("Thanks! The store couldn't open its rating box right now."),
      ),
    );
  }

  /// Asks the store to show its prompt; false when it can't (it may still
  /// quietly skip it: the store decides). The
  /// store decides: Play only shows it to installs from Play, at most a few
  /// times a year; Apple never shows it in TestFlight builds.
  static Future<bool> show() async {
    try {
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return false;
      await review.requestReview();
      return true;
    } catch (e) {
      debugPrint('Rating prompt unavailable: $e');
      return false;
    }
  }
}

final reviewPromptProvider = Provider<ReviewPrompt>(ReviewPrompt.new);
