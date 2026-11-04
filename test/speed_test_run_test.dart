import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/diagnostics/speed_test_run.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a made-up swipe is a horizontal drag the tossing way, fast enough to toss', (tester) async {
    double moved = 0;
    double? velocity;
    await tester.pumpWidget(
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => moved += d.primaryDelta ?? 0,
        onHorizontalDragEnd: (d) => velocity = d.primaryVelocity,
        child: const SizedBox.expand(),
      ),
    );
    SpeedTestRun.tossDirection = () => -1;
    // (the swipe times itself on a real stopwatch: frames are pumped until it ends)
    var finished = false;
    final done = SpeedTestRun.swipeForTest(
      0.75,
      const Duration(milliseconds: 320),
    ).then((_) => finished = true);
    await tester.runAsync(() async {
      while (!finished) {
        await Future<void>.delayed(const Duration(milliseconds: 8));
        tester.binding.scheduleFrame();
        await tester.pump();
      }
    });
    await done;
    SpeedTestRun.tossDirection = null;
    expect(moved, lessThan(-300)); // 75% of an 800 px wide test screen, leftwards
    expect(velocity, isNotNull);
    expect(velocity!, lessThan(-1000));
  });

  testWidgets('the live panel: step, countdown, frame rate', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    SpeedTestRun.status.value = const SpeedTestStatus(
      step: 4,
      of: 16,
      stage: 'camera still vf: swipe',
      left: 151,
      live: (fps: 58, ui: 6.4, gpu: 4.9),
    );
    addTearDown(() => SpeedTestRun.status.value = null);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: const ColoredBox(
          color: Color(0xFF3A2416),
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(padding: EdgeInsets.fromLTRB(12, 40, 12, 0), child: SpeedTestBanner()),
          ),
        ),
      ),
    );
    expect(find.text('2:31 left'), findsOneWidget);
    expect(find.textContaining('58 fps'), findsOneWidget);
    final shots = Platform.environment['SHOTS'];
    if (shots == null) return;
    await tester.runAsync(() async {
      final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/speed_test_panel.png').writeAsBytes(png!.buffer.asUint8List());
    });
  });

  test('a moving row: the frame rate while moving and the refreshes dropped', () {
    // 120 Hz: frames every 8.33 ms while moving, one refresh missed in four;
    // still frames (the camera's) in between don't count.
    final frames = <({double ui, double gpu, int vsync, bool moving})>[];
    var t = 0;
    for (var i = 0; i < 40; i++) {
      t += i % 4 == 3 ? 16667 : 8333;
      frames.add((ui: 5, gpu: 4, vsync: t, moving: true));
      if (i % 10 == 0) frames.add((ui: 1, gpu: 9, vsync: t + 1000, moving: false));
    }
    final row = SpeedTestRun.rowForTest('camera swipe', frames);
    final cells = row.substring(17).trim().split(RegExp(r' +'));
    final hz = ui.PlatformDispatcher.instance.implicitView?.display.refreshRate ?? 60;
    if (hz.round() == 120) {
      expect(int.parse(cells[0]), inInclusiveRange(94, 98)); // 39 gaps in ~0.41 s
      expect(cells[1], '20%'); // 10 missed of 49 refreshes
    }
    expect(cells[2], '5.0/5.0');
    expect(row.length, lessThan(68));
  });
}
