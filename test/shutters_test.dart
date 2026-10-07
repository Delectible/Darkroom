import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/theme/retro_theme.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/camera/application/capture_controller.dart';
import 'package:darkroom/features/camera/presentation/widgets/camera_controls.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:darkroom/features/camera/presentation/body_swap.dart' show BodyYaw;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Selected extends SelectedCameraNotifier {
  _Selected(this.ids);

  final Map<AppMode, String> ids;

  @override
  Map<AppMode, String> build() => ids;
}

class _Capture extends CaptureController {
  @override
  CaptureState build() => const CaptureState();

  @override
  Future<void> shutter() async {}
}

class _Mode extends AppModeNotifier {
  _Mode(this.mode);

  final AppMode mode;

  @override
  AppMode build() => mode;
}

/// Each body's shutter (compact key, chrome release + advance lever, Super 8
/// RUN button, camcorder key) pumps, fires and runs its stroke without
/// errors. `SHOTS=dir` saves them side by side.
void main() {
  testWidgets('shutters', (tester) async {
    final key = GlobalKey();
    Widget one(AppMode mode, String id) => ProviderScope(
      overrides: [
        appModeProvider.overrideWith(() => _Mode(mode)),
        selectedCameraProvider.overrideWith(() => _Selected({AppMode.film: id, AppMode.digital: id})),
        captureControllerProvider.overrideWith(_Capture.new),
      ],
      child: Theme(
        data: RetroPalette.forMode(mode).toTheme(),
        child: ColoredBox(
          color: RetroPalette.forMode(mode).body,
          child: const Padding(padding: EdgeInsets.all(10), child: ShutterButton()),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                one(AppMode.digital, 'ccd2003'),
                one(AppMode.film, 'portra400'),
                one(AppMode.film, 'super8'),
                one(AppMode.digital, 'camcorder90'),
                // Tipped, as mid-toss: the caps slide against their bases.
                BodyYaw(yaw: 0.7, child: one(AppMode.film, 'super8')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // Let the sprite layers decode.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
    }
    // Fire the film one and catch its lever mid-swing.
    await tester.tap(find.byType(ShutterButton).at(1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    final shots = Platform.environment['SHOTS'];
    if (shots != null) {
      await tester.runAsync(() async {
        final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await ro.toImage(pixelRatio: 3);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$shots/shutters.png').writeAsBytes(png!.buffer.asUint8List());
      });
    }
  });
}
