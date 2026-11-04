import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../core/diagnostics/perf_recorder.dart';

/// How sharply the 3D body is drawn, and on phones with little RAM, steered
/// by how long frames really take while it moves (a swap). Flutter Scene's
/// own adaptive quality judged by the time between frames, so at 60 Hz
/// (which those phones run at) it could step down but never back up: this
/// reads each frame's own build and raster time instead.
///
/// The body's draw scale is [base] (low RAM: its width capped at 1080 px;
/// screens >= 1100 px: 90%) times [detail] (1 down to [floor], never under
/// 648 px wide; only ever below 1 on low RAM). The labels on it that are
/// widgets (FLIP, the format dial) soften to match ([textBlur]).
///
/// It keeps stats for Debug > 3D Quality Stats (and the Performance Report).
class BodyQuality {
  BodyQuality._();

  /// The steered part: 1 = full, down to [floor].
  static final detail = ValueNotifier<double>(1);

  /// The body's draw scale before [detail].
  static double base = 1;

  /// Lowest [detail] (1 where nothing is steered).
  static double floor = 1;

  /// The screen's width in pixels.
  static double screenPx = 0;

  /// Whether [detail] is steered (low RAM).
  static bool get steering => _on;

  static bool _on = false;
  static bool _started = false;
  static bool _moving = false;
  static final _frames = <int>[];
  static int _cooldown = 0;

  /// Frames per verdict (about half a second of a swap).
  static const window = 30;

  /// A frame over this (build or raster, µs) missed 60 Hz.
  static const late = 16700;

  /// Smallest width (px) the body is ever drawn at.
  static const minWidth = 648.0;

  /// Sets the draw scale for a screen [px] wide; [low] RAM steers it.
  /// (Once per run: both bodies share it.)
  static void init({required double px, required bool low}) {
    if (_started) return;
    _started = true;
    screenPx = px;
    _clock.start();
    _levelFrom = 0;
    if (low) {
      _on = true;
      base = px > 1080 ? 1080 / px : 1;
      floor = math.min(1, math.max(0.6, minWidth / (px * base)));
    } else {
      base = px >= 1100 ? 0.9 : 1;
      floor = 1;
    }
    SchedulerBinding.instance.addTimingsCallback(_timings);
    PerfRecorder.extras.add(summary);
  }

  /// The body is being swapped (only those frames count).
  static void moving(bool on) {
    if (on && !_moving) _swaps++;
    _moving = on;
    if (!on) _frames.clear();
    final now = _clock.elapsedMicroseconds;
    if (on) {
      _swapFrom = now;
    } else if (_swapFrom != null) {
      _level(_pct).swapping += now - _swapFrom!;
      _swapFrom = null;
    }
  }

  // ---- stats -----------------------------------------------------------------

  static final _clock = Stopwatch();
  static int _levelFrom = 0;
  static int? _swapFrom;
  static int _swaps = 0;
  static int _windows = 0;
  static int _downs = 0;
  static int _ups = 0;
  static final _levels = <int, _Level>{};
  static final _events = <_Event>[];

  static int get _pct => (detail.value * 100).round();
  static _Level _level(int pct) => _levels.putIfAbsent(pct, _Level.new);

  static void _set(double to, int lateFrames, double meanUs) {
    final now = _clock.elapsedMicroseconds;
    final from = _pct;
    _level(from).time += now - _levelFrom;
    if (_swapFrom != null) {
      _level(from).swapping += now - _swapFrom!;
      _swapFrom = now;
    }
    _levelFrom = now;
    detail.value = to;
    _events.add(_Event(now, from, _pct, lateFrames, meanUs));
    if (_events.length > 40) _events.removeAt(0);
    to < from / 100 ? _downs++ : _ups++;
    PerfRecorder.mark('3D quality $from% -> $_pct%', hold: const Duration(seconds: 2));
  }

  static void _timings(List<FrameTiming> timings) {
    if (!_moving) return;
    final level = _level(_pct);
    for (final t in timings) {
      final us = math.max(t.buildDuration.inMicroseconds, t.rasterDuration.inMicroseconds);
      _frames.add(us);
      level
        ..frames += 1
        ..frameUs += us
        ..late += us > late ? 1 : 0;
    }
    if (_frames.length < window) return;
    final lateFrames = _frames.where((f) => f > late).length;
    final mean = _frames.reduce((a, b) => a + b) / _frames.length;
    _frames.clear();
    _windows++;
    if (!_on) return;
    final d = detail.value;
    if (lateFrames >= 6) {
      // a fifth of the frames missed: a step down (15%), then a pause
      // before it may climb again
      _cooldown = 2;
      final to = math.max(floor, d * 0.85);
      if (to < d) _set(to, lateFrames, mean);
      return;
    }
    if (_cooldown > 0) {
      _cooldown--;
      return;
    }
    // every frame on time with room to spare: a step back up
    if (lateFrames == 0 && mean < 10000 && d < 1) _set(math.min(1, d / 0.85), lateFrames, mean);
  }

  /// The blur (logical px) that makes a crisp label read like the body
  /// drawn at [base] x [detail] on a screen of [dpr].
  static double textBlur(double dpr) {
    final s = base * detail.value;
    if (s >= 0.8) return 0;
    return (1 / s - 1) * 0.5 / dpr;
  }

  // ---- reports ---------------------------------------------------------------

  static String _w(double scale) => '${(screenPx * scale).round()} px wide';
  static String _p(double v) => '${(v * 100).round()}%';

  static String _dur(int us) {
    final s = us ~/ 1000000;
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    return m < 60 ? '${m}m ${s % 60}s' : '${m ~/ 60}h ${m % 60}m';
  }

  /// One line for the Performance Report.
  static String summary() =>
      '3D quality: ${_on ? 'steered (low RAM)' : 'fixed'}, now ${_p(base * detail.value)} '
      '(${_w(base * detail.value)}), floor ${_p(base * floor)}, $_downs down / $_ups up, $_swaps swaps';

  /// Debug > 3D Quality Stats.
  static String report() {
    if (!_started) return 'The 3D cameras haven\'t loaded this run (Fancy graphics off, or no 3D here).';
    final now = _clock.elapsedMicroseconds;
    final b = StringBuffer()
      ..writeln('3D CAMERA QUALITY')
      ..writeln()
      ..writeln('Screen: ${screenPx.round()} px wide')
      ..writeln(
        _on
            ? 'Mode: steered (this phone is short of RAM: the 3D body gets softer when swaps stutter, '
                  'and sharpens again when they don\'t)'
            : 'Mode: fixed (enough RAM: never steered)',
      )
      ..writeln('Normal: ${_p(base)} of the screen (${_w(base)})');
    if (_on) {
      b
        ..writeln(
          'Lowest: ${_p(floor)} of normal = ${_p(base * floor)} (${_w(base * floor)}; never under '
          '${minWidth.round()} px)',
        )
        ..writeln(
          'Now: ${_p(detail.value)} of normal = ${_p(base * detail.value)} (${_w(base * detail.value)})',
        );
    }
    b
      ..writeln()
      ..writeln('THIS SESSION (${_dur(now)})')
      ..writeln('Swaps: $_swaps, judged in $_windows checks of $window frames')
      ..writeln('Steps: $_downs down, $_ups up');
    final levels = _levels.keys.toList()..sort((a, c) => c.compareTo(a));
    if (!levels.contains(_pct)) levels.add(_pct);
    for (final pct in levels) {
      final l = _level(pct);
      final time = l.time + (pct == _pct ? now - _levelFrom : 0);
      final swapping = l.swapping + (pct == _pct && _swapFrom != null ? now - _swapFrom! : 0);
      b
        ..writeln()
        ..writeln('At $pct% (${_w(base * pct / 100)}): ${_dur(time)}, swapping ${_dur(swapping)}');
      if (l.frames > 0) {
        b.writeln(
          '  ${l.frames} frames, average ${(l.frameUs / l.frames / 1000).toStringAsFixed(1)} ms, '
          '${(l.late * 100 / l.frames).toStringAsFixed(0)}% late (over ${(late / 1000).toStringAsFixed(1)} ms)',
        );
      }
    }
    if (_events.isNotEmpty) {
      b
        ..writeln()
        ..writeln('CHANGES (latest last)');
      for (final e in _events) {
        b.writeln(
          '  ${_dur(e.at)} in: ${e.from}% -> ${e.to}% '
          '(${e.late} of $window frames late, average ${(e.meanUs / 1000).toStringAsFixed(1)} ms)',
        );
      }
    }
    b
      ..writeln()
      ..writeln('HOW IT DECIDES')
      ..writeln(
        'Only while you swap cameras (the only time the 3D body keeps redrawing). Every $window frames: '
        '6 or more late = 15% softer, then 2 checks\' pause; none late and under 10 ms on average = '
        '15% sharper. Only the 3D body (and FLIP / the format label on it) changes: the viewfinder, '
        'text and buttons stay sharp. It starts at normal each time the app opens.',
      );
    return b.toString();
  }
}

class _Level {
  int time = 0, swapping = 0, frames = 0, frameUs = 0, late = 0;
}

class _Event {
  _Event(this.at, this.from, this.to, this.late, this.meanUs);

  final int at, from, to, late;
  final double meanUs;
}

/// Builds [builder] with [BodyQuality.textBlur] for this screen, again
/// whenever the body's detail steps.
class BodyQualityText extends StatelessWidget {
  const BodyQualityText({super.key, required this.builder});

  final Widget Function(BuildContext context, double blur) builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: BodyQuality.detail,
    builder: (context, _, _) =>
        builder(context, BodyQuality.textBlur(MediaQuery.devicePixelRatioOf(context))),
  );
}
