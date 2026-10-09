import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/device/physical_orientation.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/theme/retro_theme.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/camera/presentation/photo_body.dart';
import 'package:darkroom/features/camera/presentation/widgets/camera_controls.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:darkroom/features/sd_card/presentation/win98/win98_shutdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _Held extends PhysicalOrientationNotifier {
  @override
  DeviceOrientation build() => DeviceOrientation.portraitUp;
}

class _Mode extends AppModeNotifier {
  _Mode(this.mode);

  final AppMode mode;

  @override
  AppMode build() => mode;
}

/// The gallery buttons (a print on film bodies, a review LCD on digital
/// ones) with and without a picture, and the Shut Down screens. `SHOTS=dir`
/// saves them.
void main() {
  final shots = Platform.environment['SHOTS'];

  Future<void> save(WidgetTester tester, GlobalKey key, String name) async {
    if (shots == null) return;
    await tester.runAsync(() async {
      final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/$name.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  testWidgets('gallery buttons', (tester) async {
    final dir = Directory.systemTemp.createTempSync('thumb');
    final thumb = '${dir.path}/t.jpg';
    final pic = img.Image(width: 160, height: 120);
    for (final p in pic) {
      p
        ..r = 60 + p.x
        ..g = 90 + p.y
        ..b = 150;
    }
    File(thumb).writeAsBytesSync(img.encodeJpg(pic));
    MediaItem item(String camera) => MediaItem(
      id: camera,
      cameraId: camera,
      kind: MediaKind.photo,
      status: MediaStatus.ready,
      fileName: 'A.JPG',
      capturedAt: DateTime(2026),
      readyAt: DateTime(2026),
      thumbPath: thumb,
      outputPath: thumb,
      seen: true,
    );
    final key = GlobalKey();
    Widget button(AppMode mode, List<MediaItem> items) => ProviderScope(
      overrides: [
        // The classic drawn buttons (the photoreal ones: photo_body_test).
        bodyArtProvider.overrideWithValue(null),
        appModeProvider.overrideWith(() => _Mode(mode)),
        physicalOrientationProvider.overrideWith(_Held.new),
        filmItemsProvider.overrideWith((ref) => Stream.value(items)),
        sdCardItemsProvider.overrideWith((ref) => Stream.value(items)),
      ],
      child: Theme(
        data: RetroPalette.forMode(mode).toTheme(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GalleryButton(onOpen: () {}),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(0xFF8A8F96),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  button(AppMode.film, [item('portra400')]),
                  button(AppMode.film, const []),
                  button(AppMode.digital, [item('ccd2003')]),
                  button(AppMode.digital, const []),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull);
    await save(tester, key, 'gallery_buttons');
  });

  testWidgets('shut down screens', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [physicalOrientationProvider.overrideWith(_Held.new)],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(onPressed: () => showShutDownSequence(context), child: const Text('go')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 600));
    await save(tester, key, 'shutdown_1');
    await tester.pump(const Duration(milliseconds: 3200));
    await save(tester, key, 'shutdown_2');
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump(const Duration(milliseconds: 300));
    await save(tester, key, 'shutdown_3_crt');
    await tester.pump(const Duration(milliseconds: 300));
    await save(tester, key, 'shutdown_4_line');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('go'), findsOneWidget); // back where it started
  });
}
