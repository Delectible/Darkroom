import 'dart:io';

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

/// The 3D bodies (assets/body3d): the manifest's models and studio are
/// bundled, 3D off gives the classic bodies, and the controls on the face
/// take taps. (The models themselves need Flutter GPU: not in tests.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the manifest, studio and models are there', () async {
    final art = await WholeArt.load(scenes: false);
    expect(art, isNotNull);
    await rootBundle.load('${WholeArt.root}/studio.hdr');
    for (final mode in AppMode.values) {
      final body = art!.bodies[mode]!;
      expect(body.layout.parts, isNotEmpty);
      expect(body.alt, mode == AppMode.film ? 'run' : 'rec');
      // the models are converted at build time (hook/build.dart), not bundled raw
      expect(File('${WholeArt.root}/${mode.name}.glb').existsSync(), isTrue);
    }
  });

  test('3D off (or no art) draws the classic bodies', () async {
    final art = await WholeArt.load(scenes: false);
    for (final on in [true, false]) {
      final c = ProviderContainer(
        overrides: [
          initialGlobalSettingsProvider.overrideWithValue(GlobalSettings(controls3d: on)),
          wholeArtProvider.overrideWith((ref) async => art),
        ],
      );
      addTearDown(c.dispose);
      await c.read(wholeArtProvider.future);
      for (final mode in art!.bodies.keys) {
        expect(c.read(wholeBodyProvider(mode)), on ? isNotNull : isNull);
        expect(c.read(photoBodyProvider(mode)), on ? isNotNull : isNull);
      }
    }
  });

  testWidgets('the selfie-flip knob takes taps', (tester) async {
    final art = await tester.runAsync(() => WholeArt.load(scenes: false));
    final mode = art!.bodies.keys.first;
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
}
