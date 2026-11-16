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
  // the screen it runs on: a big phone and a small one, each both ways
  var screen = _screens.first;
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
      await File('$shots/photoroom_$name${screen.tag}.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  Future<void> real(WidgetTester tester, [int times = 6]) async {
    for (var i = 0; i < times; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  for (final s in _screens) {
    group(s.name, () {
      setUp(() => screen = s);
      testWidgets('the wizard: choose, pick, arrange', (tester) async {
        tester.view.physicalSize = screen.size;
        tester.view.devicePixelRatio = screen.dpr;
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
        // the caption box with the keyboard up: it moves, the wizard stays put
        tester.view.viewInsets = FakeViewPadding(bottom: screen.size.height * 0.42);
        await tester.tap(find.text('Caption...'));
        await tester.pumpAndSettle();
        expect(find.text('Your text:'), findsOneWidget);
        await shoot(tester, 'caption_keyboard');
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();

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
        // the colour panel: a basic colour, then the card in it
        await tester.tap(find.byTooltip('Card colour'));
        await tester.pumpAndSettle();
        expect(find.text('Basic colors:'), findsOneWidget);
        await shoot(tester, 'card_colours');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        // add a photo from the pictures on C:
        await tester.tap(find.byTooltip('Add a photo'));
        await tester.pumpAndSettle();
        expect(find.text('Add a Photo'), findsOneWidget);
        await shoot(tester, 'card_add_photo');
        await tester.tap(find.text('IMG_0016.JPG'));
        await tester.pumpAndSettle();

        // and a GIF
        await tester.tap(find.text('< Back'));
        await tester.pump();
        await tester.tap(find.text('< Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Animated GIF'));
        await tester.pump();
        await tester.tap(find.text('Next >'));
        await tester.pumpAndSettle();
        // (the frames' decoding and the changes are covered by 'a GIF encodes')
        await tester.tap(find.text('Next >'));
        await tester.pump();
        await tester.tap(find.text('Circle'));
        await tester.pump();
        expect(find.text('Slow'), findsOneWidget);
        await shoot(tester, 'gif');
        await tester.pumpWidget(const SizedBox());
      });
    });
  }

  test('what each takes', () {
    expect(PhotoRoomMake.collage.fits(1), isFalse);
    expect(PhotoRoomMake.collage.fits(7), isTrue);
    expect(PhotoRoomMake.strip.fits(4), isTrue);
    expect(PhotoRoomMake.collage.fits(36), isTrue);
    expect(spritesAreValid(), isTrue);
  });

  test('thumbnails come from the saved file (a tall strip stays a tall strip)', () async {
    final dir = Directory.systemTemp.createTempSync('thumbs');
    final strip = img.Image(width: 600, height: 1462)..clear(img.ColorRgb8(250, 240, 120));
    img.fillRect(strip, x1: 44, y1: 48, x2: 556, y2: 432, color: img.ColorRgb8(200, 30, 40));
    final out = '${dir.path}/STRIP001.JPG', thumb = '${dir.path}/thumb.jpg';
    File(out).writeAsBytesSync(img.encodeJpg(strip));
    File(thumb).writeAsBytesSync([0, 1, 2]); // (a garbled old one)
    final item = MediaItem(
      id: 'photoroom_1',
      cameraId: 'photoroom',
      kind: MediaKind.photo,
      status: MediaStatus.ready,
      fileName: 'STRIP001.JPG',
      capturedAt: DateTime(2026, 11, 15),
      readyAt: DateTime(2026, 11, 15),
      outputPath: out,
      thumbPath: thumb,
      location: MediaLocation.c,
    );
    expect(await repairPhotoRoomThumbs([item]), isTrue);
    final t = img.decodeJpg(File(thumb).readAsBytesSync())!;
    expect((t.width, t.height), (164, 400));
    // the top photo's red at the top, the lemon paper round it
    expect(t.getPixel(82, 60).r, greaterThan(150));
    expect(t.getPixel(82, 60).g, lessThan(90));
    expect(t.getPixel(4, 200).g, greaterThan(200));
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
    // a fade: five frames between each pair (round to the first again)
    final faded = img.decodeGif(await encodeGif(paths, 600, GifSize.small, transition: GifTransition.fade))!;
    // (each photo, then its change to the next: 6 frames at least)
    expect(faded.numFrames, 3 * 7);
  });
}

typedef _Screen = ({String name, String tag, Size size, double dpr});

/// A big phone (the Pixel 9 Pro) and a small one (360 x 640), upright and
/// sideways.
const _screens = <_Screen>[
  (name: 'portrait', tag: '', size: Size(1280, 2856), dpr: 3.1),
  (name: 'landscape', tag: '_land', size: Size(2856, 1280), dpr: 3.1),
  (name: 'small', tag: '_small', size: Size(720, 1280), dpr: 2.0),
  (name: 'small landscape', tag: '_small_land', size: Size(1280, 720), dpr: 2.0),
];
