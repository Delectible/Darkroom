import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/speed_test_run.dart';
import '../../../core/diagnostics/speed_tests.dart';
import '../application/camera_ui_state.dart' show PrefKeys;

/// Whether swipes between the cameras stop the camera's stream and show a
/// still viewfinder until the camera lands ([freeze]).
///
/// On phones whose graphics chip can't draw the live picture and the
/// moving body together (a 3.3 GB tablet: ~30 fps swiping with the stream
/// on, ~84 with it stopped), the still is the smooth choice. Judged from
/// real swipes: each one's frame rate is taken from the frames the app
/// actually produced; after the first swipe (shaders warming), if two of
/// the last three ran under [_slowFps], swipes freeze from then on (saved:
/// the phone won't get faster). Fast phones never trip it: a Pixel 9 Pro
/// swipes at ~55 fps even held to 60 Hz.
class SwipeTuning {
  SwipeTuning._();

  /// Judged slow on this phone (saved).
  static bool auto = false;

  /// Freeze the viewfinder in swipes: judged slow, or Debug's switch on.
  /// (Not during a speed test: it measures the live viewfinder, and its
  /// "freeze vf" step the frozen one.)
  static bool get freeze => SpeedTests.freezeSwipe.value || (auto && !SpeedTestRun.running);

  static const _slowFps = 42.0;

  static SharedPreferencesWithCache? _prefs;

  /// Reads the saved verdict (main.dart, once prefs are open).
  static void load(SharedPreferencesWithCache prefs) {
    _prefs = prefs;
    auto = prefs.getBool(PrefKeys.freezeSwipes) ?? false;
  }

  /// Forgets the verdict (Debug): judged again from the next swipes.
  static void reset() {
    auto = false;
    _swipes = 0;
    _recent.clear();
    _prefs?.remove(PrefKeys.freezeSwipes);
  }

  static bool _listening = false;
  static bool _timing = false;
  static final _stamps = <int>[];
  static int _swipes = 0;
  static final _recent = <double>[];

  /// A swipe began: time its frames.
  static void start() {
    if (!_listening) {
      _listening = true;
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        if (_timing) _stamps.add(SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds);
      });
    }
    _stamps.clear();
    _timing = true;
  }

  /// The swipe ended (landed or settled back): judge it.
  static void end() {
    if (!_timing) return;
    _timing = false;
    // Frozen swipes run fast by design, and a speed test's made-up ones
    // aren't the person's: neither counts.
    if (freeze || SpeedTestRun.running || _stamps.length < 6) return;
    final span = _stamps.last - _stamps.first;
    if (span <= 0) return;
    _judge((_stamps.length - 1) * 1e6 / span);
  }

  @visibleForTesting
  static void judgeForTest(double fps) => _judge(fps);

  static void _judge(double fps) {
    if (++_swipes == 1) return; // (the first warms shaders up)
    _recent.add(fps);
    if (_recent.length > 3) _recent.removeAt(0);
    if (_recent.where((f) => f < _slowFps).length >= 2) {
      auto = true;
      _prefs?.setBool(PrefKeys.freezeSwipes, true);
    }
  }

  /// For reports: "auto (judged slow)", "switch", or "off".
  static String get state => SpeedTests.freezeSwipe.value
      ? 'on (switch)'
      : auto
      ? 'on (this phone judged slow)'
      : 'off';
}
