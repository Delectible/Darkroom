// Desktop preview of the live 3D bodies (Flutter GPU), for checking the
// models, their lighting and the face's widgets on them without a phone:
//
//   flutter create --platforms linux .        (local only, not committed)
//   (linux/runner/my_application.cc: fl_dart_project_set_enable_flutter_gpu)
//   flutter build linux --debug -t tool/live3d/preview.dart
//   MODE=film POSES=0,30 build/linux/x64/debug/bundle/darkroom
//
// Each pose prints `SHOT n` on stderr once it has drawn (screenshot it).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import 'package:darkroom/features/camera/presentation/body_swap.dart';
import 'package:darkroom/features/camera/presentation/whole_body.dart';
import 'package:darkroom/features/camera/presentation/whole_face.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _Mode extends AppModeNotifier {
  _Mode(this.mode);

  final AppMode mode;

  @override
  AppMode build() => mode;
}

class _Selected extends SelectedCameraNotifier {
  @override
  Map<AppMode, String> build() => {
    AppMode.film: Platform.environment['FILM'] ?? 'portra400',
    AppMode.digital: Platform.environment['DIGITAL'] ?? 'ccd2003',
  };
}

class _Held extends PhysicalOrientationNotifier {
  @override
  DeviceOrientation build() => DeviceOrientation.portraitUp;
}

class _Lens extends LensNotifier {
  @override
  CameraLensDirection build() => CameraLensDirection.back;
}

class _Flash extends FlashNotifier {
  @override
  Map<AppMode, FlashSetting> build() {
    final f = FlashSetting.values.asNameMap()[Platform.environment['FLASH']] ?? FlashSetting.auto;
    return {AppMode.film: f, AppMode.digital: f};
  }
}

class _Name extends UserNameNotifier {
  @override
  String? build() => null;
}

class _Finish extends BodyFinishNotifier {
  @override
  String? build() => Platform.environment['FINISH'];
}

class _Session extends CameraSessionController {
  @override
  CameraSessionState build() => const CameraSessionState(hasFrontCamera: true);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final mode = env['MODE'] == 'digital' ? AppMode.digital : AppMode.film;
  final art = await WholeArt.load();
  if (art == null) {
    stderr.writeln('no 3D art');
    exit(1);
  }
  final body = art.bodies[mode]!;
  final pose = ValueNotifier<double>(0);
  runApp(
    ProviderScope(
      overrides: [
        wholeArtProvider.overrideWithValue(AsyncValue.data(art)),
        initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
        initialCameraSettingsProvider.overrideWithValue(const {}),
        physicalOrientationProvider.overrideWith(_Held.new),
        appModeProvider.overrideWith(() => _Mode(mode)),
        selectedCameraProvider.overrideWith(_Selected.new),
        lensProvider.overrideWith(_Lens.new),
        userNameProvider.overrideWith(_Name.new),
        flashProvider.overrideWith(_Flash.new),
        bodyFinishProvider.overrideWith(_Finish.new),
        cameraSessionProvider.overrideWith(_Session.new),
        filmItemsProvider.overrideWith((ref) => Stream.value(const <MediaItem>[])),
        sdCardItemsProvider.overrideWith((ref) => Stream.value(const <MediaItem>[])),
        batteryLevelProvider.overrideWith((ref) => Stream.value(80)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RetroPalette.forMode(mode).toTheme(),
        home: Scaffold(
          backgroundColor: const Color(0xFF0C0B0A),
          body: ValueListenableBuilder<double>(
            valueListenable: pose,
            builder: (context, deg, _) => SwapBody(
              mode: mode,
              capSide: deg == 0 ? 0 : (mode == AppMode.film ? 1 : -1),
              pose: deg == 0
                  ? BodyPose.rest
                  : BodyPose(dx: 0, dy: 0, tilt: deg * math.pi / 180, roll: 0, scale: 0.92, swing: 0.4),
              rendered: RenderedBody(
                art: art,
                body: body,
                shutter: 'shutter',
                viewfinder: const ColoredBox(color: Color(0xFF6A8CAF)),
              ),
              face: WholeFace(
                art: art,
                body: body,
                mode: mode,
                onSettings: () {},
                onOpenSelector: () {},
                onOpenGallery: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final poses = (env['POSES'] ?? '0,30').split(',').map(double.parse).toList();
  for (final (i, deg) in poses.indexed) {
    pose.value = deg;
    await Future<void>.delayed(const Duration(seconds: 4));
    stderr.writeln('SHOT $i');
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  exit(0);
}
