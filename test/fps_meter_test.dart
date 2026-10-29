import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/diagnostics/fps_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Debug > FPS Counter draws its readout and chart and keeps sampling
/// without errors. `SHOTS=dir` saves it.
void main() {
  testWidgets('FPS counter runs', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: ColoredBox(
          color: const Color(0xFF335577),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: RepaintBoundary(key: key, child: const FpsMeter()),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('FPS'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final shots = Platform.environment['SHOTS'];
    if (shots != null) {
      await tester.runAsync(() async {
        final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final png = await (await ro.toImage(pixelRatio: 3)).toByteData(format: ui.ImageByteFormat.png);
        await File('$shots/fps_meter.png').writeAsBytes(png!.buffer.asUint8List());
      });
    }
  });
}
