import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'perf_recorder.dart';
import 'speed_tests.dart';

/// Debug > Speed Tests > Run Speed Tests: works through every switch on its
/// own, the same way each time, with the phone left alone: the camera at
/// rest, swipes between the cameras (real touches, made up by the app),
/// then Darkroom 98 kept busy. Every frame is labelled "test N: (switch)"
/// so the Performance Report compares each one to the baseline.
class SpeedTestRun {
  SpeedTestRun._();

  /// What's running ("Speed test 3 of 12: ..."), null when idle. Shown as a
  /// banner over the app (app.dart); tapping it stops the run.
  static final status = ValueNotifier<String?>(null);

  /// Darkroom 98 redraws its screen every frame while true (a speck in a
  /// corner, as any change inside the screen redraws all of it).
  static final pulse = ValueNotifier<bool>(false);

  /// Set by the camera screen: which way (+1 right, -1 left) a swipe tosses
  /// the camera in hand to the other one.
  static int Function()? tossDirection;

  /// Set by the camera screen: slides Darkroom 98 in (completes once it's up).
  static Future<void> Function()? openExplorer;

  static bool _stop = false;
  static void stop() => _stop = true;

  static bool get running => status.value != null;

  /// One test: a name and its switch (null = baseline, everything normal).
  static const _camera = 'camera';
  static const _win98 = 'win98';

  static List<(String, String, ValueNotifier<bool>?)> get _plan => [
    (_camera, 'baseline', null),
    (_camera, 'no look', SpeedTests.noLook),
    (_camera, 'slow grain', SpeedTests.slowGrain),
    (_camera, 'still swipe', SpeedTests.stillSwipe),
    (_camera, 'no strap', SpeedTests.noStrap),
    (_camera, 'cheap edges', SpeedTests.cheapEdges),
    (_camera, '3D 70%', SpeedTests.small3d),
    (_win98, 'baseline', null),
    (_win98, 'no lines', SpeedTests.noLines),
    (_win98, 'no glass', SpeedTests.noGlass),
    (_win98, 'no tint', SpeedTests.noTint),
    (_win98, 'square', SpeedTests.squareScreen),
  ];

  /// About how long a run takes, for the confirmation.
  static const minutes = 3;

  /// Runs the plan from the camera screen ([navigator] is popped to it
  /// first); the recorder starts empty, so the report holds only the run.
  /// Calls [done] at the end (or when stopped).
  static Future<void> run(NavigatorState navigator, {required VoidCallback done}) async {
    if (running) return;
    _stop = false;
    final plan = _plan;
    for (final (_, _, flag) in plan) {
      flag?.value = false;
    }
    navigator.popUntil((r) => r.isFirst);
    await _wait(const Duration(milliseconds: 1500));
    PerfRecorder.clear();
    var inWin98 = false;
    try {
      for (var i = 0; i < plan.length && !_stop; i++) {
        final (where, name, flag) = plan[i];
        status.value = 'Speed test ${i + 1} of ${plan.length}: $where, $name';
        if (where == _win98 && !inWin98) {
          PerfRecorder.test = null;
          await openExplorer?.call();
          await _wait(const Duration(milliseconds: 1500));
          inWin98 = true;
        }
        flag?.value = true;
        await _wait(const Duration(milliseconds: 600)); // (settle the switch)
        PerfRecorder.test = 'test ${i + 1}: $where $name';
        if (where == _camera) {
          await _cameraRound();
        } else {
          await _win98Round();
        }
        PerfRecorder.test = null;
        flag?.value = false;
      }
    } finally {
      PerfRecorder.test = null;
      pulse.value = false;
      for (final (_, _, flag) in plan) {
        flag?.value = false;
      }
      if (inWin98) navigator.popUntil((r) => r.isFirst);
      status.value = null;
      await _wait(const Duration(milliseconds: 800));
      done();
    }
  }

  /// The camera at rest for 5 s, then 4 tosses and 2 half swipes let go.
  static Future<void> _cameraRound() async {
    await _wait(const Duration(seconds: 5));
    for (var k = 0; k < 4 && !_stop; k++) {
      await _swipe(0.75, const Duration(milliseconds: 320));
      await _wait(const Duration(milliseconds: 1400));
    }
    for (var k = 0; k < 2 && !_stop; k++) {
      await _swipe(0.25, const Duration(milliseconds: 700), slow: true);
      await _wait(const Duration(milliseconds: 1000));
    }
  }

  /// Darkroom 98 redrawing every frame for 5 s.
  static Future<void> _win98Round() async {
    pulse.value = true;
    await _wait(const Duration(seconds: 5));
    pulse.value = false;
  }

  /// A finger across [fraction] of the screen the tossing way over [time],
  /// one move a frame; [slow] ends at rest (lets the camera spring back).
  static Future<void> _swipe(double fraction, Duration time, {bool slow = false}) async {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    final dir = tossDirection?.call();
    if (view == null || dir == null || _stop) return;
    final size = view.physicalSize / view.devicePixelRatio;
    final start = Offset(size.width * (dir > 0 ? 0.3 : 0.7), size.height * 0.5);
    final distance = size.width * fraction * dir;
    final binding = GestureBinding.instance;
    final pointer = 900 + _pointers++;
    final clock = Stopwatch()..start();
    var at = start;
    Duration stamp() => Duration(microseconds: 1000000000 + clock.elapsedMicroseconds);
    binding.handlePointerEvent(PointerDownEvent(pointer: pointer, position: at, timeStamp: stamp()));
    while (clock.elapsed < time && !_stop) {
      await SchedulerBinding.instance.endOfFrame;
      final t = (clock.elapsedMicroseconds / time.inMicroseconds).clamp(0.0, 1.0);
      // eased out when slow: the finger stops before it lifts
      final eased = slow ? 1 - (1 - t) * (1 - t) : t;
      final next = start + Offset(distance * eased, 0);
      binding.handlePointerEvent(
        PointerMoveEvent(pointer: pointer, position: next, delta: next - at, timeStamp: stamp()),
      );
      at = next;
    }
    if (slow) await _wait(const Duration(milliseconds: 150));
    binding.handlePointerEvent(PointerUpEvent(pointer: pointer, position: at, timeStamp: stamp()));
  }

  static int _pointers = 0;

  @visibleForTesting
  static Future<void> swipeForTest(double fraction, Duration time) => _swipe(fraction, time);

  static Future<void> _wait(Duration d) async {
    final until = DateTime.now().add(d);
    while (!_stop && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

/// Inside Darkroom 98's screen: while a speed test runs, a speck that
/// changes every frame, so the whole screen (under its glass and filters)
/// redraws the way it does whenever anything on it moves.
class SpeedTestPulse extends StatefulWidget {
  const SpeedTestPulse({super.key});

  @override
  State<SpeedTestPulse> createState() => _SpeedTestPulseState();
}

class _SpeedTestPulseState extends State<SpeedTestPulse> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() => _n++));
  int _n = 0;

  @override
  void initState() {
    super.initState();
    SpeedTestRun.pulse.addListener(_onPulse);
  }

  void _onPulse() {
    if (SpeedTestRun.pulse.value) {
      if (!_ticker.isActive) unawaited(_ticker.start());
    } else {
      _ticker.stop();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    SpeedTestRun.pulse.removeListener(_onPulse);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!SpeedTestRun.pulse.value) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomRight,
      child: SizedBox(
        width: 2,
        height: 2,
        child: ColoredBox(color: Color(_n.isEven ? 0x22808080 : 0x23808080)),
      ),
    );
  }
}

/// Over the whole app while a speed test runs: which step, and how to stop.
class SpeedTestBanner extends StatelessWidget {
  const SpeedTestBanner({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: SpeedTestRun.status,
    builder: (context, text, _) => text == null
        ? const SizedBox.shrink()
        : Directionality(
            textDirection: TextDirection.ltr,
            child: GestureDetector(
              onTap: SpeedTestRun.stop,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xD9000000),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$text\nHands off the phone. Tap here to stop.',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xE6FFFFFF),
                    decoration: TextDecoration.none,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
  );
}
