import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/features/camera/presentation/viewfinder_shut.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The viewfinder shutting while the camera is off: film (mirror up) and
/// digital (LCD sleep), closing over a still and opening over nothing (the
/// live picture under it). `SHOTS=dir` saves each stage.
void main() {
  final shots = Platform.environment['SHOTS'];

  ui.Image scene() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const r = Rect.fromLTWH(0, 0, 360, 270);
    c.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C3A62), Color(0xFFB0687A), Color(0xFFF0A868), Color(0xFF1D2230)],
          stops: [0, 0.4, 0.62, 0.63],
        ).createShader(r),
    );
    c.drawCircle(const Offset(230, 150), 26, Paint()..color = const Color(0xFFFFE2B0));
    c.drawRect(const Rect.fromLTWH(70, 120, 8, 80), Paint()..color = const Color(0xFF12151D));
    c.drawCircle(const Offset(74, 112), 26, Paint()..color = const Color(0xFF12151D));
    return rec.endRecording().toImageSync(360, 270);
  }

  for (final mode in AppMode.values) {
    testWidgets('${mode.name} viewfinder shuts and opens', (tester) async {
      final still = scene();
      final shut = AnimationController(vsync: const TestVSync(), duration: ViewfinderShutter.close);
      ViewfinderShutter.shut = shut;
      final key = GlobalKey();
      ui.Image? showing = still;
      late StateSetter set;
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 360,
              height: 270,
              child: ColoredBox(
                // what's under it: the live picture, opening
                color: const Color(0xFF6A8CA8),
                child: StatefulBuilder(
                  builder: (context, s) {
                    set = s;
                    return ViewfinderShut(mode: mode, still: showing);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> shoot(String name) async {
        await tester.pump();
        if (shots == null) return;
        await tester.runAsync(() async {
          final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await ro.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$shots/shut_${mode.name}_$name.png').writeAsBytes(png!.buffer.asUint8List());
        });
      }

      for (final v in [0.0, 0.3, 0.55, 0.8, 1.0]) {
        shut.value = v;
        await shoot('close_${(v * 100).round()}');
      }
      // live again: the still goes, it opens over the picture
      set(() => showing = null);
      unawaited(shut.reverse());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      await shoot('open_mid');
      await tester.pumpAndSettle();
      expect(shut.value, 0);
      expect(tester.takeException(), isNull);
      ViewfinderShutter.shut = kAlwaysDismissedAnimation;
      shut.dispose();
    });
  }
}

void unawaited(Future<void> f) {}
