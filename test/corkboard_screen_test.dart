import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/corkboard/presentation/corkboard_screen.dart';
import 'package:darkroom/features/darkroom/application/darkroom_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _Engine implements DarkroomEngine {
  @override
  Future<void> markSeen() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Name extends UserNameNotifier {
  @override
  String? build() => 'Sam';
}

/// The whole corkboard (darkroom strip, pinned prints, reels, instants) at a
/// Pixel 9 Pro's size, upright and turned to landscape (the board follows
/// the phone): an overflow anywhere fails the test. `SHOTS=dir` saves PNGs.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  for (final land in [false, true]) {
    testWidgets('corkboard ${land ? 'landscape' : 'portrait'}', (tester) async {
      tester.view.physicalSize = land ? const Size(2856, 1280) : const Size(1280, 2856);
      tester.view.devicePixelRatio = 3.1;
      tester.view.padding = land
          ? const FakeViewPadding(left: 150, bottom: 60)
          : const FakeViewPadding(top: 150, bottom: 60);
      addTearDown(tester.view.reset);

      final dir = Directory.systemTemp.createTempSync('board');
      final pic = img.Image(width: 300, height: 200);
      for (final p in pic) {
        p
          ..r = 70 + p.x % 150
          ..g = 100 + p.y % 100
          ..b = 130;
      }
      final thumb = '${dir.path}/t.jpg';
      File(thumb).writeAsBytesSync(img.encodeJpg(pic));
      final now = DateTime.now();
      var n = 0;
      MediaItem item(String camera, {MediaKind kind = MediaKind.photo, bool developing = false}) => MediaItem(
        id: '${camera}_${n++}',
        cameraId: camera,
        kind: kind,
        status: MediaStatus.ready,
        fileName: kind == MediaKind.video ? 'REEL003.MP4' : 'ROLL001_07.JPG',
        capturedAt: now.subtract(const Duration(minutes: 2)),
        readyAt: developing ? now.add(const Duration(minutes: 3)) : now.subtract(const Duration(minutes: 1)),
        thumbPath: thumb,
        outputPath: thumb,
        width: 3,
        height: 2,
        durationMs: 42000,
        seen: true,
      );
      final items = [
        item('portra400', developing: true),
        item('super8', kind: MediaKind.video, developing: true),
        for (var i = 0; i < 4; i++) item('portra400'),
        item('polaroid600'),
        item('super8', kind: MediaKind.video),
        item('hp5plus400'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            filmItemsProvider.overrideWith((ref) => Stream.value(items)),
            secondTickerProvider.overrideWith((ref) => Stream.value(now)),
            darkroomEngineProvider.overrideWithValue(_Engine()),
            userNameProvider.overrideWith(_Name.new),
          ],
          child: RepaintBoundary(
            key: boundary,
            child: const MaterialApp(debugShowCheckedModeBanner: false, home: CorkboardScreen()),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);

      if (shots != null) {
        await tester.runAsync(() async {
          final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await ro.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$shots/corkboard_${land ? 'land' : 'port'}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }

  testWidgets('a print coming off: the prints fade round to the new order, no jump', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    MediaItem print(int i) => MediaItem(
      id: 'p$i',
      cameraId: 'portra400',
      kind: MediaKind.photo,
      status: MediaStatus.ready,
      fileName: 'ROLL001_0$i.JPG',
      capturedAt: now.subtract(const Duration(minutes: 2)),
      readyAt: now.subtract(const Duration(minutes: 1)),
      width: 3,
      height: 2,
      seen: true,
    );
    final items = StreamController<List<MediaItem>>();
    addTearDown(items.close);
    items.add([print(1), print(2), print(3)]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filmItemsProvider.overrideWith((ref) => items.stream),
          secondTickerProvider.overrideWith((ref) => Stream.value(now)),
          darkroomEngineProvider.overrideWithValue(_Engine()),
          userNameProvider.overrideWith(_Name.new),
        ],
        child: const MaterialApp(home: CorkboardScreen()),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(PinnedPrint), findsNWidgets(3));

    items.add([print(1), print(3)]);
    double opacity() => tester.widget<SliverFadeTransition>(find.byType(SliverFadeTransition)).opacity.value;
    for (var i = 0; i < 20 && opacity() > 0.9; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(opacity(), lessThan(0.9), reason: 'the prints fade out');
    expect(find.byType(PinnedPrint), findsNWidgets(3), reason: 'still the old order while it fades out');

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byType(PinnedPrint), findsNWidgets(2), reason: 'the new order, faded back in');
    expect(opacity(), 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
