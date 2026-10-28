import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/startup/launch_curtain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The launch curtain: up for at least its minimum with its line, held
/// while the app isn't ready, then faded away for good (touches reach the
/// app again). `SHOTS=dir` saves it.
void main() {
  testWidgets('holds until ready, then fades away', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);
    var ready = false;
    var taps = 0;
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: LaunchCurtain(
            isReady: () => ready,
            line: 1,
            child: Scaffold(
              body: Center(
                child: TextButton(onPressed: () => taps++, child: const Text('Camera')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(const AssetImage('assets/artwork/rabbit_mark.png'), key.currentContext!),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(LaunchCurtain.lines[1]), findsOneWidget);
    final shots = Platform.environment['SHOTS'];
    if (shots != null) {
      await tester.runAsync(() async {
        final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final png = await (await ro.toImage(pixelRatio: 1)).toByteData(format: ui.ImageByteFormat.png);
        await File('$shots/launch_curtain.png').writeAsBytes(png!.buffer.asUint8List());
      });
    }
    // Not ready: still up well past the minimum, and the app can't be touched.
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Camera'), warnIfMissed: false);
    expect(taps, 0);
    expect(find.text(LaunchCurtain.lines[1]), findsOneWidget);
    ready = true;
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.text(LaunchCurtain.lines[1]), findsNothing);
    await tester.tap(find.text('Camera'));
    expect(taps, 1);
  });

  testWidgets('gives up waiting after its maximum', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LaunchCurtain(isReady: () => false, line: 0, child: const SizedBox()),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.text(LaunchCurtain.lines[0]), findsNothing);
  });
}
