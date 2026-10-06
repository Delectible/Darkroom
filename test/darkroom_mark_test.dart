import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/theme/darkroom_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rabbit mark paints at small and large sizes, flat and RGB-split.
void main() {
  testWidgets('rabbit mark', (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: const ColoredBox(
          color: Color(0xFF2A2420),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(
              spacing: 12,
              children: [
                DarkroomMark(size: 14, color: Color(0xCC2B4C8C)),
                DarkroomMark(size: 16, color: Color(0x77000000)),
                DarkroomMark(size: 48, color: Color(0xFFF3E3C8)),
                DarkroomMark(size: 96, color: Colors.white, rgbSplit: true),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final shots = Platform.environment['SHOTS'];
    if (shots != null) {
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final png = await (await ro.toImage(pixelRatio: 2)).toByteData(format: ui.ImageByteFormat.png);
        await File('$shots/rabbit_mark.png').writeAsBytes(png!.buffer.asUint8List());
      });
    }
  });
}
