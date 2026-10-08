import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

/// Records every frame's timings on the phone (Win98 Help > Debug >
/// Performance Recorder), labelled with what the app was doing (`mark`), so
/// a slow device can say exactly what is slow: the UI thread (Dart: build,
/// layout, painting the layer tree) or the raster thread (the GPU drawing it:
/// shaders, blurs, big images).
class PerfRecorder {
  PerfRecorder._();

  static bool _on = false;
  static bool get recording => _on;

  static final List<_Frame> _frames = [];
  static const _keep = 4000;

  static String? _label;
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
  }

  static void stop() {
    if (!_on) return;
    _on = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  static void clear() => _frames.clear();

  static void _onTimings(List<ui.FrameTiming> timings) {
    final now = DateTime.now();
    final label = now.isBefore(_labelUntil) ? _label! : 'other';
    for (final t in timings) {
      _frames.add(
        _Frame(
          label,
          t.buildDuration.inMicroseconds / 1000,
          t.rasterDuration.inMicroseconds / 1000,
          t.totalSpan.inMicroseconds / 1000,
        ),
      );
    }
    if (_frames.length > _keep) _frames.removeRange(0, _frames.length - _keep);
  }

  /// A plain-text summary to copy and send: per activity, how many frames
  /// missed the display's budget and which thread was the bottleneck.
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
      ..writeln('Frames recorded: ${_frames.length}')
      ..writeln()
      ..writeln('activity: frames, slow (>budget), UI avg/p90/max, GPU avg/p90/max (ms)');
    if (_frames.isEmpty) {
      return (b..writeln('(nothing yet: turn the recorder on, then use the app)')).toString();
    }
    final byLabel = <String, List<_Frame>>{};
    for (final f in _frames) {
      (byLabel[f.label] ??= []).add(f);
    }
    final labels = byLabel.keys.toList()
      ..sort((a, c) => _slow(byLabel[c]!, budget).compareTo(_slow(byLabel[a]!, budget)));
    for (final l in labels) {
      final fs = byLabel[l]!;
      final ui_ = fs.map((f) => f.build).toList(), gpu = fs.map((f) => f.raster).toList();
      b.writeln(
        '$l: ${fs.length}, ${_slow(fs, budget)} slow, '
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

  static int _slow(List<_Frame> fs, double budget) => fs.where((f) => f.total > budget * 1.05).length;

  static String _stats(List<double> v) {
    final s = [...v]..sort();
    final avg = s.reduce((a, c) => a + c) / s.length;
    final p90 = s[math.min(s.length - 1, (s.length * 0.9).floor())];
    return '${avg.toStringAsFixed(1)}/${p90.toStringAsFixed(1)}/${s.last.toStringAsFixed(1)}';
  }
}

class _Frame {
  const _Frame(this.label, this.build, this.raster, this.total);

  final String label;
  final double build;
  final double raster;
  final double total;
}
