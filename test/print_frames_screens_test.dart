import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/navigation.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/theme/note_box.dart';
import 'package:darkroom/features/corkboard/presentation/print_frames.dart';
import 'package:darkroom/features/corkboard/presentation/print_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Frames in the print viewer: the Frame button opens a row of the print in
/// each frame, a tap puts one on; and the app's message box over it
/// (SHOTS=dir saves each).
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  Future<File> photo(Directory dir, String name, int w, int h) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final r = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    c.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C3A62), Color(0xFFB0687A), Color(0xFFF0A868), Color(0xFF1D2230)],
          stops: [0, 0.42, 0.62, 0.63],
        ).createShader(r),
    );
    c.drawCircle(Offset(w * 0.64, h * 0.56), h * 0.1, Paint()..color = const Color(0xFFFFE2B0));
    c.drawRect(Rect.fromLTWH(w * 0.2, h * 0.45, w * 0.02, h * 0.3), Paint()..color = const Color(0xFF12151D));
    c.drawCircle(Offset(w * 0.21, h * 0.42), h * 0.1, Paint()..color = const Color(0xFF12151D));
    final image = await rec.endRecording().toImage(w, h);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return File('${dir.path}/$name.png')..writeAsBytesSync(png!.buffer.asUint8List());
  }

  testWidgets('frames tray and notes in the print viewer', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('frames');
    addTearDown(() => dir.deleteSync(recursive: true));
    final (big, small) = (await tester.runAsync(
      () async => (await photo(dir, 'print', 1200, 800), await photo(dir, 'thumb', 300, 200)),
    ))!;
    final items = [
      MediaItem(
        id: 'a',
        cameraId: 'portra400',
        kind: MediaKind.photo,
        status: MediaStatus.ready,
        fileName: 'ROLL001_07.JPG',
        capturedAt: DateTime(2026, 10, 6),
        readyAt: DateTime(2026, 10, 6),
        width: 3,
        height: 2,
        outputPath: big.path,
        thumbPath: small.path,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [filmItemsProvider.overrideWith((ref) => Stream.value(items))],
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            navigatorKey: appNavigatorKey,
            debugShowCheckedModeBanner: false,
            home: ColoredBox(
              color: const Color(0xFF8A6A48),
              child: PrintViewerScreen(items: items, initialIndex: 0),
            ),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    Future<void> shoot(String name) async {
      await settle();
      expect(tester.takeException(), isNull);
      if (shots == null) return;
      final image = await tester.runAsync(
        () => (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2),
      );
      final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      File('$shots/frames_$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    await shoot('closed');
    await tester.tap(find.text('Frame'));
    await shoot('tray_classic');
    for (final f in [PrintFrame.borderless, PrintFrame.deckle, PrintFrame.darkroom]) {
      await tester.tap(find.text(f.label));
      await shoot('tray_${f.name}');
    }
    // the message box (#6): a plain one, and one with an action
    await tester.tap(find.text('Frame'));
    Notes.show('Saved to your photo library (Darkroom).');
    await shoot('note_saved');
    Notes.show(
      'A print you saved is no longer on your phone: deleted, or moved to the cloud by a backup app.',
      action: 'Save again',
    );
    await shoot('note_action');
    Notes.hide();
    await tester.pump(const Duration(seconds: 7));
  });
}
