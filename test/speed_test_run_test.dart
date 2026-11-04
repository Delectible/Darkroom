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
}
