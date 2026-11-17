import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;

import '../shaders/shader_library.dart' show FilmUniforms;
import '../performance/quality.dart';
import 'launch_timer.dart';
import 'speed_tests.dart';

/// Records every frame's timings on the phone (Win98 Help > Debug >
/// Performance Report; always on), labelled with what the app was doing (`mark`), so
/// a slow device can say exactly what is slow: the UI thread (Dart: build,
/// layout, painting the layer tree) or the raster thread (the GPU drawing it:
/// shaders, blurs, big images).
class PerfRecorder {
  PerfRecorder._();

  static bool _on = false;
  static bool get recording => _on;

  static final List<_Frame> _frames = [];

  /// About two minutes at 120 Hz (the recorder is always on).
  static const _keep = 15000;

  static String? _label;

  /// The Run Speed Tests step under way ("test 3: camera still swipe"):
  /// its frames are labelled with it, in front of the activity.
  static String? test;

  /// The screen on top, for frames nothing labelled ("idle camera"...).
  static String get screen => _screen;
  static set screen(String v) {
    if (v == _screen) return;
    _screen = v;
    event('screen: $v');
  }

  static String _screen = 'camera';
  static DateTime _labelUntil = DateTime(0);

  /// Labels the frames of the next [hold] (an animation, a dialog opening).
  /// Cheap when not recording.
  static void mark(String label, {Duration hold = const Duration(milliseconds: 1200)}) {
    if (!_on) return;
    _label = label;
    _labelUntil = DateTime.now().add(hold);
    event(label);
  }

  static void start() {
    if (_on) return;
    _on = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _startBeat();
    if (!_watching) {
      _lifecycle = AppLifecycleListener(
        onStateChange: (s) {
          _foreground = s == AppLifecycleState.resumed;
          event('app ${s.name}');
          _lastVsync = 0; // (the gap over a trip to the background isn't a hitch)
        },
      );
      _watching = true;
      // Which frames were drawn while something moved: an animation running
      // (a ticker asked for the next frame) or a finger on the screen. The
      // rest are the screen standing still (the camera's own frames).
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        if (!_on) return;
        final b = SchedulerBinding.instance;
        _sync(b.currentSystemFrameTimeStamp.inMicroseconds);
        if (b.transientCallbackCount > 0 || _down > 0) {
          _moving.add(b.currentSystemFrameTimeStamp.inMicroseconds);
          if (_moving.length > 2000) _moving.remove(_moving.first);
        }
      });
      GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
        if (e is PointerDownEvent) _down++;
        if (e is PointerUpEvent || e is PointerCancelEvent) _down = (_down - 1).clamp(0, 99);
      });
    }
  }

  /// How many times the 3D camera has been rendered (whole_body.dart counts):
  /// the speed test reports renders a second per step.
  static int scene3d = 0;

  static bool _watching = false;
  // ignore: unused_field
  static AppLifecycleListener? _lifecycle;
  static int _down = 0;

  /// vsync times (µs) of frames drawn while something moved, until matched.
  static final _moving = <int>{};

  /// Whether the frame of [vsync] was one drawn while something moved
  /// (matched to the nearest ms: the two clocks are the engine's).
  static bool _wasMoving(int vsync) {
    if (_moving.remove(vsync)) return true;
    for (final t in _moving) {
      if ((t - vsync).abs() < 1000) {
        _moving.remove(t);
        return true;
      }
    }
    return false;
  }

  static void stop() {
    if (!_on) return;
    _on = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _beat?.cancel();
  }

  /// Clears the frames and the recent lists (the launch's are kept).
  static void clear() {
    _frames.clear();
    _hitches.clear();
    _stalls.clear();
    _events.clear();
    _lastVsync = 0;
  }

  /// The frames recorded under [label] (a speed test step): build (UI) and
  /// raster (GPU) ms, and vsync time (µs).
  static List<({double ui, double gpu, int vsync, bool moving})> framesOf(String label) => [
    for (final f in _frames)
      if (f.label == label || f.label.startsWith('$label · '))
        (ui: f.build, gpu: f.raster, vsync: f.vsync, moving: f.moving),
  ];

  /// The last second's frames: how many, and the average UI / GPU ms (null
  /// before any). Frame timings arrive in batches, so it lags a little.
  static ({int fps, double ui, double gpu})? lastSecond() {
    if (_frames.isEmpty) return null;
    final end = _frames.last.vsync;
    var n = 0;
    var ui = 0.0, gpu = 0.0;
    for (var i = _frames.length - 1; i >= 0 && _frames[i].vsync > end - 1000000; i--) {
      n++;
      ui += _frames[i].build;
      gpu += _frames[i].raster;
    }
    return (fps: n, ui: ui / n, gpu: gpu / n);
  }

  /// Feeds frame timings as the engine would (tests).
  @visibleForTesting
  static void debugTimings(List<ui.FrameTiming> timings) => _onTimings(timings);

  static void _onTimings(List<ui.FrameTiming> timings) {
    final now = DateTime.now();
    final activity = now.isBefore(_labelUntil) ? _label! : 'idle $screen';
    final t = test;
    final label = t != null ? '$t · $activity' : '$activity${SpeedTests.tag}';
    final budget = _budget;
    for (final t in timings) {
      final vsync = t.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      final moving = _wasMoving(vsync);
      final build = t.buildDuration.inMicroseconds / 1000, raster = t.rasterDuration.inMicroseconds / 1000;
      final wait = t.vsyncOverhead.inMicroseconds / 1000;
      Quality.frame(build, raster, vsync, moving);
      final gap = _lastVsync == 0 ? 0.0 : (vsync - _lastVsync) / 1000;
      _lastVsync = vsync;
      final f = _Frame(label, build, raster, t.totalSpan.inMicroseconds / 1000, vsync, moving, wait, gap);
      _frames.add(f);
      // A hitch: a frame over twice the budget, or a gap in a steady run of
      // frames (the camera's own stream: 2.5x the usual gap, 50 ms+).
      final usual = _usualGap();
      final slow = build > budget * 2 || raster > budget * 2;
      final hole = gap > 50 && gap < 3000 && usual > 0 && usual < 50 && gap > usual * 2.5;
      if (slow || hole) _hitch(f, usual);
      if (gap > 0 && gap < 1000) {
        _gaps.add(gap);
        if (_gaps.length > 30) _gaps.removeAt(0);
      }
    }
    if (_frames.length > _keep) _frames.removeRange(0, _frames.length - _keep);
  }

  // ---- hitches, stalls, events, memory (all timed from the app's start) ----

  static int _lastVsync = 0;
  static final _gaps = <double>[];
  static double _usualGap() {
    if (_gaps.length < 10) return 0;
    final s = [..._gaps]..sort();
    return s[s.length ~/ 2];
  }

  static double get _budget =>
      1000 / (ui.PlatformDispatcher.instance.implicitView?.display.refreshRate ?? 60);

  /// The engine's clock minus the app's (µs), from frames' vsync times: the
  /// largest seen is the closest (a frame callback runs after its vsync).
  static int? _offset;
  static void _sync(int vsyncUs) {
    final o = vsyncUs - LaunchTimer.sinceStartUs;
    if (_offset == null || o > _offset!) _offset = o;
  }

  /// Seconds since the app's code started, for an engine vsync time.
  static String _at(int vsyncUs) => _offset == null ? '?' : _secs(vsyncUs - _offset!);
  static String _now() => _secs(LaunchTimer.sinceStartUs);
  static String _secs(int us) => (us / 1e6).toStringAsFixed(2);

  static final _launchHitches = <String>[], _hitches = <String>[];
  static void _hitch(_Frame f, double usual) {
    final line =
        '${_at(f.vsync)}s ${f.label}: UI ${_n(f.build)} GPU ${_n(f.raster)} wait ${_n(f.wait)}, '
        'gap ${_n(f.gap)} (usual ${_n(usual)})${f.moving ? ' moving' : ''}';
    if (LaunchTimer.sinceStartUs < 20000000 && _launchHitches.length < 60) {
      _launchHitches.add(line);
    } else {
      _add(_hitches, line, 80);
    }
  }

  static final _stalls = <String>[];
  static final _events = <String>[];

  /// Something happened (a screen, a mark, the app going to the background):
  /// listed with its time, to line up with the hitches.
  static void event(String what) {
    if (!_on) return;
    _add(_events, '${_now()}s $what', 120);
  }

  static void _add(List<String> to, String line, int keep) {
    to.add(line);
    if (to.length > keep) to.removeAt(0);
  }

  /// Memory every 5 s (MB, the process's resident size), the last 2 minutes.
  static final _rss = <int>[];
  static int _peakRss = 0;

  static Timer? _beat;
  static final _beatClock = Stopwatch();
  static int _beats = 0;
  static bool _foreground = true;

  /// Every 50 ms: a tick that comes late means the app's thread was busy
  /// (a stall, with or without a frame due). And memory every 100 ticks.
  static void _startBeat() {
    _beat?.cancel();
    _beatClock
      ..reset()
      ..start();
    _beat = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final ms = _beatClock.elapsedMicroseconds / 1000;
      _beatClock
        ..reset()
        ..start();
      if (!_foreground) return;
      if (ms >= 90) {
        final activity = DateTime.now().isBefore(_labelUntil) ? _label! : 'idle $screen';
        final line =
            '${_secs(LaunchTimer.sinceStartUs - (ms * 1000).round())}s busy ${_n(ms - 50)} ms ($activity)';
        if (LaunchTimer.sinceStartUs < 20000000 && _launchStalls.length < 40) {
          _launchStalls.add(line);
        } else {
          _add(_stalls, line, 60);
        }
      }
      if (++_beats % 100 == 1) {
        try {
          final mb = ProcessInfo.currentRss >> 20;
          _peakRss = math.max(_peakRss, mb);
          _rss.add(mb);
          if (_rss.length > 24) _rss.removeAt(0);
        } catch (_) {}
      }
    });
  }

  static final _launchStalls = <String>[];

  /// More lines for the report's header (e.g. the 3D camera's quality).
  static final extras = <String Function()>[];

  static String _n(double v) => v >= 100 ? v.round().toString() : v.toStringAsFixed(1);

  /// The frames as plain text to copy: per activity, then the hitches,
  /// stalls and events on one clock (seconds since the app's code started,
  /// the same as Launch Timing's).
  static String report() {
    final view = ui.PlatformDispatcher.instance.implicitView;
    final hz = view?.display.refreshRate ?? 60;
    final budget = 1000 / hz;
    final b = StringBuffer()
      ..writeln('FRAMES')
      ..writeln(
        'Screen ${view?.physicalSize.width.round()}x${view?.physicalSize.height.round()} '
        '@${view?.devicePixelRatio.toStringAsFixed(2)}x ${hz.round()} Hz (budget ${_n(budget)} ms); '
        'halation ${FilmUniforms.lite ? 'off' : 'on'}; up ${_now()}s',
      )
      ..writeln(SpeedTests.summary);
    for (final extra in extras) {
      b.writeln(extra());
    }
    if (_rss.isNotEmpty) b.writeln('RSS MB every 5 s: ${_rss.join(' ')} (peak $_peakRss)');
    if (_frames.isEmpty) return (b..writeln('No frames yet.')).toString();
    final span = (_frames.last.vsync - _frames.first.vsync) / 1e6;
    var drops = 0;
    final hist = List<int>.filled(7, 0);
    const edges = [8.4, 16.7, 33.4, 50, 100, 250];
    for (final f in _frames) {
      final worst = math.max(f.build, f.raster);
      drops += math.max(0, (worst / budget).ceil() - 1);
      var i = 0;
      while (i < edges.length && worst > edges[i]) {
        i++;
      }
      hist[i]++;
    }
    b
      ..writeln(
        '${_frames.length} frames over ${span.toStringAsFixed(0)}s (${_at(_frames.first.vsync)}-${_at(_frames.last.vsync)}s), '
        '~$drops refreshes missed',
      )
      ..writeln(
        'Slower thread ms: <8 ${hist[0]}, 8-17 ${hist[1]}, 17-33 ${hist[2]}, 33-50 ${hist[3]}, '
        '50-100 ${hist[4]}, 100-250 ${hist[5]}, 250+ ${hist[6]}',
      )
      ..writeln()
      ..writeln(
        'BY ACTIVITY  frames, fps, slow (a thread over budget), hiccups (gap 2.5x usual, worst ms); '
        'UI / GPU / wait (vsync to UI start) as avg/p90/p99/max ms; mov = share drawn while moving',
      );
    final byLabel = <String, List<_Frame>>{};
    for (final f in _frames) {
      (byLabel[f.label] ??= []).add(f);
    }
    // A speed test run's steps in order (baseline first), then the rest by
    // how many frames were slow.
    int? step(String l) => l.startsWith('test ') ? int.tryParse(l.substring(5).split(':').first) : null;
    final labels = byLabel.keys.toList()
      ..sort((a, c) {
        final sa = step(a), sc = step(c);
        if (sa != null || sc != null) {
          if (sa == null) return 1;
          if (sc == null) return -1;
          return sa != sc ? sa.compareTo(sc) : a.compareTo(c);
        }
        return _slow(byLabel[c]!, budget).compareTo(_slow(byLabel[a]!, budget));
      });
    for (final l in labels) {
      final fs = byLabel[l]!;
      final ui_ = [for (final f in fs) f.build], gpu = [for (final f in fs) f.raster];
      final wait = [for (final f in fs) f.wait];
      final (hic, worstGap) = _hiccups(fs);
      final mov = fs.where((f) => f.moving).length * 100 ~/ fs.length;
      final uiAvg = ui_.reduce((a, c) => a + c) / fs.length, gpuAvg = gpu.reduce((a, c) => a + c) / fs.length;
      b.writeln(
        '$l: ${fs.length}f ${_fps(fs)}fps slow ${_slow(fs, budget)} hiccups $hic'
        '${hic > 0 ? ' (${_n(worstGap)})' : ''} mov $mov% '
        '${gpuAvg > uiAvg ? 'GPU' : 'UI'}-bound | UI ${_stats(ui_)} | GPU ${_stats(gpu)} | wait ${_stats(wait)}',
      );
    }
    final worst = [..._frames]
      ..sort((a, c) => math.max(c.build, c.raster).compareTo(math.max(a.build, a.raster)));
    b
      ..writeln()
      ..writeln('WORST FRAMES  (over budget, up to 15) time, activity: UI / GPU / wait / total ms')
      ..writeAll([
        for (final f in worst.take(15).where((f) => math.max(f.build, f.raster) > budget))
          '${_at(f.vsync)}s ${f.label}: ${_n(f.build)} / ${_n(f.raster)} / ${_n(f.wait)} / ${_n(f.total)}\n',
      ])
      ..writeln()
      ..writeln('HITCHES IN THE FIRST 20 S  (a frame over 2x budget, or a gap in steady frames)')
      ..writeln(_launchHitches.isEmpty ? '  none' : _launchHitches.join('\n'))
      ..writeln()
      ..writeln('HITCHES SINCE (last 80)')
      ..writeln(_hitches.isEmpty ? '  none' : _hitches.join('\n'))
      ..writeln()
      ..writeln('STALLS  the app\'s thread busy 40 ms+ (frame due or not); first 20 s, then the last 60')
      ..writeln(_launchStalls.isEmpty ? '  none at launch' : _launchStalls.join('\n'))
      ..writeln(_stalls.isEmpty ? '  none since' : _stalls.join('\n'))
      ..writeln()
      ..writeln('EVENTS  (screens, marks, app state; last 120)')
      ..writeln(_events.isEmpty ? '  none' : _events.join('\n'));
    return b.toString();
  }

  /// Gaps over 2.5x the activity's usual gap (and 50 ms+): the camera's
  /// stream skipping, or the thread too busy to draw.
  static (int, double) _hiccups(List<_Frame> fs) {
    final gaps = [
      for (final f in fs)
        if (f.gap > 0 && f.gap < 1000) f.gap,
    ]..sort();
    if (gaps.length < 10) return (0, 0);
    final usual = gaps[gaps.length ~/ 2];
    if (usual >= 50) return (0, 0);
    final big = gaps.where((g) => g > 50 && g > usual * 2.5).toList();
    return (big.length, big.isEmpty ? 0 : big.last);
  }

  /// A frame misses the screen when either thread takes longer than a
  /// refresh: the two work side by side (the UI thread builds the next
  /// frame while the GPU draws this one), so their sum (the total) running
  /// past the budget only delays a frame, it doesn't drop one.
  static int _slow(List<_Frame> fs, double budget) =>
      fs.where((f) => f.build > budget * 1.05 || f.raster > budget * 1.05).length;

  /// Frames drawn per second while this was going on: from the time between
  /// one frame and the next (gaps over 0.1 s, when nothing moved, left out).
  static String _fps(List<_Frame> fs) {
    var sum = 0, n = 0;
    for (var i = 1; i < fs.length; i++) {
      final gap = fs[i].vsync - fs[i - 1].vsync;
      if (gap > 0 && gap < 100000) {
        sum += gap;
        n++;
      }
    }
    return n == 0 ? '?' : (1e6 * n / sum).round().toString();
  }

  static String _stats(List<double> v) {
    final s = [...v]..sort();
    final avg = s.reduce((a, c) => a + c) / s.length;
    double p(double q) => s[math.min(s.length - 1, (s.length * q).floor())];
    return '${_n(avg)}/${_n(p(.9))}/${_n(p(.99))}/${_n(s.last)}';
  }
}

class _Frame {
  const _Frame(this.label, this.build, this.raster, this.total, this.vsync, this.moving, this.wait, this.gap);

  final String label;
  final double build;
  final double raster;
  final double total;

  /// When its vsync came (µs, the engine's clock).
  final int vsync;

  /// Drawn while something moved (an animation, a finger on the screen).
  final bool moving;

  /// From its vsync to the UI thread starting it (ms): long = the thread
  /// was busy with something else when the frame was due.
  final double wait;

  /// Since the frame before (ms).
  final double gap;
}
