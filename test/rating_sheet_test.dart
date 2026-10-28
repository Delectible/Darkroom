import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/device/physical_orientation.dart';
import 'package:darkroom/features/review/rating_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Give us a shoutout!": fits a Pixel 9 Pro at 1.0x and 1.3x text, No thanks
/// = false, Yea! = true (then the store's prompt). `SHOTS=dir` saves it.
void main() {
  final shots = Platform.environment['SHOTS'];
  for (final (scale, button, want) in [(1.0, 'Yea!', true), (1.3, 'No thanks', false)]) {
    testWidgets('rating sheet x$scale, $button', (tester) async {
      tester.view.physicalSize = const Size(1280, 2856);
      tester.view.devicePixelRatio = 3.1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final boundary = GlobalKey();
      bool? answer;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [physicalOrientationProvider.overrideWith(_Held.new)],
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Builder(
                builder: (context) => Scaffold(
                  backgroundColor: const Color(0xFF0E0E12),
                  body: Center(
                    child: TextButton(
                      onPressed: () async => answer = await showRatingSheet(context),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/artwork/rabbit_mark.png'),
          tester.element(find.byType(RatingSheet)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Give us a shoutout!'), findsOneWidget);
      if (shots != null) {
        await tester.runAsync(() async {
          final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await ro.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$shots/rating_$scale.png').writeAsBytes(png!.buffer.asUint8List());
        });
      }
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(answer, want);
    });
  }
}

class _Held extends PhysicalOrientationNotifier {
  @override
  DeviceOrientation build() => DeviceOrientation.portraitUp;
}
