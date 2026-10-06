import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:darkroom/core/processing/instant_frame.dart';
import 'package:darkroom/features/corkboard/presentation/instant_print.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The instant frame is off-white with a fine embossed texture, like a real
/// print (scans: ~220-243, texture std ~1-2 levels), not flat paper-white.
void main() {
  test('paper texture: off-white, faint, seamless', () {
    final px = PaperTexture.pixels();
    const n = PaperTexture.size;
    var sum = 0.0, sum2 = 0.0;
    for (var i = 0; i < n * n; i++) {
      final v = px[i * 4 + 1].toDouble();
      sum += v;
      sum2 += v * v;
    }
    final mean = sum / (n * n), sd = math.sqrt(sum2 / (n * n) - mean * mean);
    expect(mean, inInclusiveRange(220, 242));
    expect(sd, inInclusiveRange(0.8, 6));
    // Seamless: the wrap edge is no rougher than the rest.
    var seam = 0.0, inner = 0.0;
    for (var y = 0; y < n; y++) {
      seam += (px[(y * n + n - 1) * 4 + 1] - px[(y * n) * 4 + 1]).abs();
      inner += (px[(y * n + 100) * 4 + 1] - px[(y * n + 101) * 4 + 1]).abs();
    }
    expect(seam, lessThan(inner * 1.6 + n));
  });

  testWidgets('framed print renders with the texture', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async => PaperTexture.loaded.value = await PaperTexture.image());
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Material(
          color: const Color(0xFF6B4A2E),
          child: Center(
            child: SizedBox(
              width: 340,
              child: RepaintBoundary(
                key: boundary,
                child: const InstantPrint(
                  shadow: false,
                  note: 'the lake, 2026',
                  picture: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF1C2A3A), Color(0xFFD9CDB0)]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final shots = Platform.environment['SHOTS'];
    if (shots != null) {
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await ro.toImage(pixelRatio: 3.1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$shots/instant_frame.png').writeAsBytes(png!.buffer.asUint8List());
      });
    }
  });
}
