import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/sd_card/presentation/win98/explorer_screen.dart';
import 'package:darkroom/features/sd_card/presentation/win98/win98_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every monitor finish (Tools > Options > Monitor) draws round the screen,
/// upright and turned. `SHOTS=dir` saves them.
void main() {
  final shots = Platform.environment['SHOTS'];
  for (final finish in MonitorFinish.all) {
    for (final land in [false, true]) {
      testWidgets('monitor ${finish.name}${land ? ' landscape' : ''}', (tester) async {
        tester.view.physicalSize = land ? const Size(2856, 1280) : const Size(1280, 2856);
        tester.view.devicePixelRatio = 3.1;
        addTearDown(tester.view.reset);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [win98MonitorProvider.overrideWith(() => _Monitor(finish.name))],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: RepaintBoundary(
                key: boundary,
                child: ExplorerMonitor(child: ColoredBox(color: W98.desktop)),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (shots != null) {
          await tester.runAsync(() async {
            final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await ro.toImage(pixelRatio: 1);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '$shots/monitor_${finish.name}${land ? '_land' : ''}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
          });
        }
      });
    }
  }
}

class _Monitor extends Win98MonitorNotifier {
  _Monitor(this.name);

  final String name;

  @override
  String? build() => name;
}
