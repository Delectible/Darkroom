import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/features/studio/studio_book_screen.dart';
import 'package:darkroom/features/studio/studio_makers.dart';
import 'package:darkroom/features/studio/studio_page_turn.dart';
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
      studioBookProvider.overrideWith(() => _Book()),
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
    expect(find.text('RETURN ALL TO THE BOARD'), findsOneWidget);
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

  testWidgets('the book: an album page packed by hand, the page turn, a flip book', (tester) async {
    await phone(tester);
    final dir = Directory.systemTemp.createTempSync('book');
    String pic(String name, int w, int h, int tone) {
      final im = img.Image(width: w, height: h);
      for (final p in im) {
        p
          ..r = 30 + (p.x * 2 + tone) % 200
          ..g = 50 + (p.y + tone) % 150
          ..b = 80 + tone % 120;
      }
      final path = '${dir.path}/$name.jpg';
      File(path).writeAsBytesSync(img.encodeJpg(im));
      return path;
    }

    StudioWork w(String id, StudioKind k, String path, {List<String> pages = const []}) => StudioWork(
      id: id,
      kind: k,
      path: path,
      cover: k == StudioKind.flipbook ? pages.first : null,
      pages: pages,
      paper: 'cream',
      pageMs: 360,
      createdAt: DateTime(2026, 11, 13),
    );
    final works = [
      w('s1', StudioKind.strip, pic('s1', 240, 800, 10)),
      w('c1', StudioKind.collage, pic('c1', 800, 800, 60)),
      w('s2', StudioKind.strip, pic('s2', 260, 700, 120)),
      w('c2', StudioKind.collage, pic('c2', 900, 640, 170)),
      w('f1', StudioKind.flipbook, '/none.mp4', pages: [for (final m in prints) m.outputPath!]),
      w('sb', StudioKind.scrapbook, pic('sb', 900, 1200, 90)),
    ];
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
            studioBookProvider.overrideWith(() => _Book(works)),
          ],
          child: RepaintBoundary(
            key: boundary,
            child: const MaterialApp(debugShowCheckedModeBanner: false, home: StudioBookScreen()),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 50));
      }
    });
    expect(find.text('page 1 of 2'), findsOneWidget);
    await shoot(tester, 'book');
    // drag the page part way over
    final page = tester.getRect(find.byType(PageTurn));
    final g = await tester.startGesture(page.bottomRight - const Offset(20, 60));
    await g.moveBy(const Offset(-40, 0));
    await tester.pump();
    await g.moveBy(Offset(-page.width * 0.45, -30));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await shoot(tester, 'book_turn');
    await g.moveBy(Offset(-page.width * 0.4, 0));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('page 2 of 2'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await shoot(tester, 'book_scrapbook');
    // the flip book, held big
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
          studioBookProvider.overrideWith(() => _Book(works)),
        ],
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(debugShowCheckedModeBanner: false, home: FlipBookViewer(work: works[4])),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    // (into the second page, the first swinging away)
    await tester.pump(const Duration(milliseconds: 360 + 90));
    expect(find.text('Save video'), findsOneWidget);
    await shoot(tester, 'flipbook_viewer');
    await tester.pumpWidget(const SizedBox());
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
  _Book([this.works = const []]);

  final List<StudioWork> works;

  @override
  Future<List<StudioWork>> build() async => works;
}
