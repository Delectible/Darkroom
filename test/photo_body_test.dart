import 'package:camera/camera.dart';
import 'package:darkroom/core/device/physical_orientation.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/camera/presentation/photo_body.dart';
import 'package:darkroom/features/camera/presentation/whole_body.dart';
import 'package:darkroom/features/camera/presentation/widgets/camera_controls.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Mode extends AppModeNotifier {
  _Mode(this.mode);

  final AppMode mode;

  @override
  AppMode build() => mode;
}

class _Held extends PhysicalOrientationNotifier {
  @override
  DeviceOrientation build() => DeviceOrientation.portraitUp;
}

class _Lens extends LensNotifier {
  @override
  CameraLensDirection build() => CameraLensDirection.back;
}

/// The whole-body art (assets/body3): every image is bundled, 3D off gives
/// the classic bodies, the controls on it take taps, and a whole swap
/// draws without waiting on a single image (nothing pops in mid-turn).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every image the manifest names is bundled', () async {
    final art = await WholeArt.load();
    if (art == null) return markTestSkipped('no whole-body art bundled');
    for (final body in art.bodies.values) {
      final all = [
        body.rest,
        ...body.layers.values,
        for (final t in body.turns) ...[t.body, ...t.shutters.values],
      ];
      for (final a in all) {
        await rootBundle.load(a.path);
      }
    }
  });

  test('3D off (or no art) draws the classic bodies', () async {
    final art = await WholeArt.load();
    if (art == null) return markTestSkipped('no whole-body art bundled');
    for (final on in [true, false]) {
      final c = ProviderContainer(
        overrides: [
          initialGlobalSettingsProvider.overrideWithValue(GlobalSettings(controls3d: on)),
          wholeArtProvider.overrideWith((ref) async => art),
        ],
      );
      addTearDown(c.dispose);
      await c.read(wholeArtProvider.future);
      for (final mode in art.bodies.keys) {
        expect(c.read(wholeBodyProvider(mode)), on ? isNotNull : isNull);
        expect(c.read(photoBodyProvider(mode)), on ? isNotNull : isNull);
      }
    }
  });

  testWidgets('the rendered selfie-flip knob takes taps', (tester) async {
    final art = await tester.runAsync(WholeArt.load);
    if (art == null) return markTestSkipped('no whole-body art bundled');
    final mode = art.bodies.keys.first;
    final c = ProviderContainer(
      overrides: [
        initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
        wholeArtProvider.overrideWith((ref) async => art),
        appModeProvider.overrideWith(() => _Mode(mode)),
        lensProvider.overrideWith(_Lens.new),
        physicalOrientationProvider.overrideWith(_Held.new),
      ],
    );
    addTearDown(c.dispose);
    await tester.runAsync(() => c.read(wholeArtProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: LensFlipButton(enabled: true))),
        ),
      ),
    );
    await tester.pump();
    expect(c.read(photoBodyProvider(mode)), isNotNull);
    await tester.tap(find.byType(LensFlipButton));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.read(lensProvider), CameraLensDirection.front);
  });

  for (final mode in AppMode.values) {
    testWidgets('${mode.name} turns without waiting on an image', (tester) async {
      final art = await tester.runAsync(WholeArt.load);
      final body = art?.bodies[mode];
      if (art == null || body == null) return markTestSkipped('no ${mode.name} body bundled');
      tester.view.physicalSize = const Size(1236, 2745);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final deg = ValueNotifier<double>(0);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<double>(
            valueListenable: deg,
            builder: (context, d, _) => WholeTurn(art: art, body: body, deg: d, shutter: 'shutter'),
          ),
        ),
      );
      await tester.runAsync(() => art.precache(tester.element(find.byType(WholeTurn))));
      await tester.pump();
      WholeArt.lateFrames = 0;
      for (var d = 0.0; d <= body.turns.last.yaw; d += 1) {
        deg.value = d;
        await tester.pump(const Duration(milliseconds: 16));
        expect(WholeArt.lateFrames, 0, reason: '${mode.name} at $d degrees');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
