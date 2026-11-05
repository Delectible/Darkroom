import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../core/diagnostics/perf_recorder.dart';
import '../../../core/performance/quality.dart';

/// How sharply the 3D body is drawn.
///
/// The body's draw scale is [base] (low RAM: its width capped at 1080 px;
/// screens >= 1100 px: 90%) times [detail] (1 down to [floor], never under
/// 648 px wide), which follows the quality manager's 3D steps
/// (Quality.scale3d). The labels on it that are widgets (FLIP, the format
/// dial) soften to match ([textBlur]).
///
/// It keeps stats for Debug > Performance Report.
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

  /// Whether [detail] follows the quality manager (once the 3D is in).
  static bool get steering => _on;

  static bool _on = false;
  static bool _started = false;
  static bool _moving = false;

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
      base = px > 1080 ? 1080 / px : 1;
    } else {
      base = px >= 1100 ? 0.9 : 1;
    }
    floor = math.min(1, math.max(0.6, minWidth / (px * base)));
    // The quality manager steers it now, on every phone (2.0.15): from how
    // all moving frames run, not only swaps on low-RAM phones.
    _on = true;
    void follow() {
      final to = math.max(floor, Quality.scale3d.value);
      if (to != detail.value) _set(to);
    }

    Quality.scale3d.addListener(follow);
    follow();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    PerfRecorder.extras.add(summary);
  }

  /// The body is being swapped (only those frames count).
  static void moving(bool on) {
    if (on && !_moving) _swaps++;
    _moving = on;
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
  static int _downs = 0;
  static int _ups = 0;
  static final _levels = <int, _Level>{};
  static final _events = <_Event>[];

  static int get _pct => (detail.value * 100).round();
  static _Level _level(int pct) => _levels.putIfAbsent(pct, _Level.new);

  static void _set(double to) {
    final now = _clock.elapsedMicroseconds;
    final from = _pct;
    _level(from).time += now - _levelFrom;
    if (_swapFrom != null) {
      _level(from).swapping += now - _swapFrom!;
      _swapFrom = now;
    }
    _levelFrom = now;
    detail.value = to;
    _events.add(_Event(now, from, _pct));
    if (_events.length > 40) _events.removeAt(0);
    to < from / 100 ? _downs++ : _ups++;
    PerfRecorder.mark('3D quality $from% -> $_pct%', hold: const Duration(seconds: 2));
  }

  static void _timings(List<FrameTiming> timings) {
    if (!_moving) return;
    final level = _level(_pct);
    for (final t in timings) {
      final us = math.max(t.buildDuration.inMicroseconds, t.rasterDuration.inMicroseconds);
      level
        ..frames += 1
        ..frameUs += us
        ..late += us > late ? 1 : 0;
    }
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
      '3D quality: set by the quality manager, now ${_p(base * detail.value)} '
      '(${_w(base * detail.value)}), floor ${_p(base * floor)}, $_downs down / $_ups up, $_swaps swaps';

  /// Debug > Performance Report (3D quality).
  static String report() {
    if (!_started) return 'The 3D cameras haven\'t loaded this run (Fancy graphics off, or no 3D here).';
    final now = _clock.elapsedMicroseconds;
    final b = StringBuffer()
      ..writeln('Screen: ${screenPx.round()} px wide')
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
      ..writeln('Swaps: $_swaps')
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
        b.writeln('  ${_dur(e.at)} in: ${e.from}% -> ${e.to}%');
      }
    }
    b
      ..writeln()
      ..writeln('HOW IT DECIDES')
      ..writeln(
        'The quality manager (Debug > Quality Manager) sets it from how moving frames run: its 3D '
        'steps draw the body at 90%, 80% or 70%. Only the 3D body (and FLIP / the format label on it) '
        'changes: the viewfinder, text and buttons stay sharp. The frame times above are while you '
        'swap cameras.',
      );
    return b.toString();
  }
}

class _Level {
  int time = 0, swapping = 0, frames = 0, frameUs = 0, late = 0;
}

class _Event {
  _Event(this.at, this.from, this.to);

  final int at, from, to;
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
