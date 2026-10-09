import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/device/physical_orientation.dart';
import 'package:darkroom/core/processing/photo_pipeline.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/core/theme/retro_theme.dart';
import 'package:darkroom/core/device/battery.dart';
import 'package:darkroom/features/camera/application/camera_session_controller.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/camera/presentation/whole_body.dart';
import 'package:darkroom/features/camera/presentation/whole_face.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Mode extends AppModeNotifier {
  _Mode(this.mode);

  final AppMode mode;

  @override
  AppMode build() => mode;
}

class _Selected extends SelectedCameraNotifier {
  @override
  Map<AppMode, String> build() => {AppMode.film: 'portra400', AppMode.digital: 'ccd2003'};
}

class _Flash extends FlashNotifier {
  @override
  Map<AppMode, FlashSetting> build() => {AppMode.film: FlashSetting.auto, AppMode.digital: FlashSetting.auto};
}

class _Lens extends LensNotifier {
  @override
  CameraLensDirection build() => CameraLensDirection.back;
}

class _Held extends PhysicalOrientationNotifier {
  @override
  DeviceOrientation build() => DeviceOrientation.portraitUp;
}

class _Session extends CameraSessionController {
  @override
  CameraSessionState build() => const CameraSessionState(hasFrontCamera: true);
}

/// The camera face of the 3D bodies (assets/body3d; the model itself needs
/// Flutter GPU, so a dark stand-in here) at the sizes of real phones:
/// everything fits (no overflow) and the viewfinder fills the frame's
/// screen on every height (the middle trims). `SHOTS=dir` saves them.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  final phones = {
    'pixel9pro': const Size(412, 915),
    's10plus': const Size(412, 869),
    'iphone15': const Size(393, 852),
    'tall': const Size(411, 960),
  };

  Widget app(AppMode mode, Widget child, WholeArt art) => ProviderScope(
    overrides: [
      wholeArtProvider.overrideWithValue(AsyncValue.data(art)),
      initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
      initialCameraSettingsProvider.overrideWithValue(const {}),
      physicalOrientationProvider.overrideWith(_Held.new),
      appModeProvider.overrideWith(() => _Mode(mode)),
      selectedCameraProvider.overrideWith(_Selected.new),
      flashProvider.overrideWith(_Flash.new),
      lensProvider.overrideWith(_Lens.new),
      cameraSessionProvider.overrideWith(_Session.new),
      filmItemsProvider.overrideWith((ref) => Stream.value(const <MediaItem>[])),
      sdCardItemsProvider.overrideWith((ref) => Stream.value(const <MediaItem>[])),
      batteryLevelProvider.overrideWith((ref) => Stream.value(80)),
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RetroPalette.forMode(mode).toTheme(),
        home: Scaffold(backgroundColor: const Color(0xFF0C0B0A), body: child),
      ),
    ),
  );

  Future<void> shoot(WidgetTester tester, String name) async {
    if (shots == null) return;
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/$name.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  for (final mode in AppMode.values) {
    for (final MapEntry(key: phone, value: size) in phones.entries) {
      testWidgets('${mode.name} face on $phone', (tester) async {
        final art = await tester.runAsync(() => WholeArt.load(scenes: false));
        final body = art?.bodies[mode];
        if (art == null || body == null) return markTestSkipped('no whole-body art bundled');
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          app(
            mode,
            WholeFace(
              art: art,
              body: body,
              mode: mode,
              onSettings: () {},
              onOpenSelector: () {},
              onOpenGallery: () {},
            ),
            art,
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        // The viewfinder fills the frame's screen whatever the height.
        final fit = DesignFit(art, Size(art.design.width, size.height * art.design.width / size.width));
        expect(fit.rect(body.layout.screen).height, greaterThan(400));
        await shoot(tester, 'whole_${mode.name}_$phone');
      });
    }
  }
}
