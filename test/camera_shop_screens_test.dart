import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/skins/camera_skins.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:darkroom/features/skins/presentation/camera_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The camera shop at phone and tablet sizes: no overflow, picking a skin
/// puts it on the camera, locked skins can't be put on (SHOTS=dir saves
/// the frames).
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  Future<void> shoot(WidgetTester tester, String name) async {
    if (shots == null) return;
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/$name.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  for (final (name, size, dpr) in [
    ('phone', const Size(1280, 2856), 3.1),
    ('tablet', const Size(1600, 2560), 2.0),
    ('phone_landscape', const Size(2856, 1280), 3.1),
  ]) {
    testWidgets('shop $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundary,
            child: const MaterialApp(debugShowCheckedModeBanner: false, home: CameraShopScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ON YOUR CAMERA'), findsOneWidget);
      await shoot(tester, 'shop_film_$name');

      // a locked one: shown, can't be put on
      await tester.tap(find.text('PINBALL'));
      await tester.pumpAndSettle();
      expect(find.text('LOCKED'), findsOneWidget);
      await shoot(tester, 'shop_locked_$name');

      // owned (Debug: unlock all) -> put it on
      await container.read(unlockedSkinsProvider.notifier).unlockAll();
      await tester.pumpAndSettle();
      await tester.tap(find.text('PUT IT ON'));
      await tester.pumpAndSettle();
      expect(container.read(cameraSkinProvider)[AppMode.film], 'brassed');

      await tester.tap(find.text('DIGITAL'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OWNED').last);
      await tester.pumpAndSettle();
      await shoot(tester, 'shop_digital_$name');
    });
  }
}
