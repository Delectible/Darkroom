import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as dart_ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How much drawing this phone gets, steered by how its frames really run.
///
/// Instead of one "fancy graphics" switch, two ladders of small steps, each
/// one cheaper to draw than the last and chosen so the first ones are the
/// hardest to see:
///  * the graphics chip's ([gpuSteps]): the 3D body's edge smoothing, the
///    viewfinder's halation, the 3D body drawn a little smaller (its labels
///    soften to match, so nothing on it looks sharper than the rest), and a
///    steady 60 Hz on a screen the phone can't fill;
///  * the app's own work, the processor's ([uiSteps]): a simpler strap, the
///    film grain moving 12 times a second instead of 24, a steady 60 Hz.
///
/// Judged only on frames drawn while something moves (PerfRecorder tags
/// them), in windows of [window] frames: how many of the screen's refreshes
/// got no new frame, and which side (UI or GPU) took the time. Two bad
/// windows in a row take a step down the ladder of whichever side is the
/// bottleneck (a very bad one, two steps at once); six clean ones in a row take the last step back up (once a
/// step back up goes wrong, no more tries this run). A steady 60 frames a
/// second is good enough on any screen: a 120 Hz phone held to 60 by Android
/// (a Pixel while its camera runs) isn't blamed for it (2.1.10: it was, when
/// its frames weren't very cheap, and stepped all the way down). Below 60, if
/// frames are cheap, the rate they come at is the one judged against.
/// Steps are saved, so the next launch starts where this one ended; a new
/// phone starts by its memory (low RAM: the first two steps taken).
///
/// Light: a few comparisons per frame, nothing while nothing moves. Debug >
/// Performance > Quality Manager shows it all and steps it by hand.
class Quality {
  Quality._();

  // ---- the dials (read by the parts of the app they lighten) ---------------

  /// The 3D body's edges smoothed by a cheap filter (FXAA), not MSAA.
  static final fxaa = ValueNotifier<bool>(false);

  /// No viewfinder halation (a full-screen blur pass every camera frame).
  static final noHalation = ValueNotifier<bool>(false);

  /// The 3D body's draw scale (1, 0.9, 0.8, 0.7): BodyQuality follows it.
  static final scale3d = ValueNotifier<double>(1);

  /// The screen held at 60 Hz (on a 90/120 Hz screen the phone can't fill:
  /// a steady 60 looks smoother than a stuttering 75).
  static final cap60 = ValueNotifier<bool>(false);

  /// The strap drawn simply (no shadow, stitching or weave).
  static final lightStrap = ValueNotifier<bool>(false);

  /// The film grain moves 12 times a second instead of 24.
  static final slowGrain = ValueNotifier<bool>(false);

  /// Any dial moved.
  static final Listenable changed = Listenable.merge([
    fxaa,
    noHalation,
    scale3d,
    cap60,
    lightStrap,
    slowGrain,
  ]);

  static const gpuSteps = ['cheap 3D edges', 'no halation', '3D at 90%', '3D at 80%', '60 Hz', '3D at 70%'];
  static const uiSteps = ['simple strap', 'grain at 12 fps', '60 Hz'];

  /// Steps taken on each ladder.
  static int get gpu => _gpu;
  static int get ui => _ui;
  static int _gpu = 0, _ui = 0;

  /// Steers itself (Debug can turn this off and step by hand).
  static bool auto = true;

  /// Not judging (a speed test runs: it measures each step itself).
  static bool paused = false;

  /// Judging (after the launch curtain: start-up frames aren't the app's
  /// normal running).
  static bool listening = false;

  /// The phone struggled with every step taken on the side that limits it:
  /// "Things feeling slow?" may ask (LagWatch, the last resort).
  static bool get exhausted => _exhausted;
  static bool _exhausted = false;

  // ---- start ------------------------------------------------------------

  // (v2, 2.1.10: steps saved under the old, too touchy judging are dropped)
  static const _gpuKey = 'quality.v2.gpu', _uiKey = 'quality.v2.ui';
  static const oldKeys = {'quality.gpu', 'quality.ui'};
  static const keys = {_gpuKey, _uiKey};
  static SharedPreferencesWithCache? _prefs;
  static bool _saved = false;
  static final _clock = Stopwatch();

  /// Picks up the saved steps (main.dart, once prefs are open).
  static void start(SharedPreferencesWithCache prefs) {
    _prefs = prefs;
    _clock.start();
    for (final k in oldKeys) {
      if (prefs.containsKey(k)) unawaited(prefs.remove(k));
    }
    final g = prefs.getInt(_gpuKey), u = prefs.getInt(_uiKey);
    _saved = g != null || u != null;
    _gpu = (g ?? 0).clamp(0, gpuSteps.length);
    _ui = (u ?? 0).clamp(0, uiSteps.length);
    _apply();
    if (_saved) _log('started at the saved steps');
  }

  /// A first start on a phone with little memory: begins two steps down
  /// (cheap edges, no halation: no multisampled render targets or blur
  /// pass); the slowest phones at a steady 60 Hz too. Only when nothing was
  /// saved.
  static void lowMemory({required bool low, required bool lowest}) {
    if (_saved || (!low && !lowest)) return;
    _set(lowest ? 5 : 2, _ui, 'start: ${lowest ? 'very little' : 'little'} memory');
  }

  // ---- judging -----------------------------------------------------------

  /// Frames per verdict (about half a second of movement at 90-120 Hz).
  static const window = 48;

  static final _frames = <({double ui, double gpu, int vsync})>[];
  static int _bad = 0, _good = 0, _cooldown = 0, _probe = 0;
  static bool _ceiling = false;
  static final _taken = <String>[]; // 'g' / 'u', newest last: the next step up

  /// One drawn frame (PerfRecorder): its UI and GPU ms, its vsync (µs),
  /// whether something moved.
  static void frame(double uiMs, double gpuMs, int vsync, bool moving) {
    if (!moving || !auto || paused || !listening) return;
    _frames.add((ui: uiMs, gpu: gpuMs, vsync: vsync));
    if (_frames.length >= window) _judge();
  }

  static double get _hz {
    final r = dart_ui.PlatformDispatcher.instance.implicitView?.display.refreshRate ?? 60;
    return r.isFinite && r >= 20 && r <= 1000 ? r : 60;
  }

  static void _judge() {
    final fs = List.of(_frames);
    _frames.clear();
    final v = verdict(fs, _hz);
    if (v == null) return;
    _windows.add(v);
    if (_windows.length > 12) _windows.removeAt(0);
    if (_probe > 0) _probe--;
    if (_cooldown > 0) {
      _cooldown--;
      return;
    }
    if (v.bad) {
      _good = 0;
      // (two bad windows in a row; a very bad one, a third of the
      // refreshes or more missed, steps down at once, two steps)
      final severe = v.drop >= 0.33;
      if (++_bad < (severe ? 1 : 2)) return;
      _bad = 0;
      // A step back up that went wrong: down again, and no more tries.
      if (_probe > 0) _ceiling = true;
      stepDown(gpuSide: v.gpuBound, why: v.text);
      if (severe) stepDown(gpuSide: v.gpuBound, why: 'and again: ${v.text}');
    } else if (v.clean) {
      _bad = 0;
      if (++_good < 6 || _ceiling || _taken.isEmpty && _gpu == 0 && _ui == 0) return;
      _good = 0;
      stepUp(why: 'room to spare');
      _probe = 3;
    } else {
      _bad = 0;
      _good = 0;
    }
  }

  /// A window's numbers, and what they say (pure: tested).
  static Verdict? verdict(List<({double ui, double gpu, int vsync})> fs, double hz) {
    final gaps = <double>[];
    for (var i = 1; i < fs.length; i++) {
      final g = (fs[i].vsync - fs[i - 1].vsync) / 1000;
      if (g > 0 && g < 100) gaps.add(g); // (a new burst of movement)
    }
    if (gaps.length < window ~/ 2) return null;
    double p90(Iterable<double> v) {
      final s = v.toList()..sort();
      return s[math.min(s.length - 1, (s.length * 0.9).floor())];
    }

    final nominal = 1000 / hz;
    final uiP90 = p90(fs.map((f) => f.ui)), gpuP90 = p90(fs.map((f) => f.gpu));
    final work = math.max(uiP90, gpuP90);
    // Frames that are cheap to draw but come slower than the screen: the
    // phone (Android, a camera running) holds the rate, not the app. Judged
    // against the rate they can come at.
    final sorted = [...gaps]..sort();
    final quick = sorted[(sorted.length * 0.1).floor()];
    // (never judged against more than 60 a second: a steady 60 is fine)
    final period = math.max(1000 / 60, work < nominal * 0.75 ? math.max(nominal, quick) : nominal);
    var slots = 0, dropped = 0;
    for (final g in gaps) {
      // (a frame up to 30% late still counts as on time, past that as a
      // refresh missed: rounding let a jittery 40-45 fps pass as none
      // missed, so a slow tablet barely stepped down, 2.2.3)
      final n = math.max(1, (g / period - 0.3).ceil());
      slots += n;
      dropped += n - 1;
    }
    final drop = dropped / slots;
    return Verdict(
      drop: drop,
      uiP90: uiP90,
      gpuP90: gpuP90,
      gpuBound: gpuP90 >= uiP90,
      // Missed a fifth of the refreshes, and our own work is a real part of
      // a frame (not a phone idling between camera frames).
      bad: drop > 0.2 && work > period * 0.6,
      clean: drop < 0.05 && work < period * 0.6,
      hz: 1000 / period,
    );
  }

  // ---- steps -----------------------------------------------------------

  /// One step down the side that limits the phone (the other side when
  /// that one has no steps left).
  static void stepDown({required bool gpuSide, String why = 'by hand'}) {
    if (gpuSide && _gpu < gpuSteps.length) {
      _taken.add('g');
      _set(_gpu + 1, _ui, why);
    } else if (_ui < uiSteps.length) {
      _taken.add('u');
      _set(_gpu, _ui + 1, why);
    } else if (_gpu < gpuSteps.length) {
      _taken.add('g');
      _set(_gpu + 1, _ui, why);
    } else {
      _exhausted = true;
      _log('struggling with every step taken ($why)');
      return;
    }
    _cooldown = 2;
  }

  /// The last step back up.
  static void stepUp({String why = 'by hand'}) {
    _exhausted = false;
    final side = _taken.isNotEmpty ? _taken.removeLast() : (_gpu > 0 ? 'g' : 'u');
    if (side == 'g' && _gpu > 0) {
      _set(_gpu - 1, _ui, why);
    } else if (_ui > 0) {
      _set(_gpu, _ui - 1, why);
    } else if (_gpu > 0) {
      _set(_gpu - 1, _ui, why);
    }
    _cooldown = 2;
  }

  /// Back to full quality, the saved steps forgotten.
  static void reset() {
    _taken.clear();
    _ceiling = false;
    _exhausted = false;
    _bad = _good = _cooldown = _probe = 0;
    _set(0, 0, 'reset');
    _prefs?.remove(_gpuKey);
    _prefs?.remove(_uiKey);
    _saved = false;
  }

  static void _set(int g, int u, String why) {
    final was = summary;
    _gpu = g.clamp(0, gpuSteps.length);
    _ui = u.clamp(0, uiSteps.length);
    _apply();
    _prefs?.setInt(_gpuKey, _gpu);
    _prefs?.setInt(_uiKey, _ui);
    _saved = true;
    if (summary != was) _log('$was -> $summary ($why)');
  }

  static void _apply() {
    fxaa.value = _gpu >= 1;
    noHalation.value = _gpu >= 2;
    scale3d.value = _gpu >= 6
        ? 0.7
        : _gpu >= 4
        ? 0.8
        : _gpu >= 3
        ? 0.9
        : 1;
    cap60.value = _gpu >= 5 || _ui >= 3;
    lightStrap.value = _ui >= 1;
    slowGrain.value = _ui >= 2;
  }

  // ---- reports -----------------------------------------------------------

  static final _windows = <Verdict>[];
  static final _events = <String>[];

  static void _log(String text) {
    final s = _clock.elapsed.inSeconds;
    _events.add('${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')} $text');
    if (_events.length > 30) _events.removeAt(0);
  }

  /// The steps taken, in a few words: "full" or "cheap 3D edges, no halation".
  static String get summary {
    final on = {...gpuSteps.take(_gpu), ...uiSteps.take(_ui)};
    return on.isEmpty ? 'full' : on.join(', ');
  }

  /// For the speed test's header: "quality: GPU 2/6, UI 0/3 (cheap 3D edges, no halation), auto".
  static String get line =>
      'quality: GPU $_gpu/${gpuSteps.length}, UI $_ui/${uiSteps.length} ($summary), '
      '${auto ? 'auto' : 'by hand'}${_ceiling ? ', settled' : ''}';

  static String report() => [
    line,
    'GPU steps: ${[for (var i = 0; i < gpuSteps.length; i++) '${i < _gpu ? '[x]' : '[ ]'} ${gpuSteps[i]}'].join('  ')}',
    'UI steps: ${[for (var i = 0; i < uiSteps.length; i++) '${i < _ui ? '[x]' : '[ ]'} ${uiSteps[i]}'].join('  ')}',
    '',
    'Recent windows of moving frames (dropped, UI/GPU ms 90%, judged at Hz):',
    if (_windows.isEmpty) '  none yet (judged only while things move)',
    for (final w in _windows) '  ${w.text}',
    '',
    'Steps:',
    if (_events.isEmpty) '  none',
    for (final e in _events) '  $e',
  ].join('\n');
}

/// What one window of moving frames said.
class Verdict {
  const Verdict({
    required this.drop,
    required this.uiP90,
    required this.gpuP90,
    required this.gpuBound,
    required this.bad,
    required this.clean,
    required this.hz,
  });

  final double drop, uiP90, gpuP90, hz;
  final bool gpuBound, bad, clean;

  String get text =>
      '${(drop * 100).round()}% dropped, UI ${uiP90.toStringAsFixed(1)} / GPU ${gpuP90.toStringAsFixed(1)} ms '
      'at ${hz.round()} Hz${bad ? ' - too slow (${gpuBound ? 'GPU' : 'UI'})' : (clean ? ' - room to spare' : '')}';
}
