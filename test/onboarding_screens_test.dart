import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/help/how_it_works_screen.dart';
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

  // Default text, and the biggest system text the app honours (1.3x).
  for (final scale in [1.0, 1.3]) {
    testWidgets('welcome tour pages, text x$scale', (tester) async {
      tester.view.physicalSize = const Size(1280, 2856);
      tester.view.devicePixelRatio = 3.1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userNameProvider.overrideWith(_NoName.new),
            initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
          ],
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(debugShowCheckedModeBanner: false, home: OnboardingScreen(onDone: () {})),
          ),
        ),
      );
      // The first page's rabbit is an asset: load it (and fail if it's gone).
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/artwork/rabbit_mark.png'),
          tester.element(find.byType(OnboardingScreen)),
          onError: (e, _) => throw e,
        ),
      );
      await tester.pumpAndSettle();
      for (var page = 0; page < 7; page++) {
        if (shots != null) {
          await tester.runAsync(() async {
            final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await ro.toImage(pixelRatio: 1);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$shots/onboarding_${scale}_$page.png').writeAsBytes(png!.buffer.asUint8List());
          });
        }
        if (page < 6) {
          await tester.tap(find.byType(FilledButton));
          // (the moves page loops for ever: pump, don't settle)
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        }
      }
      expect(find.text('Allow all'), findsOneWidget);
      expect(find.text('A few quick yeses'), findsOneWidget);
    });
  }

  for (final (scale, land) in [(1.0, false), (1.3, false), (1.0, true)]) {
    testWidgets('how it works, text x$scale${land ? ', landscape' : ''}', (tester) async {
      tester.view.physicalSize = land ? const Size(2856, 1280) : const Size(1280, 2856);
      tester.view.devicePixelRatio = 3.1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: const MaterialApp(debugShowCheckedModeBanner: false, home: HowItWorksScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      if (shots != null) {
        await tester.runAsync(() async {
          final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await ro.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$shots/how_it_works_$scale${land ? '_land' : ''}.png').writeAsBytes(png!.buffer.asUint8List());
        });
      }
      expect(find.text('Tap a print'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
