import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/features/help/gesture_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every gesture demo paints through its whole loop without throwing.
/// `SHOTS=dir` saves the cards as frames (`gesture_NNN.png`) for a GIF.
void main() {
  final shots = Platform.environment['SHOTS'];

  testWidgets('gesture demos loop', (tester) async {
    tester.view.physicalSize = const Size(1040, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    Widget grid(double t) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: key,
        child: Material(
          color: const Color(0xFF0E0E12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 20,
              children: [
                for (final m in GestureMove.values)
                  SizedBox(
                    width: 152,
                    child: GestureCard(move: m, size: 96, t: t),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    const frames = 52;
    for (var i = 0; i < frames; i++) {
      await tester.pumpWidget(grid(i / frames));
      expect(tester.takeException(), isNull);
      if (shots == null) continue;
      await tester.runAsync(() async {
        final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await ro.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$shots/gesture_${i.toString().padLeft(3, '0')}.png',
        ).writeAsBytes(png!.buffer.asUint8List());
      });
    }
    // And the live one ticks.
    await tester.pumpWidget(const MaterialApp(home: GestureDemo(move: GestureMove.swap)));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
