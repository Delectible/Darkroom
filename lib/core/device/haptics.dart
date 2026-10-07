import 'package:flutter/services.dart';

/// HapticFeedback behind Settings > Haptics: the same calls, silent when
/// turned off.
class Haptics {
  const Haptics._();

  static bool enabled = true;

  static Future<void> lightImpact() => enabled ? HapticFeedback.lightImpact() : Future.value();
  static Future<void> mediumImpact() => enabled ? HapticFeedback.mediumImpact() : Future.value();
  static Future<void> heavyImpact() => enabled ? HapticFeedback.heavyImpact() : Future.value();
  static Future<void> selectionClick() => enabled ? HapticFeedback.selectionClick() : Future.value();
  static Future<void> vibrate() => enabled ? HapticFeedback.vibrate() : Future.value();
}
