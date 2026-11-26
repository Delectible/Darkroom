import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/corkboard/presentation/corkboard_screen.dart';
import 'package:darkroom/features/darkroom/application/darkroom_engine.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
/// The board's filters: shown once a dozen prints span films or months;
/// picking a film (then a month) narrows the board, All brings them back.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  testWidgets('corkboard filters', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    tester.view.padding = const FakeViewPadding(top: 150, bottom: 60);
    addTearDown(tester.view.reset);
    for (final c in ['user_accel', 'accelerometer']) {
      tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        EventChannel('dev.fluttercommunity.plus/sensors/$c'),
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
    }
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/sensors/method'),
      (_) async => null,
    );
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
    MediaItem item(String camera, int daysAgo) => MediaItem(
      id: '${camera}_${n++}',
      cameraId: camera,
      kind: MediaKind.photo,
      status: MediaStatus.ready,
      fileName: 'ROLL001_07.JPG',
      capturedAt: now.subtract(Duration(days: daysAgo)),
      readyAt: now.subtract(Duration(days: daysAgo)),
      thumbPath: thumb,
      outputPath: thumb,
      width: 3,
      height: 2,
      seen: true,
    );
    final items = [
      for (var i = 0; i < 6; i++) item('gold200', i),
      for (var i = 0; i < 4; i++) item('portra400', 35 + i),
      for (var i = 0; i < 3; i++) item('hp5plus400', 70 + i),
      item('cinestill800t', 1),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filmItemsProvider.overrideWith((ref) => Stream.value(items)),
          secondTickerProvider.overrideWith((ref) => Stream.value(now)),
          darkroomEngineProvider.overrideWithValue(_Engine()),
          initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
          userNameProvider.overrideWith(_Name.new),
        ],
        child: RepaintBoundary(
          key: boundary,
          child: const MaterialApp(debugShowCheckedModeBanner: false, home: CorkboardScreen()),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> shot(String name) async {
      if (shots == null) return;
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await ro.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$shots/$name.png').writeAsBytes(png!.buffer.asUint8List());
      });
    }

    await settle();
    expect(tester.takeException(), isNull);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Golden 200'), findsOneWidget);
    await shot('corkboard_filters');
    await tester.tap(find.text('Golden 200'));
    await settle();
    expect(tester.takeException(), isNull);
    expect(find.byType(PinnedPrint), findsNWidgets(6));
    await shot('corkboard_filters_golden');
    await tester.tap(find.text('All'));
    await settle();
    expect(find.byType(PinnedPrint), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
