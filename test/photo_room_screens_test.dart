import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/features/sd_card/application/sd_card_controller.dart';
import 'package:darkroom/features/sd_card/presentation/win98/photo_room/photo_room.dart';
import 'package:darkroom/features/sd_card/presentation/win98/photo_room/photo_room_render.dart';
import 'package:darkroom/features/sd_card/presentation/win98/pixel_icons.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

/// Photo Room's wizard on a phone: choose, pick (tap order numbers, Select
/// All / Deselect All), arrange each kind. `SHOTS=dir` saves PNGs.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();
  var land = false;
  late List<MediaItem> pictures;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('photoroom');
    pictures = [
      for (var i = 0; i < 7; i++)
        () {
          final pic = img.Image(width: 640, height: 480);
          for (final p in pic) {
            p
              ..r = 40 + (p.x + i * 50) % 200
              ..g = 60 + (p.y * 2 + i * 20) % 160
              ..b = 90 + i * 20;
          }
          final path = '${dir.path}/p$i.jpg';
          File(path).writeAsBytesSync(img.encodeJpg(pic));
          return MediaItem(
            id: 'c$i',
            cameraId: 'ccd2003',
            kind: MediaKind.photo,
            status: MediaStatus.ready,
            fileName: 'IMG_00${10 + i}.JPG',
            capturedAt: DateTime(2026, 11, 1),
            readyAt: DateTime(2026, 11, 1),
            outputPath: path,
            thumbPath: path,
            width: 640,
            height: 480,
            location: MediaLocation.c,
          );
        }(),
    ];
  });

  Future<void> shoot(WidgetTester tester, String name) async {
    if (shots == null) return;
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/photoroom_$name${land ? '_land' : ''}.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  Future<void> real(WidgetTester tester, [int times = 6]) async {
    for (var i = 0; i < times; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  for (final sideways in [false, true]) {
    group(sideways ? 'landscape' : 'portrait', () {
      setUp(() => land = sideways);
      testWidgets('the wizard: choose, pick, arrange', (tester) async {
        tester.view.physicalSize = land ? const Size(2856, 1280) : const Size(1280, 2856);
        tester.view.devicePixelRatio = 3.1;
        addTearDown(tester.view.reset);
        await tester.runAsync(() async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [darkroomFolderProvider.overrideWithValue(pictures)],
              child: RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  home: Scaffold(
                    backgroundColor: const Color(0xFF008080),
                    body: Builder(
                      builder: (context) => Center(
                        child: TextButton(onPressed: () => showPhotoRoom(context), child: const Text('open')),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        });
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Welcome to the Photo Room Wizard'), findsOneWidget);
        await shoot(tester, 'choose');

        // a booth strip: 3 or 4, in tap order
        await tester.tap(find.text('Photo booth strip'));
        await tester.pump();
        await tester.tap(find.text('Next >'));
        await tester.pumpAndSettle();
        expect(find.text('Pick your photos'), findsOneWidget);
        await tester.tap(find.text('IMG_0012.JPG'));
        await tester.tap(find.text('IMG_0010.JPG'));
        await tester.pump();
        expect(find.textContaining('2 of 7 picked'), findsOneWidget);
        await tester.tap(find.text('IMG_0015.JPG'));
        await tester.pump();
        await real(tester);
        await shoot(tester, 'pick');
        // Select All takes as many as a strip holds; Deselect All clears
        await tester.tap(find.text('Select All'));
        await tester.pump();
        expect(find.textContaining('4 of 7 picked'), findsOneWidget);
        await tester.tap(find.text('Deselect All'));
        await tester.pump();
        expect(find.textContaining('0 of 7 picked'), findsOneWidget);
        for (final n in ['IMG_0012.JPG', 'IMG_0010.JPG', 'IMG_0015.JPG']) {
          await tester.tap(find.text(n));
        }
        await tester.pump();
        // (real time: the photos decode and the strip draws off the test clock)
        await tester.tap(find.text('Next >'));
        await tester.pump();
        await tester.runAsync(() async {
          // (redrawn here, on the real clock: the photos decode off the test's)
          await tester.tap(find.text('Lemon'));
          for (var i = 0; i < 30 && find.byType(RawImage).evaluate().isEmpty; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
          }
        });
        await tester.pump();
        expect(find.byType(RawImage), findsOneWidget);
        expect(find.text('Shuffle doodles'), findsOneWidget);
        await shoot(tester, 'strip');
        // a new shuffle, a new fill
        await tester.runAsync(() async {
          await tester.tap(find.text('Shuffle doodles'));
          await tester.tap(find.text('Sky'));
          for (var i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
          }
        });
        await shoot(tester, 'strip_shuffled');

        // back to the start: a card
        await tester.tap(find.text('< Back'));
        await tester.pump();
        await tester.tap(find.text('< Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Greeting card or poster'));
        await tester.pump();
        await tester.tap(find.text('Next >'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next >'));
        await tester.pump();
        await real(tester, 8);
        expect(find.text('Hello!'), findsWidgets);
        await shoot(tester, 'card');

        // and a GIF
        await tester.tap(find.text('< Back'));
        await tester.pump();
        await tester.tap(find.text('< Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Animated GIF'));
        await tester.pump();
        await tester.tap(find.text('Next >'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next >'));
        await tester.pump();
        await real(tester, 8);
        expect(find.text('Slow'), findsOneWidget);
        await shoot(tester, 'gif');
        await tester.pumpWidget(const SizedBox());
      });
    });
  }

  test('what each takes', () {
    expect(PhotoRoomMake.collage.fits(3), isFalse);
    expect(PhotoRoomMake.collage.fits(9), isTrue);
    expect(PhotoRoomMake.strip.fits(4), isTrue);
    expect(PhotoRoomMake.sheet.fits(36), isTrue);
    expect(spritesAreValid(), isTrue);
  });

  test('a GIF encodes', () async {
    final dir = Directory.systemTemp.createTempSync('gif');
    final paths = [
      for (var i = 0; i < 3; i++)
        () {
          final p = '${dir.path}/g$i.jpg';
          File(p).writeAsBytesSync(
            img.encodeJpg(img.Image(width: 64, height: 48)..clear(img.ColorRgb8(i * 80, 40, 90))),
          );
          return p;
        }(),
    ];
    final bytes = await encodeGif(paths, 200, GifSize.small);
    final gif = img.decodeGif(bytes)!;
    expect(gif.numFrames, 3);
    expect(gif.width, 320);
  });
}
