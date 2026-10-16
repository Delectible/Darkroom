import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/theme/retro_theme.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/camera/presentation/widgets/camera_controls.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Selected extends SelectedCameraNotifier {
  @override
  Map<AppMode, String> build() => {AppMode.film: 'ektar100', AppMode.digital: 'ccd2003'};

  @override
  Future<void> select(AppMode mode, String id) async => state = {...state, mode: id};
}

class _Mode extends AppModeNotifier {
  @override
  AppMode build() => AppMode.film;
}

/// The film memo holder: changing stock slides the cards through the
/// window toward the side the new stock came from, and both cards show
/// mid-slide (SHOTS=dir saves the frames).
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  testWidgets('memo card slides with the step direction', (tester) async {
    final container = ProviderContainer(
      overrides: [
        selectedCameraProvider.overrideWith(_Selected.new),
        appModeProvider.overrideWith(_Mode.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RetroPalette.forMode(AppMode.film).toTheme(),
          home: Scaffold(
            backgroundColor: const Color(0xFF2A2622),
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: SizedBox(width: 220, height: 56, child: StockLabel(onOpen: () {})),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> shoot(String name) async {
      if (shots == null) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(
          pixelRatio: 3,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$shots/memo_$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    // The moving cards (an invisible copy of the current one sizes the window).
    Finder card(String text) =>
        find.descendant(of: find.byType(FractionalTranslation), matching: find.text(text));
    double xOf(String text) => tester.getTopLeft(card(text).last).dx;

    // Next stock: the strip travels left, the new card enters from the right.
    await container.read(selectedCameraProvider.notifier).step(AppMode.film, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 190));
    final next = container.read(activeSpecProvider).name.toUpperCase();
    expect(card('VIVID 100'), findsOneWidget);
    expect(xOf(next), greaterThan(xOf('VIVID 100')));
    await shoot('next_mid');
    await tester.pumpAndSettle();
    expect(card('VIVID 100'), findsNothing);
    await shoot('next_end');

    // Previous: the other way.
    await container.read(selectedCameraProvider.notifier).step(AppMode.film, -1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 190));
    expect(xOf('VIVID 100'), lessThan(xOf(next)));
    await shoot('prev_mid');
    await tester.pumpAndSettle();
    expect(card(next), findsNothing);
  });
}
