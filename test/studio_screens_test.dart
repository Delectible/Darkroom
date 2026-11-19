import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/studio/studio_book_screen.dart';
import 'package:darkroom/features/studio/studio_flip_frames.dart';
import 'package:darkroom/features/studio/studio_makers.dart';
import 'package:darkroom/features/studio/studio_page_turn.dart';
import 'package:darkroom/features/studio/studio_scrapbook.dart';
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
  // the screen it runs on: a big phone and a small one, each both ways
  var screen = _screens.first;

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
      await File('$shots/studio_$name${screen.tag}.png').writeAsBytes(png!.buffer.asUint8List());
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
    tester.view.physicalSize = screen.size;
    tester.view.devicePixelRatio = screen.dpr;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  // (each screen upright and sideways: nothing may overflow or overlap)
  for (final s in _screens) {
    group(s.name, () {
      setUp(() => screen = s);
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
          // a photo tapped: its frame, to drag and pinch
          await tester.tapAt(tester.getTopLeft(find.byType(RawImage)) + const Offset(60, 60));
          await tester.pumpAndSettle();
          expect(find.text('FRAME THE PHOTO'), findsOneWidget);
          await shoot(tester, '${kind.name}_frame');
          await tester.drag(find.byType(CustomPaint).last, const Offset(-40, 0));
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          if (kind == StudioKind.strip) {
            // the foot and the edges: a handwritten date, film holes
            await tester.runAsync(() async {
              await tester.ensureVisible(find.text('Handwritten'));
              await tester.tap(find.text('Handwritten'));
              await tester.ensureVisible(find.text('Film holes'));
              await tester.tap(find.text('Film holes'));
              for (var i = 0; i < 10; i++) {
                await Future<void>.delayed(const Duration(milliseconds: 150));
                await tester.pump();
              }
            });
            expect(find.textContaining('Caption: DARKROOM'), findsOneWidget);
            await shoot(tester, 'strip_holes');
          }
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

      testWidgets('scrapbook: prints spread out, a photo picked shows its frames, a text its fonts', (
        tester,
      ) async {
        await phone(tester);
        await tester.runAsync(() async {
          await tester.pumpWidget(app(ScrapbookEditor(prints: prints)));
          for (var i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
          }
        });
        final title = tester.getRect(find.text('My scrapbook'));
        await shoot(tester, 'scrapbook');
        expect(find.text('Sticker'), findsOneWidget);
        // tap the first print: its frames, Remove
        final first = tester.getCenter(find.byType(Image).first);
        await tester.tapAt(first);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Remove'), findsOneWidget);
        // the page didn't move when the tools changed
        expect(tester.getRect(find.text('My scrapbook')), title);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
        await shoot(tester, 'scrapbook_photo');
        // the title: fonts and colours
        await tester.tapAt(tester.getCenter(find.text('My scrapbook')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('LABEL'), findsOneWidget);
        await tester.tap(find.text('Typewriter'));
        await tester.pump();
        await shoot(tester, 'scrapbook_text');
        // the sticker sheet
        await tester.tap(find.text('Done'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Sticker'));
        await tester.pumpAndSettle();
        expect(find.text('Sticky note'), findsOneWidget);
        await shoot(tester, 'stickers');
        await tester.tap(find.text('Star'));
        await tester.pumpAndSettle();
        expect(find.text('Remove'), findsOneWidget);
        // writing with the keyboard up
        await tester.tap(find.text('Done').first);
        await tester.pumpAndSettle();
        tester.view.viewInsets = FakeViewPadding(bottom: screen.size.height * 0.42);
        await tester.tap(find.text('Writing'));
        await tester.pumpAndSettle();
        await shoot(tester, 'scrapbook_keyboard');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox());
      });

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
                // (a long name: shrinks to fit the cover)
                userNameProvider.overrideWith(() => _Name('Bartholomew Featherstonehaugh-Smythe')),
              ],
              child: RepaintBoundary(
                key: boundary,
                child: const MaterialApp(debugShowCheckedModeBanner: false, home: StudioBookScreen()),
              ),
            ),
          );
          // (real time for the pictures; the test clock held, so the cover
          // hasn't started to open)
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
          }
        });
        expect(find.text('page 1 of 2'), findsOneWidget);
        await shoot(tester, 'book_shut');
        // the cover swinging open, then open
        await tester.pump(const Duration(milliseconds: 280));
        await tester.pump(const Duration(milliseconds: 380));
        await shoot(tester, 'book_opening');
        await tester.pump(const Duration(milliseconds: 900));
        await shoot(tester, 'book');
        // drag the page part way over
        // (the right-hand page: the turn's box is both)
        final both = tester.getRect(find.byType(PageTurn));
        final page = Rect.fromLTRB(both.center.dx, both.top, both.right, both.bottom);
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
        // an empty book
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
              studioBookProvider.overrideWith(() => _Book(const [])),
            ],
            child: RepaintBoundary(
              key: boundary,
              child: const MaterialApp(debugShowCheckedModeBanner: false, home: StudioBookScreen()),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1600));
        await shoot(tester, 'book_empty');
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
    });
  }

  testWidgets('flip book frames: each style draws, and the video gets every change', (tester) async {
    await tester.runAsync(() async {
      final photos = [for (final m in prints) await loadStudioImage(m.outputPath!, maxSide: 400)];
      for (final style in FlipStyle.values) {
        final f = FlipFrames(photos: photos, paper: StudioPaper.cream, style: style, pageMs: 360);
        final keys = f.keyframes();
        // the frames cover the whole book, end to end, in order
        expect(keys.first.at, 0);
        expect(keys.fold<double>(0, (a, k) => a + k.hold), closeTo(f.totalMs, 1));
        for (var i = 1; i < keys.length; i++) {
          expect(keys[i].at, greaterThan(keys[i - 1].at));
        }
        // mid-change and still moments draw without trouble
        for (final t in [0.0, 400.0, 500.0, 1000.0]) {
          final rec = ui.PictureRecorder();
          f.paint(Canvas(rec), const Size(216, 270), t);
          final image = await rec.endRecording().toImage(216, 270);
          image.dispose();
        }
      }
    });
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

class _Name extends UserNameNotifier {
  _Name(this.name);

  final String name;

  @override
  String? build() => name;
}

class _Book extends StudioBook {
  _Book([this.works = const []]);

  final List<StudioWork> works;

  @override
  Future<List<StudioWork>> build() async => works;
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
