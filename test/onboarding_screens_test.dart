import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoName extends UserNameNotifier {
  @override
  String? build() => null;
}

/// The first-run tour at Pixel 9 Pro size: every page lays out without
/// overflow. `SHOTS=dir` saves a PNG per page.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  testWidgets('welcome tour pages', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [userNameProvider.overrideWith(_NoName.new)],
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(debugShowCheckedModeBanner: false, home: OnboardingScreen(onDone: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var page = 0; page < 6; page++) {
      if (shots != null) {
        await tester.runAsync(() async {
          final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await ro.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$shots/onboarding_$page.png').writeAsBytes(png!.buffer.asUint8List());
        });
      }
      if (page < 5) {
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
      }
    }
    expect(find.text('Allow all'), findsOneWidget);
    expect(find.text('A few quick yeses'), findsOneWidget);
  });
}
