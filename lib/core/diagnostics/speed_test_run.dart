import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'launch_timer.dart';
import 'perf_recorder.dart';
import 'speed_tests.dart';

/// What a step does on its screen.
enum _Where { camera, corkboard, win98 }

/// One step of the run: a short name for the results, where it runs, and
/// what it changes (switches turned on, and Fancy graphics off).
class _Step {
  const _Step(this.name, this.where, {this.flags = const [], this.classic = false});

  final String name;
  final _Where where;
  final List<ValueNotifier<bool>> flags;

  /// Fancy graphics off (the drawn bodies).
  final bool classic;
}

/// A phase a step is measured in, and how long it takes (for the countdown).
class _Phase {
  const _Phase(this.name, this.seconds);
  final String name;
  final double seconds;
}

/// Debug > Performance > Run Speed Test: works through the app's costly
/// pieces one at a time, the same way on every phone, with the phone left
/// alone: the camera at rest and swiped between the bodies (real touches,
/// made up by the app) with each switch on its own and a few together, the
/// drawn bodies, the corkboard scrolling, and Darkroom 98 redrawing. A
/// panel on top shows the step, a countdown and the live frame rate (it
/// changes once a second: a frame a second on top of the test's own). At
/// the end, one compact text to copy and send.
class SpeedTestRun {
  SpeedTestRun._();

  /// What's on the panel (null when idle). Tapping the panel stops the run.
  static final status = ValueNotifier<SpeedTestStatus?>(null);

  /// Darkroom 98 redraws its screen every frame while true.
  static final pulse = ValueNotifier<bool>(false);

  /// Set by the camera screen: which way (+1 right, -1 left) a swipe tosses
  /// the camera in hand to the other one.
  static int Function()? tossDirection;

  /// Set by the camera screen: slides 'win98' or 'corkboard' in (completes
  /// once it's up).
  static Future<void> Function(String screen)? open;

  /// Set by the camera screen: Fancy graphics on or off, and whether it's on.
  static Future<void> Function(bool on)? setFancy;
  static bool Function()? fancy;

  /// Extra lines for the results' header (the app version, the 3D textures),
  /// set by the Debug window.
  static String Function()? header;

  /// The last run's results (this app session), for Debug to show again.
  static String? lastResults;

  static bool _stop = false;
  static void stop() => _stop = true;

  static bool get running => status.value != null;

  static List<_Step> get _plan => [
    const _Step('base', _Where.camera),
    _Step('no look', _Where.camera, flags: [SpeedTests.noLook]),
    _Step('grain 12', _Where.camera, flags: [SpeedTests.slowGrain]),
    _Step('still vf', _Where.camera, flags: [SpeedTests.stillSwipe]),
    _Step('no strap', _Where.camera, flags: [SpeedTests.noStrap]),
    _Step('fxaa', _Where.camera, flags: [SpeedTests.cheapEdges]),
    _Step('3D 70%', _Where.camera, flags: [SpeedTests.small3d]),
    _Step(
      'light',
      _Where.camera,
      flags: [
        SpeedTests.slowGrain,
        SpeedTests.stillSwipe,
        SpeedTests.noStrap,
        SpeedTests.cheapEdges,
        SpeedTests.small3d,
      ],
    ),
    const _Step('classic', _Where.camera, classic: true),
    const _Step('base', _Where.corkboard),
    const _Step('base', _Where.win98),
    _Step('no lines', _Where.win98, flags: [SpeedTests.noLines]),
    _Step('no glass', _Where.win98, flags: [SpeedTests.noGlass]),
    _Step('no tint', _Where.win98, flags: [SpeedTests.noTint]),
    _Step('square', _Where.win98, flags: [SpeedTests.squareScreen]),
    _Step(
      'all off',
      _Where.win98,
      flags: [SpeedTests.noLines, SpeedTests.noGlass, SpeedTests.noTint, SpeedTests.squareScreen],
    ),
  ];

  static List<_Phase> _phases(_Where w) => switch (w) {
    _Where.camera => const [_Phase('rest', 5), _Phase('swipe', 12)],
    _Where.corkboard => const [_Phase('rest', 3), _Phase('scroll', 6)],
    _Where.win98 => const [_Phase('redraw', 5)],
  };

  /// Settling time between steps, and moving between screens.
  static const _settle = 0.8, _move = 2.0, _fancyTime = 4.0;

  static double get _plannedSeconds {
    var t = 1.5;
    var at = _Where.camera;
    for (final s in _plan) {
      if (s.where != at) t += _move * 2;
      at = s.where;
      t += _settle + _phases(s.where).fold(0.0, (a, p) => a + p.seconds);
      if (s.classic) t += _fancyTime + 3;
    }
    return t;
  }

  /// About how long a run takes, in minutes (for the confirmation).
  static int get minutes => (_plannedSeconds / 60).ceil();

  /// Runs the plan from the camera screen ([navigator] is popped to it
  /// first), then calls [done] with the results (also when stopped early).
  static Future<void> run(NavigatorState navigator, {required void Function(String results) done}) async {
    if (running) return;
    _stop = false;
    final plan = _plan;
    final total = _plannedSeconds;
    final clock = Stopwatch()..start();
    SpeedTests.allOff();
    final wasFancy = fancy?.call() ?? true;
    final rows = <String>[];
    var stepNo = 0;
    var stage = 'Getting ready';
    void show() => status.value = SpeedTestStatus(
      step: stepNo,
      of: plan.length,
      stage: stage,
      left: math.max(0, total - clock.elapsedMilliseconds / 1000),
      live: PerfRecorder.lastSecond(),
    );
    show();
    final tick = Timer.periodic(const Duration(seconds: 1), (_) => show());
    navigator.popUntil((r) => r.isFirst);
    await _wait(1.5);
    PerfRecorder.clear();
    var at = _Where.camera;
    try {
      for (final s in plan) {
        if (_stop) break;
        stepNo++;
        final where = s.where.name;
        if (s.where != at) {
          stage = 'Opening $where';
          show();
          if (at != _Where.camera) {
            navigator.popUntil((r) => r.isFirst);
            await _wait(_move);
          }
          if (s.where != _Where.camera) {
            await open?.call(where);
            await _wait(_move);
          }
          at = s.where;
        }
        for (final f in s.flags) {
          f.value = true;
        }
        if (s.classic) {
          stage = 'Fancy graphics off';
          show();
          await setFancy?.call(false);
          await _wait(_fancyTime);
        }
        await _wait(_settle);
        final key = 'step $stepNo';
        final cells = <String>[];
        for (final p in _phases(s.where)) {
          if (_stop) break;
          stage = '$where ${s.name}: ${p.name}';
          show();
          PerfRecorder.test = '$key ${p.name}';
          await _act(s.where, p);
          PerfRecorder.test = null;
          cells.add(_cell(p.name, PerfRecorder.framesOf('$key ${p.name}')));
        }
        rows.add('${'${where.substring(0, 3)} ${s.name}'.padRight(13)}${cells.join('\n${' ' * 13}')}');
        for (final f in s.flags) {
          f.value = false;
        }
        if (s.classic) {
          stage = 'Fancy graphics back on';
          show();
          await setFancy?.call(wasFancy);
          await _wait(3);
        }
      }
    } finally {
      PerfRecorder.test = null;
      pulse.value = false;
      tick.cancel();
      SpeedTests.allOff();
      if ((fancy?.call() ?? wasFancy) != wasFancy) await setFancy?.call(wasFancy);
      if (at != _Where.camera) navigator.popUntil((r) => r.isFirst);
      status.value = null;
      final text = await _results(rows, stopped: _stop, seconds: clock.elapsed.inSeconds);
      lastResults = text;
      done(text);
    }
  }

  /// What a phase does: the camera at rest, then swipes (4 tosses and 2
  /// half swipes let go); the corkboard scrolled; Darkroom 98 redrawing.
  static Future<void> _act(_Where w, _Phase p) async {
    switch ((w, p.name)) {
      case (_Where.camera, 'swipe'):
        for (var k = 0; k < 4 && !_stop; k++) {
          await _swipe(Offset(0.75 * _toss(), 0), 320);
          await _wait(1.5);
        }
        for (var k = 0; k < 2 && !_stop; k++) {
          await _swipe(Offset(0.25 * _toss(), 0), 700, slow: true);
          await _wait(1.0);
        }
      case (_Where.corkboard, 'scroll'):
        for (final dy in [-0.45, -0.45, 0.3, -0.3]) {
          if (_stop) break;
          await _swipe(Offset(0, dy), 350);
          await _wait(1.1);
        }
      case (_Where.win98, _):
        pulse.value = true;
        await _wait(p.seconds);
        pulse.value = false;
      default:
        await _wait(p.seconds);
    }
  }

  static double _toss() => (tossDirection?.call() ?? 1).toDouble();

  static double get _hz => ui.PlatformDispatcher.instance.implicitView?.display.refreshRate ?? 60;

  /// A phase's numbers: fps (frames a second while drawing), UI and GPU ms
  /// (average/90th percentile), and the share of frames over the screen's
  /// budget on either thread.
  static String _cell(String phase, List<({double ui, double gpu, int vsync})> fs) {
    if (fs.length < 3) return '${phase.padRight(6)}  (too few frames)';
    var gapSum = 0, gaps = 0;
    for (var i = 1; i < fs.length; i++) {
      final g = fs[i].vsync - fs[i - 1].vsync;
      if (g > 0 && g < 100000) {
        gapSum += g;
        gaps++;
      }
    }
    final fps = gaps == 0 ? 0 : (1e6 * gaps / gapSum).round();
    final budget = 1000 / _hz * 1.05;
    final late = fs.where((f) => f.ui > budget || f.gpu > budget).length;
    String ap(Iterable<double> v) {
      final s = v.toList()..sort();
      final avg = s.reduce((a, b) => a + b) / s.length;
      final p90 = s[math.min(s.length - 1, (s.length * 0.9).floor())];
      return '${avg.toStringAsFixed(1)}/${p90.toStringAsFixed(1)}';
    }

    return '${phase.padRight(6)}${fps.toString().padLeft(4)}${ap(fs.map((f) => f.ui)).padLeft(10)}'
        '${ap(fs.map((f) => f.gpu)).padLeft(10)}${'${(100 * late / fs.length).round()}%'.padLeft(5)}';
  }

  static Future<String> _results(List<String> rows, {required bool stopped, required int seconds}) async {
    final view = ui.PlatformDispatcher.instance.implicitView;
    var device = Platform.isIOS ? 'iPhone' : '?';
    if (Platform.isAndroid) {
      try {
        device = await const MethodChannel('darkroom/display').invokeMethod<String>('device') ?? '?';
      } catch (_) {}
    }
    final px = view?.physicalSize;
    final extra = header?.call();
    return [
      'DARKROOM SPEED TEST${stopped ? ' (stopped early)' : ''}, ${seconds}s',
      '$device, ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'screen ${px?.width.round()}x${px?.height.round()} @${view?.devicePixelRatio.toStringAsFixed(2)}x, '
          '${_hz.round()} Hz, ${Platform.numberOfProcessors} cores',
      ?extra,
      'launch: ${LaunchTimer.lastSummary() ?? '?'}',
      '',
      'step         phase  fps  ui ms     gpu ms   late',
      ...rows,
      '',
      'fps: frames a second while drawing. ms: average/90%. '
          'late: frames over ${(1000 / _hz).toStringAsFixed(1)} ms.',
    ].join('\n');
  }

  static Future<void> _swipe(Offset fraction, int ms, {bool slow = false}) async {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null || _stop) return;
    final size = view.physicalSize / view.devicePixelRatio;
    final distance = Offset(size.width * fraction.dx, size.height * fraction.dy);
    // starts on the side it moves away from (clear of the screen's edges)
    final start = Offset(
      size.width * (fraction.dx > 0 ? 0.3 : (fraction.dx < 0 ? 0.7 : 0.5)),
      size.height * (fraction.dy > 0 ? 0.3 : (fraction.dy < 0 ? 0.7 : 0.5)),
    );
    final binding = GestureBinding.instance;
    final pointer = 900 + _pointers++;
    final clock = Stopwatch()..start();
    var at = start;
    Duration stamp() => Duration(microseconds: 1000000000 + clock.elapsedMicroseconds);
    binding.handlePointerEvent(PointerDownEvent(pointer: pointer, position: at, timeStamp: stamp()));
    while (clock.elapsedMilliseconds < ms && !_stop) {
      await SchedulerBinding.instance.endOfFrame;
      final t = (clock.elapsedMicroseconds / (ms * 1000)).clamp(0.0, 1.0);
      // eased out when slow: the finger stops before it lifts
      final eased = slow ? 1 - (1 - t) * (1 - t) : t;
      final next = start + distance * eased;
      binding.handlePointerEvent(
        PointerMoveEvent(pointer: pointer, position: next, delta: next - at, timeStamp: stamp()),
      );
      at = next;
    }
    if (slow) await _wait(0.15);
    binding.handlePointerEvent(PointerUpEvent(pointer: pointer, position: at, timeStamp: stamp()));
  }

  static int _pointers = 0;

  @visibleForTesting
  static Future<void> swipeForTest(double fraction, Duration time) =>
      _swipe(Offset(fraction * _toss(), 0), time.inMilliseconds);

  static Future<void> _wait(double seconds) async {
    final until = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
    while (!_stop && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

/// What the speed test panel shows.
class SpeedTestStatus {
  const SpeedTestStatus({
    required this.step,
    required this.of,
    required this.stage,
    required this.left,
    this.live,
  });

  final int step, of;
  final String stage;

  /// Seconds left, about.
  final double left;

  /// The last second: frames, average UI / GPU ms.
  final ({int fps, double ui, double gpu})? live;
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

/// Over the whole app while a speed test runs: the step, a countdown, the
/// live frame rate; tapping it stops the run.
class SpeedTestBanner extends StatelessWidget {
  const SpeedTestBanner({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SpeedTestStatus?>(
    valueListenable: SpeedTestRun.status,
    builder: (context, s, _) {
      if (s == null) return const SizedBox.shrink();
      final left = s.left.round();
      final live = s.live;
      const ink = TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        color: Color(0xE6FFFFFF),
        decoration: TextDecoration.none,
        height: 1.35,
      );
      return Directionality(
        textDirection: TextDirection.ltr,
        child: GestureDetector(
          onTap: SpeedTestRun.stop,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
            decoration: BoxDecoration(color: const Color(0xD9000000), borderRadius: BorderRadius.circular(6)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'SPEED TEST  ${s.step}/${s.of}',
                      style: ink.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF6BFF7A)),
                    ),
                    const Spacer(),
                    Text('${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')} left', style: ink),
                  ],
                ),
                Text(s.stage, style: ink),
                Text(
                  live == null
                      ? 'measuring...'
                      : '${live.fps} fps, UI ${live.ui.toStringAsFixed(1)} ms, GPU ${live.gpu.toStringAsFixed(1)} ms',
                  style: ink.copyWith(color: const Color(0xB3FFFFFF)),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: s.of == 0 ? 0 : (s.step - 1).clamp(0, s.of) / s.of,
                    minHeight: 3,
                    color: const Color(0xFF6BFF7A),
                    backgroundColor: const Color(0x33FFFFFF),
                  ),
                ),
                const SizedBox(height: 3),
                Text('Hands off the phone. Tap here to stop.', style: ink.copyWith(fontSize: 10)),
              ],
            ),
          ),
        ),
      );
    },
  );
}
