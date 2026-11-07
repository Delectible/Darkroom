import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/device/battery.dart';
import 'package:darkroom/core/device/physical_orientation.dart';
import 'package:darkroom/core/processing/photo_pipeline.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/core/theme/retro_theme.dart';
import 'package:darkroom/features/camera/application/camera_session_controller.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/camera/application/capture_controller.dart';
import 'package:darkroom/features/camera/application/zoom_controller.dart';
import 'package:darkroom/features/camera/presentation/viewport.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Held extends PhysicalOrientationNotifier {
  _Held(this.o);

  final DeviceOrientation o;

  @override
  DeviceOrientation build() => o;
}

class _Selected extends SelectedCameraNotifier {
  _Selected(this.ids);

  final Map<AppMode, String> ids;

  @override
  Map<AppMode, String> build() => ids;
}

class _Mode extends AppModeNotifier {
  _Mode(this.m);

  final AppMode m;

  @override
  AppMode build() => m;
}

class _Flash extends FlashNotifier {
  @override
  Map<AppMode, FlashSetting> build() => {AppMode.film: FlashSetting.auto, AppMode.digital: FlashSetting.auto};
}

class _Lens extends LensNotifier {
  @override
  CameraLensDirection build() => CameraLensDirection.back;
}

class _Zoom extends ZoomController {
  @override
  ZoomState build() => const ZoomState(level: 1.4, min: 1, max: 2.5);
}

class _Session extends CameraSessionController {
  @override
  CameraSessionState build() => const CameraSessionState();
}

class _Capture extends CaptureController {
  @override
  CaptureState build() => const CaptureState();
}

/// The viewfinder's controls and readouts held each way round: they keep
/// their places and their words turn upright (SHOTS=dir saves the frames).
void main() {
  final shots = Platform.environment['SHOTS'];

  for (final mode in AppMode.values) {
    for (final (name, o) in [
      ('portrait', DeviceOrientation.portraitUp),
      ('left', DeviceOrientation.landscapeLeft),
      ('right', DeviceOrientation.landscapeRight),
      ('down', DeviceOrientation.portraitDown),
    ]) {
      testWidgets('${mode.name} viewfinder held $name', (tester) async {
        tester.view.physicalSize = const Size(1080, 1440);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              physicalOrientationProvider.overrideWith(() => _Held(o)),
              selectedCameraProvider.overrideWith(
                () => _Selected({AppMode.film: 'gold200', AppMode.digital: 'ccd2003'}),
              ),
              appModeProvider.overrideWith(() => _Mode(mode)),
              lensProvider.overrideWith(_Lens.new),
              flashProvider.overrideWith(_Flash.new),
              cameraSessionProvider.overrideWith(_Session.new),
              zoomProvider.overrideWith(_Zoom.new),
              captureControllerProvider.overrideWith(_Capture.new),
              initialCameraSettingsProvider.overrideWithValue(const {}),
              filmItemsProvider.overrideWith((ref) => Stream.value(const <MediaItem>[])),
              sdCardItemsProvider.overrideWith((ref) => Stream.value(const <MediaItem>[])),
              batteryLevelProvider.overrideWith((ref) => Stream.value(80)),
              initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RetroPalette.forMode(mode).toTheme(),
              home: RepaintBoundary(
                key: key,
                child: const ColoredBox(
                  color: Color(0xFF2A2724),
                  child: Padding(padding: EdgeInsets.all(14), child: CameraViewport()),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        if (shots != null) {
          final png = await tester.runAsync(() async {
            final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await ro.toImage(pixelRatio: 1.5);
            return image.toByteData(format: ui.ImageByteFormat.png);
          });
          File('$shots/vf_${mode.name}_$name.png').writeAsBytesSync(png!.buffer.asUint8List());
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
