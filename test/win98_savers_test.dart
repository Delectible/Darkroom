import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/features/sd_card/presentation/win98/explorer_screen.dart';
import 'package:darkroom/features/sd_card/presentation/win98/win98_display.dart';
import 'package:darkroom/features/sd_card/presentation/win98/win98_savers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Darkroom 98's screen savers run (a pipes screen fills and starts over),
/// the monitor's settings survive a save, and its colour matrix is only
/// there when something changed. `SHOTS=dir` saves a frame of each saver,
/// and the monitor as a green CRT.
void main() {
  final shots = Platform.environment['SHOTS'];

  Future<void> shoot(WidgetTester tester, GlobalKey key, String name) async {
    if (shots == null) return;
    await tester.runAsync(() async {
      final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/$name.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  for (final saver in [Win98Saver.pipes, Win98Saver.stars, Win98Saver.text]) {
    testWidgets('screen saver ${saver.name} runs', (tester) async {
      tester.view.physicalSize = const Size(1280, 2856);
      tester.view.devicePixelRatio = 3.1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: RepaintBoundary(
              key: key,
              child: ExplorerMonitor(
                child: ScreenSaverView(saver: saver, text: 'Darkroom 98', seed: 7),
              ),
            ),
          ),
        ),
      );
      // A minute of it, ten frames a second: pipes fill the box and clear.
      for (var i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (i == 80) await shoot(tester, key, 'saver_${saver.name}');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('monitor: green CRT, knobs and degauss', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    tester.view.padding = const FakeViewPadding(top: 150, bottom: 75);
    addTearDown(tester.view.reset);
    addTearDown(() => Win98Display.current.value = const Win98Display());
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: const ExplorerMonitor(
              child: ColoredBox(
                color: Color(0xFF008080),
                child: Center(
                  child: Text('Darkroom 98', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(ExplorerMonitor)));
    container
        .read(win98DisplayProvider.notifier)
        .set(const Win98Display(crt: true, tint: Win98Tint.green), save: false);
    await tester.pump();
    // Turn the brightness knob up a notch (its right half).
    final knob = find.bySemanticsLabel('Brightness');
    expect(knob, findsOneWidget);
    final r = tester.getRect(knob);
    await tester.tapAt(r.centerRight - const Offset(2, 0));
    await tester.pump();
    expect(container.read(win98DisplayProvider).brightness, closeTo(0.55, 1e-9));
    expect(find.text('BRIGHTNESS'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Degauss'));
    await tester.pump(const Duration(milliseconds: 200));
    await shoot(tester, key, 'monitor_degauss');
    await tester.pump(const Duration(seconds: 2));
    await shoot(tester, key, 'monitor_green_crt');
    expect(find.text('BRIGHTNESS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('settings: saved and read back; no colour layer until something changes', () {
    const d = Win98Display(
      crt: true,
      res: Win98Res.vga,
      brightness: 0.3,
      contrast: 0.8,
      tint: Win98Tint.amber,
      largeFonts: true,
      saver: Win98Saver.text,
      saverText: 'Hello',
      saverWait: 5,
    );
    final json =
        '{"crt":true,"res":"vga","brightness":0.3,"contrast":0.8,"tint":"amber","largeFonts":true,'
        '"saver":"text","saverText":"Hello","saverWait":5}';
    expect(Win98Display.fromJson(json), d);
    expect(Win98Display.fromJson('nonsense'), const Win98Display());
    expect(const Win98Display().matrix, isNull);
    // A green screen turns white green and leaves black (nearly) black.
    final m = const Win98Display(tint: Win98Tint.green).matrix!;
    double out(int row, double v) =>
        m[row * 5] * v + m[row * 5 + 1] * v + m[row * 5 + 2] * v + m[row * 5 + 4];
    expect(out(1, 255), greaterThan(out(0, 255) * 2));
    expect(out(1, 0), lessThan(30));
    // 640 x 480 is chunkier than 1024 x 768.
    const phone = Size(412, 915);
    expect(
      const Win98Display(res: Win98Res.vga).scaleFor(phone),
      greaterThan(const Win98Display(res: Win98Res.xga).scaleFor(phone)),
    );
  });
}
