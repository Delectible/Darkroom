import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:darkroom/features/monetization/pro_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The free version's "load today's roll?" sheet at Pixel 9 Pro size, for
/// a 35mm stock and Super 8 (minutes): no overflow (SHOTS=dir saves them).
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();
  for (final id in ['portra400', 'super8']) {
    testWidgets('load roll sheet $id', (tester) async {
      tester.view.physicalSize = const Size(1280, 2856);
      tester.view.devicePixelRatio = 3.1;
      addTearDown(tester.view.reset);
      final spec = CameraCatalog.byId(id);
      await tester.pumpWidget(
        ProviderScope(
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Roboto'),
              home: Builder(
                builder: (context) => Scaffold(
                  backgroundColor: const Color(0xFF0C0B0A),
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showLoadRollSheet(context, spec),
                      child: const Text('go'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Load ${spec.name}?'), findsOneWidget);
      expect(find.text(id == 'super8' ? '1 minute of film' : '24 shots'), findsOneWidget);
      expect(find.text('Pick another film'), findsOneWidget);
      await tester.tap(find.text('Pick another film'));
      await tester.pumpAndSettle();
      // Next morning, the same roll still in.
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Load it'))).pop();
      await tester.pumpAndSettle();
      unawaited(showCarriedRollSheet(tester.element(find.text('go')), spec, id == 'super8' ? 40 : 12));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text("Yesterday's roll is still in"), findsOneWidget);
      expect(find.text('Rewind & swap'), findsOneWidget);
      if (shots != null) {
        // Real image decoding only happens outside the fake clock.
        final el = tester.element(find.text('Pick another film'));
        await tester.runAsync(() => precacheImage(AssetImage(spec.artwork), el));
        await tester.pump();
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$shots/load_roll_$id.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }
}
