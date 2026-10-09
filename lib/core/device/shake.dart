import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Calls [onShake] when the phone is given a shake: three sharp jolts within
/// a moment (gravity left out, so tilting or walking doesn't count). Quiet
/// for a couple of seconds after each.
class ShakeDetector {
  ShakeDetector(this.onShake);

  final VoidCallback onShake;

  /// A jolt: at least this much acceleration (m/s², gravity removed).
  static const threshold = 14.0;

  StreamSubscription<UserAccelerometerEvent>? _sub;
  final _jolts = <int>[];
  int _quietUntil = 0;

  void start() {
    _sub ??= userAccelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_on, onError: (Object _) {}, cancelOnError: false);
  }

  void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void _on(UserAccelerometerEvent e) {
    final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (g < threshold) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_jolts.isNotEmpty && now - _jolts.last < 90) return; // the same jolt
    _jolts
      ..add(now)
      ..removeWhere((t) => now - t > 900);
    if (_jolts.length >= 3 && now > _quietUntil) {
      _jolts.clear();
      _quietUntil = now + 2000;
      onShake();
    }
  }
}
