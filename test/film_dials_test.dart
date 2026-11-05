import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/features/camera/application/exposure_controller.dart';
import 'package:darkroom/features/camera/application/zoom_controller.dart';
import 'package:darkroom/features/camera/presentation/film_dials.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Zoom extends ZoomController {
  @override
  ZoomState build() => const ZoomState(level: 1, min: 1, max: 2.5);

  @override
  void setLevel(double level) => state = state.copyWith(level: level.clamp(state.min, state.max));

  @override
  void settle() {}
}

class _Ev extends ExposureController {
  @override
  double build() => 0;

  @override
  void set(double stops) => state = CameraCatalog.byId('gold200').exposure!.snap(stops);
}

/// The film viewfinder's zoom ring and exposure scale: they draw, turn and
/// step (SHOTS=dir saves them at rest and in use).
void main() {
  final shots = Platform.environment['SHOTS'];

  testWidgets('zoom ring turns and stops at the lens ends; exposure steps', (tester) async {
    tester.view.physicalSize = const Size(1080, 1620);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final container = ProviderContainer(
      overrides: [zoomProvider.overrideWith(_Zoom.new), exposureCompProvider.overrideWith(_Ev.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF2C3A62), Color(0xFFB0687A), Color(0xFFF0A868), Color(0xFF1D2230)],
                  stops: [0, 0.45, 0.62, 0.63],
                ),
              ),
              child: FilmDials(spec: CameraCatalog.byId('gold200')),
            ),
          ),
        ),
      ),
    );
    Future<void> shoot(String name) async {
      expect(tester.takeException(), isNull);
      if (shots == null) return;
      final image = await tester.runAsync(
        () => (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2),
      );
      final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      File('$shots/dials_$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    await tester.pump();
    await shoot('rest');
    // turn the ring: drag left along the bottom zooms in
    final size = tester.getSize(find.byType(FilmDials));
    final g = await tester.startGesture(Offset(size.width * 0.7, size.height * 0.9));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(-14, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await shoot('zoom');
    final mid = container.read(zoomProvider).level;
    expect(mid, greaterThan(1.2));
    // past the long end: it stops there
    for (var i = 0; i < 30; i++) {
      await g.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(container.read(zoomProvider).level, closeTo(2.5, 1e-6));
    // exposure: drag up the right edge
    final e = await tester.startGesture(Offset(size.width * 0.95, size.height * 0.4));
    for (var i = 0; i < 6; i++) {
      await e.moveBy(const Offset(0, -12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await shoot('exposure');
    expect(container.read(exposureCompProvider), greaterThan(0));
    await e.up();
    await tester.pumpAndSettle();
  });
}
