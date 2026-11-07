import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:darkroom/core/device/physical_orientation.dart';
import 'package:darkroom/core/processing/photo_pipeline.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/core/theme/retro_theme.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:darkroom/features/settings/presentation/settings_sheet.dart';
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
  @override
  Map<AppMode, String> build() => {AppMode.film: 'gold200', AppMode.digital: 'ccd2003'};
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

/// Settings dressed per camera: the film owner's manual, the digital
/// camera's menu. Each opens, steps to another camera, and fits upright and
/// sideways (SHOTS=dir saves the frames).
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  for (final mode in AppMode.values) {
    for (final (name, o) in [
      ('portrait', DeviceOrientation.portraitUp),
      ('landscape', DeviceOrientation.landscapeLeft),
    ]) {
      testWidgets('${mode.name} settings $name', (tester) async {
        tester.view.physicalSize = const Size(1280, 2856);
        tester.view.devicePixelRatio = 3.1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              physicalOrientationProvider.overrideWith(() => _Held(o)),
              selectedCameraProvider.overrideWith(_Selected.new),
              flashProvider.overrideWith(_Flash.new),
              appModeProvider.overrideWith(() => _Mode(mode)),
              lensProvider.overrideWith(_Lens.new),
              initialCameraSettingsProvider.overrideWithValue(const {}),
              initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
            ],
            child: RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RetroPalette.forMode(mode).toTheme(),
                home: Builder(
                  builder: (context) => Scaffold(
                    backgroundColor: const Color(0xFF0C0B0A),
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () => showSettingsSheet(context),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (mode == AppMode.film) {
          expect(find.text('FILM SETTINGS'), findsOneWidget);
          expect(find.text('GOLDEN 200'), findsOneWidget);
          await tester.tap(find.bySemanticsLabel('Next film'));
          await tester.pumpAndSettle();
          expect(find.text('GOLDEN 200'), findsNothing);
          await tester.tap(find.bySemanticsLabel('Previous film'));
          await tester.pumpAndSettle();
        } else {
          expect(find.text('DIGITAL SETTINGS'), findsOneWidget);
          expect(find.text('FRAME SHAPE'), findsOneWidget);
        }
        if (shots != null) {
          await tester.runAsync(() async {
            final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await ro.toImage(pixelRatio: 1);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$shots/settings_${mode.name}_$name.png').writeAsBytes(png!.buffer.asUint8List());
          });
        }
        if (mode == AppMode.digital) {
          // the other tabs open, and fit
          for (final tab in ['SETUP', 'PRO']) {
            await tester.tap(find.text(tab));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: tab);
            if (shots != null && name == 'portrait') {
              await tester.runAsync(() async {
                final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
                final image = await ro.toImage(pixelRatio: 1);
                final png = await image.toByteData(format: ui.ImageByteFormat.png);
                await File(
                  '$shots/settings_digital_${tab.toLowerCase()}.png',
                ).writeAsBytes(png!.buffer.asUint8List());
              });
            }
          }
        }
      });
    }
  }
}
