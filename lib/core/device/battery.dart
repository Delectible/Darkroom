import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The phone's battery, for the digital bodies' gauges (the LCD panel and
/// the camcorder's burned-in OSD). Native: MainActivity / AppDelegate,
/// channel `darkroom/battery`.
class Battery {
  const Battery._();

  static const _channel = MethodChannel('darkroom/battery');

  /// Charge in percent, or null when it can't be read (tests, simulators).
  static Future<int?> level() async {
    try {
      final v = await _channel.invokeMethod<int>('level');
      return v == null || v < 0 ? null : v.clamp(0, 100);
    } catch (_) {
      return null;
    }
  }

  /// The three-segment gauge: full when unknown.
  static int bars(int? level) => switch (level) {
    null => 3,
    > 66 => 3,
    > 33 => 2,
    > 10 => 1,
    _ => 0,
  };
}

/// Battery percent, re-read every minute while something shows it.
final batteryLevelProvider = StreamProvider.autoDispose<int?>((ref) async* {
  yield await Battery.level();
  yield* Stream<void>.periodic(const Duration(minutes: 1)).asyncMap((_) => Battery.level());
});
