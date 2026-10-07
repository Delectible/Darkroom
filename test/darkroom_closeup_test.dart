import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/features/corkboard/presentation/corkboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The darkroom close-up (tap a tray): a print in the developer, at
/// Pixel 9 Pro size, with the stage spelled out. `SHOTS=dir` saves a PNG.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  testWidgets('darkroom close-up', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('closeup');
    final pic = img.Image(width: 320, height: 400);
    for (final p in pic) {
      p
        ..r = 60 + p.x % 160
        ..g = 90 + p.y % 120
        ..b = 140;
    }
    final thumb = '${dir.path}/t.jpg';
    File(thumb).writeAsBytesSync(img.encodeJpg(pic));
    final now = DateTime(2026, 10, 7, 12);
    final item = MediaItem(
      id: 'p1',
      cameraId: 'portra400',
      kind: MediaKind.photo,
      status: MediaStatus.ready,
      fileName: 'ROLL001_07.JPG',
      capturedAt: now.subtract(const Duration(minutes: 1)),
      readyAt: now.add(const Duration(minutes: 4)),
      thumbPath: thumb,
      outputPath: thumb,
      width: 4,
      height: 5,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filmItemsProvider.overrideWith((ref) => Stream.value([item])),
          secondTickerProvider.overrideWith((ref) => Stream.value(now)),
        ],
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Builder(
              builder: (context) => Scaffold(
                backgroundColor: const Color(0xFFB4875A),
                body: Center(
                  child: TextButton(
                    onPressed: () => showDarkroomCloseUp(context, 'p1'),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Developing'), findsOneWidget);
    if (shots != null) {
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await ro.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$shots/darkroom_closeup.png').writeAsBytes(png!.buffer.asUint8List());
      });
    }
    // Tapping anywhere goes back to the board.
    await tester.tapAt(const Offset(20, 20));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.textContaining('Developing'), findsNothing);
  });
}
