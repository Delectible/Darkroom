import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../providers.dart';

/// How the phone is physically held, from the accelerometer.
///
/// The activity is locked to portrait, so the platform (and the camera
/// plugin's device-orientation stream, which follows the UI) always say
/// "portraitUp". Gravity does not lie: this drives the saved photo's
/// orientation, the rotating icons and the landscape stock picker.
class PhysicalOrientationNotifier extends Notifier<DeviceOrientation> {
  StreamSubscription<AccelerometerEvent>? _sub;

  @override
  DeviceOrientation build() {
    // Only listen while the app is in the foreground (sensor wake-ups cost
    // battery); rebuilding cancels the old subscription.
    if (ref.watch(appLifecycleProvider) != AppLifecycleState.resumed) return DeviceOrientation.portraitUp;
    _sub = accelerometerEventStream(samplingPeriod: SensorInterval.normalInterval).listen(
      _onEvent,
      onError: (Object _) {}, // no accelerometer: stay portrait
      cancelOnError: true,
    );
    ref.onDispose(() => _sub?.cancel());
    return DeviceOrientation.portraitUp;
  }

  /// Being shaken (shake to clear the board): the jolts read as tilts, so
  /// the orientation holds until the phone has been calm for a moment.
  DateTime _calmFrom = DateTime.fromMillisecondsSinceEpoch(0);

  void _onEvent(AccelerometerEvent e) {
    final now = DateTime.now();
    final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if ((g - 9.81).abs() > 4.5) _calmFrom = now.add(const Duration(milliseconds: 700));
    if (now.isBefore(_calmFrom)) return;
    final next = classify(e.x, e.y, e.z, state);
    if (next != state) state = next;
  }

  /// Pure classification with hysteresis (exposed for tests).
  ///
  /// Android/iOS (sensors_plus) report the reaction to gravity: upright
  /// portrait => y ~ +9.8; turned counter-clockwise (top to the left,
  /// Flutter's landscapeLeft) => x ~ +9.8.
  static DeviceOrientation classify(double x, double y, double z, DeviceOrientation current) {
    final g = math.sqrt(x * x + y * y + z * z);
    if (g < 4) return current; // free fall / bogus sample
    if (z.abs() > 0.82 * g) return current; // lying flat: keep what we had
    final angle = math.atan2(x, y) * 180 / math.pi; // 0 = portrait, +90 = CCW
    DeviceOrientation? snap(double centre, DeviceOrientation o) {
      var d = (angle - centre) % 360;
      if (d > 180) d -= 360;
      if (d < -180) d += 360;
      return d.abs() <= 30 ? o : null;
    }

    return snap(0, DeviceOrientation.portraitUp) ??
        snap(90, DeviceOrientation.landscapeLeft) ??
        snap(-90, DeviceOrientation.landscapeRight) ??
        snap(180, DeviceOrientation.portraitDown) ??
        current;
  }
}

final physicalOrientationProvider = NotifierProvider<PhysicalOrientationNotifier, DeviceOrientation>(
  PhysicalOrientationNotifier.new,
);

/// Clockwise quarter turns (RotatedBox) that keep a widget upright for the
/// user in [o].
int uprightQuarterTurns(DeviceOrientation o) => switch (o) {
  DeviceOrientation.portraitUp => 0,
  DeviceOrientation.landscapeLeft => 1,
  DeviceOrientation.portraitDown => 2,
  DeviceOrientation.landscapeRight => 3,
};

bool isLandscape(DeviceOrientation o) =>
    o == DeviceOrientation.landscapeLeft || o == DeviceOrientation.landscapeRight;

/// Same as [uprightQuarterTurns] as AnimatedRotation turns, choosing the
/// short way round so landscape-to-landscape flips don't spin 270 degrees.
double uprightTurns(DeviceOrientation o) => switch (o) {
  DeviceOrientation.portraitUp => 0,
  DeviceOrientation.landscapeLeft => 0.25,
  DeviceOrientation.portraitDown => 0.5,
  DeviceOrientation.landscapeRight => -0.25,
};
