import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/features/sd_card/application/sd_card_controller.dart';
import 'package:darkroom/features/sd_card/presentation/win98/win98_display.dart';
import 'package:darkroom/features/sd_card/presentation/win98/win98_viewer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Win98 photo viewer: its actions at full size (wrapping, never
/// shrinking), the count in the status bar, and a Close button at the
/// bottom right, in portrait, landscape, large fonts and 640 x 480. `SHOTS=dir` saves it.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  MediaItem file(String id, String name) => MediaItem(
    id: id,
    kind: MediaKind.photo,
    cameraId: 'floppy99',
    status: MediaStatus.ready,
    fileName: name,
    capturedAt: DateTime(2026, 10, 6, 9),
    readyAt: DateTime(2026, 10, 6, 9),
    bytes: 34000,
    width: 640,
    height: 480,
    location: MediaLocation.c,
    savedAt: DateTime(2026, 10, 7),
  );

  for (final (name, size, dpr, display) in [
    ('portrait', const Size(1280, 2856), 3.1, const Win98Display()),
    ('landscape', const Size(2856, 1280), 3.1, const Win98Display()),
    ('large', const Size(1280, 2856), 3.1, const Win98Display(largeFonts: true, res: Win98Res.vga)),
    ('large_land', const Size(2856, 1280), 3.1, const Win98Display(largeFonts: true, res: Win98Res.vga)),
  ]) {
    testWidgets('viewer toolbar and Close ($name)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      Win98Display.current.value = display;
      addTearDown(() => Win98Display.current.value = const Win98Display());
      final items = [for (var i = 1; i <= 53; i++) file('$i', 'FLP000$i.JPG')];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
            initialCameraSettingsProvider.overrideWithValue(const {}),
            cSeenProvider.overrideWith(_Seen.new),
          ],
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Win98ViewerScreen(items: items, initialIndex: 12),
                        ),
                      ),
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
      await tester.pumpAndSettle();
      expect(find.text('13 of 53'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      // every action at its full size: none squeezed below a thumb's height
      for (final label in ['Send', 'Rename', 'Delete', 'Favourite']) {
        expect(
          tester
              .getSize(find.ancestor(of: find.text(label), matching: find.byType(GestureDetector)).first)
              .height,
          greaterThan(24),
        );
      }
      expect(tester.takeException(), isNull);
      if (shots != null) {
        await tester.runAsync(() async {
          final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await ro.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$shots/win98_viewer_$name.png').writeAsBytes(png!.buffer.asUint8List());
        });
      }
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(Win98ViewerScreen), findsNothing);
    });
  }
}

class _Seen extends CSeenNotifier {
  @override
  ({Set<String> ids, DateTime since}) build() => (ids: const {}, since: DateTime(2026));

  @override
  void see(String id) {}
}
