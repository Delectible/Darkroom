import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/theme/retro_theme.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/camera/presentation/widgets/camera_controls.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:darkroom/features/corkboard/presentation/corkboard_screen.dart';
import 'package:darkroom/features/corkboard/presentation/reel_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _Selected extends SelectedCameraNotifier {
  _Selected(this.ids);

  final Map<AppMode, String> ids;

  @override
  Map<AppMode, String> build() => ids;
}

class _Mode extends AppModeNotifier {
  _Mode(this.mode);

  final AppMode mode;

  @override
  AppMode build() => mode;
}

/// The corkboard's pinned items, the darkroom painters and the camera's
/// stock label (memo holder / LCD) laid out together: no overflow, and with
/// `SHOTS=dir` a picture to look at.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  testWidgets('corkboard and body pieces', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('cork');
    final pic = img.Image(width: 320, height: 240);
    for (final p in pic) {
      p
        ..r = 60 + p.x % 160
        ..g = 90 + p.y % 120
        ..b = 140;
    }
    final thumb = '${dir.path}/t.jpg';
    File(thumb).writeAsBytesSync(img.encodeJpg(pic));
    MediaItem item(String camera, {MediaKind kind = MediaKind.photo, String? note}) => MediaItem(
      id: camera,
      cameraId: camera,
      kind: kind,
      status: MediaStatus.ready,
      fileName: kind == MediaKind.video ? 'REEL003.MP4' : 'ROLL001_07.JPG',
      capturedAt: DateTime(2026, 10, 6),
      readyAt: DateTime(2026, 10, 6),
      thumbPath: thumb,
      outputPath: thumb,
      width: 3,
      height: 2,
      durationMs: 42000,
      note: note,
    );

    Widget scope(AppMode mode, String id, Widget child) => ProviderScope(
      overrides: [
        appModeProvider.overrideWith(() => _Mode(mode)),
        selectedCameraProvider.overrideWith(() => _Selected({AppMode.film: id, AppMode.digital: id})),
        sdCardItemsProvider.overrideWith((ref) => Stream.value(const <MediaItem>[])),
      ],
      child: Theme(data: RetroPalette.forMode(mode).toTheme(), child: child),
    );

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFFB4875A),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SizedBox(
                      height: 230,
                      // The print backs put your name on the lab stamp.
                      child: ProviderScope(
                        overrides: [userNameProvider.overrideWith(_Name.new)],
                        child: Row(
                          children: [
                            Expanded(
                              child: PinnedPrint(item: item('portra400'), onOpen: () {}),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: PinnedInstant(
                                item: item('polaroid600', note: 'the lake, 2026'),
                                onOpen: () {},
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 200,
                      child: Row(
                        children: [
                          Expanded(
                            child: PinnedReel(
                              item: item('super8', kind: MediaKind.video),
                              onOpen: () {},
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Row(
                              children: [
                                for (final p in [0.3, 0.6, 0.95])
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: AspectRatio(
                                        aspectRatio: 0.75,
                                        child: CustomPaint(
                                          painter: PrintTrayPainter(
                                            progress: p,
                                            ripple: 0.3,
                                            stage: PrintTrayPainter.stageFor(p),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 70,
                      child: Row(
                        children: [
                          const SizedBox(width: 70, child: CustomPaint(painter: _Tank())),
                          const SizedBox(width: 12),
                          Expanded(child: scope(AppMode.film, 'portra400', StockLabel(onOpen: () {}))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    scope(AppMode.digital, 'ccd2003', StockLabel(onOpen: () {})),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();

    // Turning a print over by its corner keeps its exact shape.
    Finder named(String type) => find.byWidgetPredicate((w) => w.runtimeType.toString() == type);
    final card = named('_FlipCard').at(1); // the instant print
    final front = tester.getRect(card);
    await tester.tapAt(front.bottomRight - const Offset(6, 6));
    await tester.pumpAndSettle();
    expect(named('_PrintBack'), findsOneWidget);
    final back = tester.getRect(named('_PrintBack'));
    expect(back.size.width, closeTo(front.size.width, 0.5));
    expect(back.size.height, closeTo(front.size.height, 0.5));
    if (shots != null) {
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await ro.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$shots/corkboard_pieces.png').writeAsBytes(png!.buffer.asUint8List());
      });
    }
    dir.deleteSync(recursive: true);
  });
}

class _Tank extends CustomPainter {
  const _Tank();

  @override
  void paint(Canvas canvas, Size size) => DevelopingTankPainter(progress: 0.4, spin: 0.8).paint(canvas, size);

  @override
  bool shouldRepaint(_Tank old) => false;
}

class _Name extends UserNameNotifier {
  @override
  String? build() => 'Sam';
}
