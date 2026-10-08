import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/features/sd_card/presentation/win98/debug_menu.dart';
import 'package:darkroom/features/sd_card/presentation/win98/explorer_dialogs.dart';
import 'package:darkroom/features/sd_card/presentation/win98/win98_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Layout smoke tests for the scaled Win98 screens at a Pixel 9 Pro's size
/// (an overflow anywhere fails the test). With `SHOTS=dir` the frames are
/// also saved as PNGs for a look, with real fonts if the SDK has them.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  setUpAll(() async {
    final fonts = Directory(
      '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts',
    );
    if (fonts.existsSync()) {
      final roboto = FontLoader('Roboto');
      for (final f in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
        final file = File('${fonts.path}/$f');
        if (file.existsSync()) roboto.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      }
      await roboto.load();
    }
  });

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home) => ProviderScope(
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Roboto'),
        home: home,
      ),
    ),
  );

  Future<void> shoot(WidgetTester tester, String name) async {
    if (shots == null) return;
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/$name.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  testWidgets('viewer: photo with zoom trackbar and camera readout', (tester) async {
    await phone(tester);
    final dir = Directory.systemTemp.createTempSync('w98');
    final pic = img.Image(width: 640, height: 480);
    for (final p in pic) {
      p
        ..r = p.x % 256
        ..g = (p.y * 2) % 256
        ..b = 160;
    }
    final path = '${dir.path}/DSC00042.JPG';
    File(path).writeAsBytesSync(img.encodeJpg(pic));
    final item = MediaItem(
      id: 'a',
      cameraId: 'ccd2003',
      kind: MediaKind.photo,
      status: MediaStatus.ready,
      fileName: 'DSC00042.JPG',
      capturedAt: DateTime(2026, 10, 6),
      readyAt: DateTime(2026, 10, 6),
      outputPath: path,
      width: 640,
      height: 480,
      bytes: 48213,
      location: MediaLocation.c,
    );
    await tester.pumpWidget(app(Win98ViewerScreen(items: [item, item], initialIndex: 0)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.text('Reset Zoom'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.textContaining('Camera:'), findsOneWidget);
    await shoot(tester, 'win98_viewer');
    dir.deleteSync(recursive: true);
  });

  testWidgets('debug window lists its tools and switches', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            backgroundColor: const Color(0xFF008080),
            body: Center(
              child: ElevatedButton(onPressed: () => showDebugMenu(context), child: const Text('go')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Camera Log'), findsWidgets);
    expect(find.text('Crash Reports'), findsOneWidget);
    expect(find.text('Welcome Tour'), findsOneWidget);
    await tester.tap(find.text('Frame Timing Graphs'));
    await tester.pump(const Duration(milliseconds: 400)); // past the double-tap wait
    expect(find.text('Turn On'), findsOneWidget);
    await tester.tap(find.text('Turn On'));
    await tester.pump();
    expect(find.text('Turn Off'), findsOneWidget);
    await shoot(tester, 'win98_debug');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('floppy span dialog asks for the next disk', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            backgroundColor: const Color(0xFF008080),
            body: Center(
              child: ElevatedButton(
                onPressed: () => showFloppySpan(context, disks: 5, label: 'CLIP0003.MP4'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 200)); // window opens
    await tester.pump(const Duration(milliseconds: 16)); // first reading frame
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50)); // disk 1 read
    }
    await tester.pump();
    expect(find.textContaining('Please insert disk 2 of 5'), findsOneWidget);
    await shoot(tester, 'win98_floppy');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
