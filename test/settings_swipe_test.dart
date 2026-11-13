import 'package:camera/camera.dart';
import 'package:darkroom/core/device/physical_orientation.dart';
import 'package:darkroom/core/processing/photo_pipeline.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:darkroom/features/settings/presentation/settings_sheet.dart';
import 'package:material_ui/material_ui.dart';
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

/// The digital menu closes when pulled down, but only by a pull that starts
/// with its list at the top: one that starts mid-list just scrolls up.
void main() {
  testWidgets('digital settings: pull down to close, not mid-list', (tester) async {
    // (a short phone: the Setup list scrolls)
    tester.view.physicalSize = const Size(1080, 1500);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          physicalOrientationProvider.overrideWith(() => _Held(DeviceOrientation.portraitUp)),
          selectedCameraProvider.overrideWith(_Selected.new),
          flashProvider.overrideWith(_Flash.new),
          appModeProvider.overrideWith(() => _Mode(AppMode.digital)),
          lensProvider.overrideWith(_Lens.new),
          initialCameraSettingsProvider.overrideWithValue(const {}),
          initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(onPressed: () => showSettingsSheet(context), child: const Text('open')),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> open() async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('DIGITAL SETTINGS'), findsOneWidget);
    }

    await open();
    await tester.tap(find.text('SETUP'));
    await tester.pumpAndSettle();
    final list = find.text('3D CAMERA BODIES');
    final scroll = tester.state<ScrollableState>(
      find.ancestor(of: list, matching: find.byType(Scrollable)).first,
    );
    expect(scroll.position.maxScrollExtent, greaterThan(20), reason: 'the list should scroll here');

    // Scrolled down, then one long pull down: back to the top, still open.
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.drag(list, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, 0);
    expect(find.text('DIGITAL SETTINGS'), findsOneWidget);

    // At the top now: a pull down closes it.
    await tester.drag(find.text('3D CAMERA BODIES'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('DIGITAL SETTINGS'), findsNothing);

    // The header (no list under the finger): a pull down closes it too;
    // a short one springs back.
    await open();
    await tester.drag(find.text('DIGITAL SETTINGS'), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(find.text('DIGITAL SETTINGS'), findsOneWidget);
    await tester.drag(find.text('DIGITAL SETTINGS'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('DIGITAL SETTINGS'), findsNothing);
  });
}
