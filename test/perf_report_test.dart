import 'dart:ui' as ui;

import 'package:darkroom/core/diagnostics/perf_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

ui.FrameTiming _frame(int vsyncUs, double uiMs, double gpuMs) {
  final buildStart = vsyncUs + 500;
  final buildEnd = buildStart + (uiMs * 1000).round();
  final rasterEnd = buildEnd + (gpuMs * 1000).round();
  return ui.FrameTiming(
    vsyncStart: vsyncUs,
    buildStart: buildStart,
    buildFinish: buildEnd,
    rasterStart: buildEnd,
    rasterFinish: rasterEnd,
    rasterFinishWallTime: rasterEnd,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('report lists activities, hitches and events', () {
    PerfRecorder.start();
    addTearDown(PerfRecorder.stop);
    expect(PerfRecorder.report(), contains('No frames yet.'));
    // A steady 30 fps camera stream with one 150 ms hole and one slow frame.
    var t = 1000000;
    final frames = <ui.FrameTiming>[];
    for (var i = 0; i < 60; i++) {
      t += i == 40 ? 150000 : 33333;
      frames.add(_frame(t, i == 20 ? 60 : 3, 5));
    }
    PerfRecorder.mark('launch: test mark');
    PerfRecorder.debugTimings(frames);
    final r = PerfRecorder.report();
    expect(r, contains('BY ACTIVITY'));
    expect(r, contains('launch: test mark: 60f'));
    expect(r, contains('hiccups 1 (150)'));
    expect(r, contains('gap 150'));
    expect(r, contains('UI 60.0'));
    expect(r, contains('s launch: test mark'));
  });
}
