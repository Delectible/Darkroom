import 'package:darkroom/core/diagnostics/speed_test_run.dart';
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
}
