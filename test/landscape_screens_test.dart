import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:darkroom/core/device/physical_orientation.dart';
import 'package:darkroom/core/processing/photo_pipeline.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/camera/presentation/widgets/camera_controls.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:darkroom/features/cameras/presentation/stock_selector_screen.dart';
import 'package:darkroom/features/settings/presentation/settings_sheet.dart';
import 'package:darkroom/core/theme/retro_theme.dart';
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
  Map<AppMode, String> build() => {AppMode.film: 'portra400', AppMode.digital: 'ccd2003'};

  @override
  Future<void> select(AppMode mode, String id) async => state = {...state, mode: id};
}

class _Flash extends FlashNotifier {
  @override
  Map<AppMode, FlashSetting> build() => {AppMode.film: FlashSetting.auto, AppMode.digital: FlashSetting.auto};
}

class _Mode extends AppModeNotifier {
  @override
  AppMode build() => AppMode.film;
}

class _Lens extends LensNotifier {
  @override
  CameraLensDirection build() => CameraLensDirection.back;
}

/// Picker, settings and the camera's top keys, upright and held sideways:
/// no overflow in either (SHOTS=dir saves the frames).
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);
  }

  Widget app(DeviceOrientation o, Widget home) => ProviderScope(
    overrides: [
      physicalOrientationProvider.overrideWith(() => _Held(o)),
      selectedCameraProvider.overrideWith(_Selected.new),
      flashProvider.overrideWith(_Flash.new),
      appModeProvider.overrideWith(_Mode.new),
      lensProvider.overrideWith(_Lens.new),
      initialCameraSettingsProvider.overrideWithValue(const {}),
      initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RetroPalette.forMode(AppMode.film).toTheme(),
        home: home,
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

  for (final (name, o) in [
    ('portrait', DeviceOrientation.portraitUp),
    ('landscape', DeviceOrientation.landscapeLeft),
  ]) {
    testWidgets('picker $name', (tester) async {
      await phone(tester);
      await tester.pumpWidget(app(o, const StockSelectorScreen(mode: AppMode.film)));
      await tester.pumpAndSettle();
      await shoot(tester, 'picker_$name');
      // Filter list opens the right way up too.
      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      expect(find.text('Black & White'), findsOneWidget);
      await shoot(tester, 'picker_filter_$name');
    });

    testWidgets('settings $name', (tester) async {
      await phone(tester);
      await tester.pumpWidget(
        app(
          o,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(onPressed: () => showSettingsSheet(context), child: const Text('open')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Darkroom development'), findsOneWidget);
      await shoot(tester, 'settings_$name');
    });

    testWidgets('top keys $name', (tester) async {
      await phone(tester);
      await tester.pumpWidget(
        app(
          o,
          Scaffold(
            backgroundColor: const Color(0xFF3A2A20),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const FlashButton(),
                    const SizedBox(width: 8),
                    AspectButton(onCycle: () {}),
                    const Spacer(),
                    const LensFlipButton(enabled: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await shoot(tester, 'keys_$name');
    });
  }
}
