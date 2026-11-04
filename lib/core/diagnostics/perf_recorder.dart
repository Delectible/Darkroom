import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import '../shaders/shader_library.dart' show FilmUniforms;
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
  static String screen = 'camera';
  static DateTime _labelUntil = DateTime(0);

  /// Labels the frames of the next [hold] (an animation, a dialog opening).
  /// Cheap when not recording.
  static void mark(String label, {Duration hold = const Duration(milliseconds: 1200)}) {
    if (!_on) return;
    _label = label;
    _labelUntil = DateTime.now().add(hold);
  }

  static void start() {
    if (_on) return;
    _on = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    if (!_watching) {
      _watching = true;
      // Which frames were drawn while something moved: an animation running
      // (a ticker asked for the next frame) or a finger on the screen. The
      // rest are the screen standing still (the camera's own frames).
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        if (!_on) return;
        final b = SchedulerBinding.instance;
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
  }

  static void clear() => _frames.clear();

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

  static void _onTimings(List<ui.FrameTiming> timings) {
    final now = DateTime.now();
    final activity = now.isBefore(_labelUntil) ? _label! : 'idle $screen';
    final t = test;
    final label = t != null ? '$t · $activity' : '$activity${SpeedTests.tag}';
    for (final t in timings) {
      _frames.add(
        _Frame(
          label,
          t.buildDuration.inMicroseconds / 1000,
          t.rasterDuration.inMicroseconds / 1000,
          t.totalSpan.inMicroseconds / 1000,
          t.timestampInMicroseconds(ui.FramePhase.vsyncStart),
          _wasMoving(t.timestampInMicroseconds(ui.FramePhase.vsyncStart)),
        ),
      );
    }
    if (_frames.length > _keep) _frames.removeRange(0, _frames.length - _keep);
  }

  /// A plain-text summary to copy and send: per activity, how many frames
  /// missed the display's budget and which thread was the bottleneck.
  /// More lines for the report's header (e.g. the 3D camera's quality).
  static final extras = <String Function()>[];

  static String report() {
    final view = ui.PlatformDispatcher.instance.implicitView;
    final hz = view?.display.refreshRate ?? 60;
    final budget = 1000 / hz;
    final b = StringBuffer()
      ..writeln('Darkroom performance report')
      ..writeln('${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln(
        'Screen ${view?.physicalSize.width.round()}x${view?.physicalSize.height.round()} '
        '@${view?.devicePixelRatio.toStringAsFixed(2)}x, ${hz.round()} Hz (budget ${budget.toStringAsFixed(1)} ms)',
      )
      ..writeln('Viewfinder halation: ${FilmUniforms.lite ? 'off' : 'on'}')
      ..writeln(SpeedTests.summary);
    for (final extra in extras) {
      b.writeln(extra());
    }
    b
      ..writeln('Frames recorded: ${_frames.length}')
      ..writeln()
      ..writeln('activity: frames, fps, slow (UI or GPU over budget), UI avg/p90/max, GPU avg/p90/max (ms)');
    if (_frames.isEmpty) {
      return (b..writeln('(nothing yet: turn the recorder on, then use the app)')).toString();
    }
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
      final ui_ = fs.map((f) => f.build).toList(), gpu = fs.map((f) => f.raster).toList();
      b.writeln(
        '$l: ${fs.length}, ${_fps(fs)} fps, ${_slow(fs, budget)} slow, '
        'UI ${_stats(ui_)}, GPU ${_stats(gpu)}',
      );
    }
    final worst = [..._frames]..sort((a, c) => c.total.compareTo(a.total));
    b
      ..writeln()
      ..writeln('Worst frames (activity: UI / GPU / total ms):');
    for (final f in worst.take(12)) {
      b.writeln(
        '${f.label}: ${f.build.toStringAsFixed(1)} / ${f.raster.toStringAsFixed(1)} / ${f.total.toStringAsFixed(1)}',
      );
    }
    return b.toString();
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
    final p90 = s[math.min(s.length - 1, (s.length * 0.9).floor())];
    return '${avg.toStringAsFixed(1)}/${p90.toStringAsFixed(1)}/${s.last.toStringAsFixed(1)}';
  }
}

class _Frame {
  const _Frame(this.label, this.build, this.raster, this.total, this.vsync, this.moving);

  final String label;
  final double build;
  final double raster;
  final double total;

  /// When its vsync came (µs, the engine's clock).
  final int vsync;

  /// Drawn while something moved (an animation, a finger on the screen).
  final bool moving;
}
