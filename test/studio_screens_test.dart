import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/features/studio/studio_book_screen.dart';
import 'package:darkroom/features/studio/studio_makers.dart';
import 'package:darkroom/features/studio/studio_render.dart';
import 'package:darkroom/features/studio/studio_screen.dart';
import 'package:darkroom/features/studio/studio_store.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

/// The Studio: the tray and its four cards (each with the prints it takes),
/// a strip and a collage made from photos of different shapes, and the
/// book's pages. `SHOTS=dir` saves PNGs.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  late List<MediaItem> prints;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('studio');
    // film shapes: 3:2, 4:3 landscape, square, 3:4 portrait
    final shapes = [(600, 400), (640, 480), (500, 500), (450, 600)];
    prints = [
      for (var i = 0; i < shapes.length; i++)
        () {
          final (w, h) = shapes[i];
          final pic = img.Image(width: w, height: h);
          for (final p in pic) {
            p
              ..r = 40 + (p.x * 3 + i * 60) % 200
              ..g = 60 + (p.y * 2) % 160
              ..b = 90 + i * 35;
          }
          final path = '${dir.path}/p$i.jpg';
          File(path).writeAsBytesSync(img.encodeJpg(pic));
          return MediaItem(
            id: 'p$i',
            cameraId: 'portra400',
            kind: MediaKind.photo,
            status: MediaStatus.ready,
            fileName: 'ROLL001_0$i.JPG',
            capturedAt: DateTime(2026, 11, 1),
            readyAt: DateTime(2026, 11, 1),
            thumbPath: path,
            outputPath: path,
            width: w,
            height: h,
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
      await File('$shots/studio_$name.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  Widget app(Widget home, {int inStudio = 3}) => ProviderScope(
    overrides: [
      initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
      filmItemsProvider.overrideWith((ref) => Stream.value(prints)),
      studioProvider.overrideWith(() => _Studio([for (final m in prints.take(inStudio)) m.id])),
      studioBookProvider.overrideWith(_Book.new),
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp(debugShowCheckedModeBanner: false, home: home),
    ),
  );

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('studio: the tray and the cards say what each takes', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(const StudioScreen()));
    await settle(tester);
    expect(find.text('3 prints on the table'), findsOneWidget);
    expect(find.textContaining('3 or 4 prints · ready'), findsOneWidget);
    expect(find.textContaining('1 more needed'), findsOneWidget); // flip book: 4 to 24
    expect(find.textContaining('pick which'), findsOneWidget); // collage: 2, 4, 6 or 9
    expect(find.text('Return all to the board'), findsOneWidget);
    await shoot(tester, 'table');
  });

  for (final kind in [StudioKind.strip, StudioKind.collage]) {
    testWidgets('studio: ${kind.name} from photos of different shapes', (tester) async {
      await phone(tester);
      // (real time: the photos decode and the piece draws off the test clock)
      await tester.runAsync(() async {
        await tester.pumpWidget(app(StudioMaker(kind: kind, prints: prints)));
        for (var i = 0; i < 20 && find.byType(RawImage).evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await tester.pump();
        }
      });
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);
      await shoot(tester, kind.name);
      if (kind == StudioKind.collage) {
        await tester.runAsync(() async {
          await tester.tap(find.text('Loose'));
          await tester.tap(find.text('Kraft'));
          for (var i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 150));
            await tester.pump();
          }
        });
        await shoot(tester, 'collage_loose');
      }
    });
  }

  test('book pages: a scrapbook alone, strips and collages share', () {
    StudioWork w(StudioKind k, int i) =>
        StudioWork(id: '$i', kind: k, path: '/x$i', createdAt: DateTime(2026));
    final pages = studioPages([
      w(StudioKind.strip, 1),
      w(StudioKind.strip, 2),
      w(StudioKind.collage, 3), // 1 + 1 + 2 > 3: new page
      w(StudioKind.scrapbook, 4),
      w(StudioKind.strip, 5),
    ]);
    expect([for (final p in pages) p.map((x) => x.id).join(',')], ['1,2', '3', '4', '5']);
  });

  test('how many each takes', () {
    expect(StudioNeeds.of(StudioKind.collage).fits(3), isFalse);
    expect(StudioNeeds.of(StudioKind.collage).fits(6), isTrue);
    expect(StudioNeeds.of(StudioKind.strip).fits(4), isTrue);
    expect(StudioNeeds.of(StudioKind.flipbook).min, 4);
    expect(collageGrid(6), (3, 2));
  });
}

class _Studio extends StudioNotifier {
  _Studio(this.ids);

  final List<String> ids;

  @override
  List<String> build() => ids;
}

class _Book extends StudioBook {
  @override
  Future<List<StudioWork>> build() async => const [];
}
