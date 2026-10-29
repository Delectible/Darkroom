import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'debug_flags.dart';

/// Win98 Help > Debug > FPS Counter: frames drawn per second, live, with
/// the last 15 s as a bar chart (a line at the screen's refresh rate) and
/// the slowest frame of the last second. Sits bottom left, clear of
/// Flutter's frame graphs (top), so both can be on together.
///
/// Counts frames the engine actually drew (FrameTiming), so a screen with
/// nothing moving reads low: that's Flutter not redrawing, not a stall.
final fpsMeterProvider = NotifierProvider<DebugFlag, bool>(DebugFlag.new);

class FpsMeter extends StatefulWidget {
  const FpsMeter({super.key});

  /// Samples kept: 4 a second for 15 s.
  static const history = 60;

  @override
  State<FpsMeter> createState() => _FpsMeterState();
}

class _FpsMeterState extends State<FpsMeter> {
  /// When each recent frame finished (raster), µs since the epoch, with
  /// its total build + raster time (µs).
  final _frames = <(int, int)>[];
  final _fps = <double>[];
  double _now = 0;
  double _worstMs = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _sample());
  }

  void _timings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      _frames.add((t.timestampInMicroseconds(ui.FramePhase.rasterFinish), t.totalSpan.inMicroseconds));
    }
  }

  void _sample() {
    final now = DateTime.now().microsecondsSinceEpoch;
    _frames.removeWhere((f) => f.$1 < now - 1000000);
    _now = _frames.length.toDouble();
    _worstMs = _frames.fold<int>(0, (m, f) => math.max(m, f.$2)) / 1000;
    _fps.add(_now);
    if (_fps.length > FpsMeter.history) _fps.removeAt(0);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rate = View.of(context).display.refreshRate.clamp(30.0, 240.0);
    final good = _now >= rate * 0.9;
    final colour = good
        ? const Color(0xFF6BFF7A)
        : _now >= rate * 0.5
        ? const Color(0xFFFFD24A)
        : const Color(0xFFFF6B5A);
    const ink = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      color: Color(0xCCFFFFFF),
      decoration: TextDecoration.none,
      height: 1.2,
    );
    return IgnorePointer(
      child: Container(
        width: 168,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _now.toStringAsFixed(0),
                  style: ink.copyWith(fontSize: 22, fontWeight: FontWeight.w700, color: colour),
                ),
                const SizedBox(width: 4),
                const Text('FPS', style: ink),
                const Spacer(),
                Text('/${rate.round()} Hz', style: ink.copyWith(color: const Color(0x99FFFFFF))),
              ],
            ),
            Text('slowest ${_worstMs.toStringAsFixed(1)} ms', style: ink.copyWith(fontSize: 10)),
            const SizedBox(height: 4),
            SizedBox(
              height: 40,
              width: double.infinity,
              child: CustomPaint(painter: _FpsChart(List.of(_fps), rate)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One bar per quarter second, coloured like the readout; a dashed line at
/// the refresh rate.
class _FpsChart extends CustomPainter {
  _FpsChart(this.fps, this.rate);

  final List<double> fps;
  final double rate;

  @override
  void paint(Canvas canvas, Size size) {
    final top = rate * 1.1;
    final w = size.width / FpsMeter.history;
    final x0 = size.width - fps.length * w;
    final bar = Paint();
    for (var i = 0; i < fps.length; i++) {
      final v = fps[i];
      bar.color = v >= rate * 0.9
          ? const Color(0xFF6BFF7A)
          : v >= rate * 0.5
          ? const Color(0xFFFFD24A)
          : const Color(0xFFFF6B5A);
      final h = (v / top).clamp(0.0, 1.0) * size.height;
      canvas.drawRect(Rect.fromLTWH(x0 + i * w, size.height - h, math.max(1, w - 0.6), h), bar);
    }
    final y = size.height - rate / top * size.height;
    final line = Paint()
      ..color = const Color(0x80FFFFFF)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 3, size.width), y), line);
    }
  }

  @override
  bool shouldRepaint(_FpsChart old) => true;
}
