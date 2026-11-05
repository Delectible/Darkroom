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

/// A part of a step: what it does, about how long that takes (for the
/// countdown), and whether it's about motion (judged on the frames drawn
/// while something moved) or the screen at rest (all its frames).
class _Phase {
  const _Phase(this.name, this.seconds, this.act, {this.motion = true});

  final String name;
  final double seconds;
  final Future<void> Function(NavigatorState nav) act;
  final bool motion;
}

/// One step of the run: phases on one screen, with switches on (and Fancy
/// graphics off for [classic]).
class _Step {
  const _Step(this.name, this.phases, {this.flags = const [], this.classic = false, this.variant = false});

  final String name;
  final List<_Phase> phases;
  final List<ValueNotifier<bool>> flags;
  final bool classic;

  /// In the second part: the camera swipe again, with a switch on.
  final bool variant;
}

/// Debug > Performance > Run Speed Test: the same few minutes on every
/// phone, hands off. Part one goes through the app as a person would (the
/// camera at rest and swiped between the bodies, the film picker, the
/// settings, the corkboard and Darkroom 98 sliding in, scrolling, sliding
/// out); part two swipes the camera again with each speed switch on its
/// own, all of them, and the drawn bodies. Moving parts are judged on the
/// frames drawn while something moved (frame rate against the screen's,
/// share of frames dropped); still screens on all their frames. A panel on
/// top shows the step, a countdown and the live frame rate (it changes
/// once a second). At the end, one compact text to copy and send.
class SpeedTestRun {
  SpeedTestRun._();

  /// What's on the panel (null when idle). Tapping the panel stops the run.
  static final status = ValueNotifier<SpeedTestStatus?>(null);

  /// Darkroom 98 redraws its screen every frame while true.
  static final pulse = ValueNotifier<bool>(false);

  /// Set by the camera screen: which way (+1 right, -1 left) a swipe tosses
  /// the camera in hand to the other one.
  static int Function()? tossDirection;

  /// Set by the camera screen: slides 'win98' or 'corkboard' in, or opens
  /// 'picker' / 'settings' (completes once it's on its way).
  static Future<void> Function(String screen)? open;

  /// Set by the camera screen: stops (true) or restarts the camera's stream.
  static void Function(bool paused)? pauseCamera;

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

  // ---- what it does

  static final _rest = _Phase('rest', 5, (_) => _wait(5), motion: false);
  static final _swipes = _Phase('swipe', 12, (_) async {
    for (var k = 0; k < 4 && !_stop; k++) {
      await _swipe(Offset(0.75 * _toss(), 0), 320);
      await _wait(1.5);
    }
    for (var k = 0; k < 2 && !_stop; k++) {
      await _swipe(Offset(0.25 * _toss(), 0), 700, slow: true);
      await _wait(1.0);
    }
  });

  /// Opens [screen] and closes it again, twice (sheets that slide up).
  static _Phase _openClose(String screen) => _Phase('open/close', 6.5, (nav) async {
    for (var k = 0; k < 2 && !_stop; k++) {
      await _open(screen);
      await _wait(1.6);
      await nav.maybePop();
      await _wait(1.6);
    }
  });

  static _Phase _slideIn(String screen) => _Phase('slide in', 3, (_) async {
    await _open(screen);
    await _wait(1.2);
  });

  static _Phase _slideOut() => _Phase('slide out', 2.5, (nav) async {
    nav.popUntil((r) => r.isFirst);
    await _wait(2.5);
  });

  /// Problems met on the way (a screen that wouldn't open), for the results.
  static final _notes = <String>[];

  static Future<void> _open(String screen) async {
    final o = open;
    if (o == null) return _notes.add('$screen: no camera screen to open it from');
    try {
      await o(screen);
    } catch (e) {
      _notes.add('$screen: $e');
    }
  }

  /// A swipe with the stronger request to Android for the full refresh rate.
  static final _strongVote = _Phase('swipe', 13, (nav) async {
    await _channel('strongVote', true);
    await _wait(1);
    await _swipes.act(nav);
    await _channel('strongVote', false);
  });

  static Future<Object?> _channel(String method, [Object? args]) async {
    if (!Platform.isAndroid) return null;
    try {
      return await const MethodChannel(
        'darkroom/display',
      ).invokeMethod<Object?>(method, args).timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  /// Battery saver, heat, Smooth display, free memory: one line (never
  /// throws: a phone's odd value reads as "?").
  static Future<String?> _state() async {
    try {
      final m = await _channel('deviceState');
      return m is Map ? stateLine(m) : null;
    } catch (e) {
      return 'phone state unreadable ($e)';
    }
  }

  /// [m] from Android as one line. Smooth display's top rate can be
  /// Infinity ("as fast as the screen goes", Pixels): "max".
  @visibleForTesting
  static String stateLine(Map<Object?, Object?> m) {
    String hz(Object? v) {
      if (v is! num || v.isNaN || v <= 0) return '?';
      return v.isInfinite ? 'max' : '${v.round()}';
    }

    const heat = ['none', 'light', 'moderate', 'severe', 'critical', 'emergency', 'shutdown'];
    final t = m['thermal'];
    return 'battery saver ${m['powerSave'] == true ? 'ON' : 'off'}, '
        'heat ${t is int && t >= 0 && t < heat.length ? heat[t] : '?'}, '
        'smooth display ${hz(m['minHz'])}-${hz(m['peakHz'])} Hz, '
        'free RAM ${m['freeMb'] ?? '?'} MB${m['lowMemory'] == true ? ' (low)' : ''}';
  }

  /// A swipe with the camera's stream stopped (the viewfinder still).
  static final _cameraOff = _Phase('swipe', 14, (nav) async {
    pauseCamera?.call(true);
    await _wait(2);
    await _swipes.act(nav);
    pauseCamera?.call(false);
  });

  static List<_Step> get _plan => [
    _Step('camera', [_rest, _swipes]),
    _Step('picker', [_openClose('picker')]),
    _Step('settings', [_openClose('settings')]),
    _Step('corkboard', [
      _slideIn('corkboard'),
      _Phase('scroll', 6, (_) async {
        for (final dy in [-0.45, -0.45, 0.3, -0.3]) {
          if (_stop) break;
          await _swipe(Offset(0, dy), 350);
          await _wait(1.1);
        }
      }),
      _slideOut(),
    ]),
    _Step('win98', [
      _slideIn('win98'),
      _Phase('redraw', 4, (_) async {
        pulse.value = true;
        await _wait(4);
        pulse.value = false;
      }),
      _slideOut(),
    ]),
    _Step('no look', [_swipes], flags: [SpeedTests.noLook], variant: true),
    _Step('grain 12', [_rest], flags: [SpeedTests.slowGrain], variant: true),
    _Step('still vf', [_swipes], flags: [SpeedTests.stillSwipe], variant: true),
    _Step('no strap', [_swipes], flags: [SpeedTests.noStrap], variant: true),
    _Step('fxaa', [_swipes], flags: [SpeedTests.cheapEdges], variant: true),
    _Step('3D 70%', [_swipes], flags: [SpeedTests.small3d], variant: true),
    _Step(
      'all light',
      [_swipes],
      flags: [
        SpeedTests.noLook,
        SpeedTests.slowGrain,
        SpeedTests.stillSwipe,
        SpeedTests.noStrap,
        SpeedTests.cheapEdges,
        SpeedTests.small3d,
      ],
      variant: true,
    ),
    _Step('drawn bodies', [_swipes], classic: true, variant: true),
    _Step('camera off', [_cameraOff], variant: true),
    _Step('strong 120 ask', [_strongVote], variant: true),
  ];

  /// Settling time before each step, and Fancy graphics changing.
  static const _settle = 0.8, _fancyTime = 4.0;

  static double get _plannedSeconds {
    var t = 1.5;
    for (final s in _plan) {
      t += _settle + s.phases.fold(0.0, (a, p) => a + p.seconds);
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
    _notes.clear();
    final plan = _plan;
    final total = _plannedSeconds;
    final clock = Stopwatch()..start();
    final screens = <String>[], variants = <String>[];
    var stepNo = 0;
    var stage = 'Getting ready';
    void show() => status.value = SpeedTestStatus(
      step: stepNo,
      of: plan.length,
      stage: stage,
      left: math.max(0, total - clock.elapsedMilliseconds / 1000),
      live: PerfRecorder.lastSecond(),
    );
    // The panel first: nothing below may keep the run from showing it.
    show();
    final tick = Timer.periodic(const Duration(seconds: 1), (_) => show());
    String? before, head;
    var wasFancy = true;
    try {
      before = await _state();
      try {
        head = header?.call();
      } catch (e) {
        _notes.add('header: $e');
      }
      SpeedTests.allOff();
      wasFancy = fancy?.call() ?? true;
      navigator.popUntil((r) => r.isFirst);
      await _wait(1.5);
      PerfRecorder.clear();
      for (final s in plan) {
        if (_stop) break;
        stepNo++;
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
        for (final p in s.phases) {
          if (_stop) break;
          stage = '${s.variant ? 'swipe, ${s.name}' : s.name}: ${p.name}';
          show();
          final key = 'step $stepNo ${p.name}';
          final renders = PerfRecorder.scene3d;
          final time = Stopwatch()..start();
          PerfRecorder.test = key;
          final hz = <double>[];
          final sampler = Timer.periodic(const Duration(milliseconds: 700), (_) async {
            final v = await _displayHz();
            if (v != null) hz.add(v);
          });
          try {
            await p.act(navigator);
          } catch (e) {
            _notes.add('${s.name} ${p.name}: $e');
          }
          sampler.cancel();
          PerfRecorder.test = null;
          final perSecond = (PerfRecorder.scene3d - renders) / math.max(0.1, time.elapsedMilliseconds / 1000);
          final name = s.variant || s.phases.length == 1 && p.name == 'open/close'
              ? s.name
              : '${s.name} ${p.name}';
          (s.variant ? variants : screens).add(
            _row(name, PerfRecorder.framesOf(key), motion: p.motion, renders3d: perSecond, displayHz: hz),
          );
        }
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
    } catch (e) {
      // (a run that breaks still ends with results, saying where)
      _notes.add('run stopped: $e');
    } finally {
      PerfRecorder.test = null;
      pulse.value = false;
      tick.cancel();
      SpeedTests.allOff();
      pauseCamera?.call(false);
      if ((fancy?.call() ?? wasFancy) != wasFancy) await setFancy?.call(wasFancy);
      navigator.popUntil((r) => r.isFirst);
      status.value = null;
      await _channel('strongVote', false);
      final after = await _state();
      try {
        head ??= header?.call();
      } catch (_) {}
      String text;
      try {
        text = await _results(
          screens,
          variants,
          stopped: _stop,
          seconds: clock.elapsed.inSeconds,
          states: [if (before != null) 'start: $before', if (after != null) 'end: $after'],
          head: head,
        );
      } catch (e, st) {
        // (whatever happens, the run ends with something to send)
        text =
            'DARKROOM SPEED TEST: the results failed ($e)\n$st\n\n${[...screens, ...variants, ..._notes].join('\n')}';
      }
      lastResults = text;
      done(text);
    }
  }

  @visibleForTesting
  static String rowForTest(
    String name,
    List<({double ui, double gpu, int vsync, bool moving})> frames, {
    bool motion = true,
  }) => _row(name, frames, motion: motion, renders3d: 0);

  static double _toss() => (tossDirection?.call() ?? 1).toDouble();

  /// The screen's refresh rate (60 if the phone reports something odd).
  static double get _hz {
    final r = ui.PlatformDispatcher.instance.implicitView?.display.refreshRate ?? 60;
    return r.isFinite && r >= 20 && r <= 1000 ? r : 60;
  }

  static const _nameWidth = 17;

  /// One line of results. Moving: the frame rate while moving and the share
  /// of the screen's refreshes that got no new frame (dropped), from the
  /// frames drawn while something moved. At rest: frames a second overall
  /// (the camera's own rate) and no drop figure. Then UI and GPU ms
  /// (average/90th percentile) and the 3D camera's renders a second.
  static String _row(
    String name,
    List<({double ui, double gpu, int vsync, bool moving})> all, {
    required bool motion,
    required double renders3d,
    List<double> displayHz = const [],
  }) {
    final fs = motion ? all.where((f) => f.moving).toList() : all;
    final head = name.padRight(_nameWidth);
    if (fs.length < 3) return '$head(too few frames: ${all.length}, moving ${fs.length})';
    final period = 1e6 / _hz;
    var gapSum = 0, gaps = 0, slots = 0, dropped = 0;
    final gapList = <int>[];
    for (var i = 1; i < fs.length; i++) {
      final g = fs[i].vsync - fs[i - 1].vsync;
      if (g <= 0 || g > (motion ? 250000 : 1000000)) continue; // (a new burst of motion)
      gapSum += g;
      gaps++;
      gapList.add(g);
      final n = math.max(1, (g / period).round());
      slots += n;
      dropped += n - 1;
    }
    final fps = gaps == 0 ? 0 : (1e6 * gaps / gapSum).round();
    String ap(Iterable<double> v) {
      final s = v.toList()..sort();
      final avg = s.reduce((a, b) => a + b) / s.length;
      final p90 = s[math.min(s.length - 1, (s.length * 0.9).floor())];
      return '${avg.toStringAsFixed(1)}/${p90.toStringAsFixed(1)}';
    }

    // Moving: refreshes dropped. At rest: "a" and the share of frames drawn
    // with an animation running (should be 0: a loop left running costs
    // battery and frames).
    final drop = motion
        ? (slots > 0 ? '${(100 * dropped / slots).round()}%' : '-')
        : 'a${(100 * all.where((f) => f.moving).length / all.length).round()}%';
    // The fastest frames came: the rate frames can arrive at (60 here on a
    // 120 Hz screen = something holds the app to 60; 120 with drops = the
    // app misses frames).
    gapList.sort();
    final quick = gapList.isEmpty ? null : gapList[(gapList.length * 0.1).floor()];
    final vsync = !motion || quick == null ? '-' : '${(1e6 / quick).round()}';
    return '$head${fps.toString().padLeft(4)}${drop.padLeft(5)}${ap(fs.map((f) => f.ui)).padLeft(10)}'
        '${ap(fs.map((f) => f.gpu)).padLeft(10)}${renders3d.round().toString().padLeft(5)}'
        '${vsync.padLeft(5)}${(displayHz.isEmpty ? '?' : _hzRange(displayHz)).padLeft(7)}';
  }

  /// The display's rates seen during a phase: "120", or "60-120".
  static String _hzRange(List<double> v) {
    final lo = v.reduce(math.min).round(), hi = v.reduce(math.max).round();
    return lo == hi ? '$lo' : '$lo-$hi';
  }

  static Future<double?> _displayHz() async {
    final v = await _channel('displayHz');
    return v is num && v.isFinite && v > 0 ? v.toDouble() : null;
  }

  static Future<String> _results(
    List<String> screens,
    List<String> variants, {
    required bool stopped,
    required int seconds,
    List<String> states = const [],
    String? head,
  }) async {
    final view = ui.PlatformDispatcher.instance.implicitView;
    var device = Platform.isIOS ? 'iPhone' : '?';
    if (Platform.isAndroid) {
      try {
        device = (await _channel('device'))?.toString() ?? '?';
      } catch (_) {}
    }
    final px = view?.physicalSize;
    final extra = head;
    final columns =
        '${'fps'.padLeft(4)}${'drop'.padLeft(5)}${'ui ms'.padLeft(10)}${'gpu ms'.padLeft(10)}${'3D/s'.padLeft(5)}${'max'.padLeft(5)}${'disp'.padLeft(7)}';
    return [
      'DARKROOM SPEED TEST${stopped ? ' (stopped early)' : ''}, ${seconds}s',
      '$device, ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'screen ${px?.width.round()}x${px?.height.round()} @${view?.devicePixelRatio.toStringAsFixed(2)}x, '
          '${_hz.round()} Hz, ${Platform.numberOfProcessors} cores',
      ?extra,
      ...states,
      'launch: ${LaunchTimer.lastSummary() ?? '?'}',
      '',
      '${'AROUND THE APP'.padRight(_nameWidth)}$columns',
      ...screens,
      if (variants.isNotEmpty) ...['', 'CAMERA SWIPE WITH (or at rest, for grain)', ...variants],
      if (_notes.isNotEmpty) ...['', 'PROBLEMS', ..._notes],
      '',
      'fps: frames a second while moving (at rest: all frames, the camera\'s rate). '
          'drop: refreshes with no new frame while moving (the screen is ${_hz.round()} Hz). '
          'a% (at rest): frames drawn with an animation running (should be 0). '
          'ms: average/90%. 3D/s: 3D camera renders a second. '
          'max: the fastest rate frames came while moving (below the screen = held back). '
          'disp: the rate Android let apps draw at then (Android only).',
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
    // The same gesture on every phone: a move a frame at the screen's rate
    // (at least 8), each stamped as if exactly on time, so the swipe's speed
    // (and whether it tosses) doesn't depend on how the phone's frames run;
    // only how long it takes in real time does.
    final steps = math.max(8, (ms / 1000 * _hz).round());
    final stepTime = Duration(microseconds: ms * 1000 ~/ steps);
    var stamp = const Duration(seconds: 1000);
    var at = start;
    binding.handlePointerEvent(PointerDownEvent(pointer: pointer, position: at, timeStamp: stamp));
    for (var k = 1; k <= steps && !_stop; k++) {
      await SchedulerBinding.instance.endOfFrame;
      final t = k / steps;
      // eased out when slow: the finger stops before it lifts
      final eased = slow ? 1 - (1 - t) * (1 - t) : t;
      final next = start + distance * eased;
      stamp += stepTime;
      binding.handlePointerEvent(
        PointerMoveEvent(pointer: pointer, position: next, delta: next - at, timeStamp: stamp),
      );
      at = next;
    }
    // A flick lifts right after its last move; a slow swipe stops first.
    var lift = stamp + const Duration(milliseconds: 1);
    if (slow) {
      await _wait(0.15);
      lift = stamp + const Duration(milliseconds: 150);
    }
    binding.handlePointerEvent(PointerUpEvent(pointer: pointer, position: at, timeStamp: lift));
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
