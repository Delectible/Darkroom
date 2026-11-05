import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/processing/multi_exposure.dart';
import 'package:darkroom/features/camera/application/exposure_controller.dart';
import 'package:darkroom/features/camera/application/lens_controller.dart';
import 'package:darkroom/features/camera/application/multi_exposure_controller.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:darkroom/features/camera/application/zoom_controller.dart';
import 'package:darkroom/features/camera/presentation/film_dials.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _Zoom extends ZoomController {
  @override
  ZoomState build() => const ZoomState(level: 1, min: 1, max: 2.5);

  @override
  void setLevel(double level) => state = state.copyWith(level: level.clamp(state.min, state.max));

  @override
  void settle() {}
}

class _Me extends MultiExposureController {
  @override
  MultiExposureState build() => const MultiExposureState();

  @override
  void toggle() => state = MultiExposureState(armed: !state.armed);
}

class _Lens extends FilmLensController {
  @override
  LensKind build() => LensKind.standard;

  @override
  void set(LensKind lens) => state = lens;
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
      overrides: [
        zoomProvider.overrideWith(_Zoom.new),
        exposureCompProvider.overrideWith(_Ev.new),
        multiExposureProvider.overrideWith(_Me.new),
        filmLensProvider.overrideWith(_Lens.new),
      ],
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
    // the ME chip, top right, arms multiple exposure
    await tester.tapAt(Offset(size.width - 30, 30));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(multiExposureProvider).armed, isTrue);
    await shoot('me');
    await tester.pump(const Duration(seconds: 3));
    // the lens ring, top left, opens the tray; a cap puts that lens on
    await tester.tapAt(const Offset(30, 30));
    await tester.pump(const Duration(milliseconds: 300));
    await shoot('lens_tray');
    await tester.tap(find.text('FISH'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(filmLensProvider), LensKind.fisheye);
    await tester.pump(const Duration(seconds: 3));
  });

  test('a double exposure blends two captures into one upright frame', () async {
    final dir = Directory.systemTemp.createTempSync('me');
    addTearDown(() => dir.deleteSync(recursive: true));
    String jpg(String name, int w, int h, int r, int g, int b) {
      final im = img.Image(width: w, height: h)..clear(img.ColorRgb8(r, g, b));
      final f = File('${dir.path}/$name.jpg')..writeAsBytesSync(img.encodeJpg(im));
      return f.path;
    }

    final a = jpg('a', 64, 48, 200, 40, 40), b = jpg('b', 48, 64, 40, 40, 200);
    await MultiExposure.blend(a, b, '${dir.path}/out.jpg');
    final out = img.decodeJpg(File('${dir.path}/out.jpg').readAsBytesSync())!;
    expect((out.width, out.height), (64, 48));
    final p = out.getPixel(32, 24);
    // both lights are in it
    expect(p.r, greaterThan(150));
    expect(p.b, greaterThan(100));
  });
}
