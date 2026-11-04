import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// How sharply the 3D body is drawn on phones with little RAM, steered by
/// how long frames really take while it moves (a swap). Flutter Scene's own
/// adaptive quality judged by the time between frames, so at 60 Hz (which
/// those phones run at) it could step down but never back up: this reads
/// each frame's own build and raster time instead.
///
/// The body's draw scale is [base] (its width capped at 1080 px) times
/// [detail] (1 down to [floor], never under 648 px wide); the labels on it
/// that are drawn as widgets (FLIP, the format dial) soften to match
/// ([textBlur]), so they don't look sharper than the body under them.
class BodyQuality {
  BodyQuality._();

  /// The steered part: 1 = full, down to [floor].
  static final detail = ValueNotifier<double>(1);

  /// The body's draw scale before [detail] (1 except on low-RAM phones with
  /// screens wider than 1080 px).
  static double base = 1;

  /// Lowest [detail]: 60%, or more on smaller screens so the body is never
  /// drawn less than 648 px wide (60% of 1080).
  static double floor = 0.6;

  static bool _on = false;
  static bool _moving = false;
  static final _frames = <int>[];
  static int _cooldown = 0;

  /// Frames per verdict (about half a second of a swap).
  static const window = 30;

  /// A frame over this (build or raster, µs) missed 60 Hz.
  static const _late = 16700;

  /// Turns the steering on for a low-RAM phone whose screen is [px] wide.
  static void enable(double px) {
    if (_on) return;
    _on = true;
    base = px > 1080 ? 1080 / px : 1;
    floor = math.min(1, math.max(0.6, 648 / (px * base)));
    SchedulerBinding.instance.addTimingsCallback(_timings);
  }

  /// The body is being swapped (only those frames count).
  static void moving(bool on) {
    _moving = on && _on;
    if (!_moving) _frames.clear();
  }

  static void _timings(List<FrameTiming> timings) {
    if (!_moving) return;
    for (final t in timings) {
      _frames.add(math.max(t.buildDuration.inMicroseconds, t.rasterDuration.inMicroseconds));
    }
    if (_frames.length < window) return;
    final late = _frames.where((f) => f > _late).length;
    final mean = _frames.reduce((a, b) => a + b) / _frames.length;
    _frames.clear();
    final d = detail.value;
    if (late >= 6) {
      // a fifth of the frames missed: a step down (15%), then a pause
      // before it may climb again
      _cooldown = 2;
      detail.value = math.max(floor, d * 0.85);
      return;
    }
    if (_cooldown > 0) {
      _cooldown--;
      return;
    }
    // every frame on time with room to spare: a step back up
    if (late == 0 && mean < 10000 && d < 1) detail.value = math.min(1, d / 0.85);
  }

  /// The blur (logical px) that makes a crisp label read like the body
  /// drawn at [base] x [detail] on a screen of [dpr].
  static double textBlur(double dpr) {
    final s = base * detail.value;
    if (s >= 0.8) return 0;
    return (1 / s - 1) * 0.5 / dpr;
  }
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
