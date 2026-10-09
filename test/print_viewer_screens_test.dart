import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/features/corkboard/presentation/print_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The print viewer on a Pixel 9 Pro, upright (buttons in a row under the
/// print) and sideways (buttons in a column on the right, so the print gets
/// the height): no overflow either way (SHOTS=dir saves the frames).
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();
  final items = [
    MediaItem(
      id: 'a',
      cameraId: 'portra400',
      kind: MediaKind.photo,
      status: MediaStatus.ready,
      fileName: 'ROLL001_07.JPG',
      capturedAt: DateTime(2026, 10, 6),
      readyAt: DateTime(2026, 10, 6),
      width: 3,
      height: 2,
    ),
  ];

  for (final landscape in [false, true]) {
    testWidgets('print viewer ${landscape ? 'landscape' : 'portrait'}', (tester) async {
      tester.view.physicalSize = landscape ? const Size(2856, 1280) : const Size(1280, 2856);
      tester.view.devicePixelRatio = 3.1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [filmItemsProvider.overrideWith((ref) => Stream.value(items))],
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: ColoredBox(
                color: const Color(0xFF8A6A48),
                child: PrintViewerScreen(items: items, initialIndex: 0),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      final save = tester.getCenter(find.text('Save'));
      final share = tester.getCenter(find.text('Share'));
      if (landscape) {
        expect(save.dx, closeTo(share.dx, 1), reason: 'one column');
        expect(save.dx, greaterThan(tester.view.physicalSize.width / 3.1 * 0.8), reason: 'on the right');
      } else {
        expect(save.dy, closeTo(share.dy, 1), reason: 'one row');
      }
      if (shots != null) {
        final image = await tester.runAsync(
          () => (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 1),
        );
        final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
        File('$shots/print_viewer_${landscape ? 'landscape' : 'portrait'}.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      }
    });
  }
}
