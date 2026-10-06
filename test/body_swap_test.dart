import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/features/camera/presentation/body_swap.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The film <-> digital toss, frozen at points along the way at a Pixel 9
/// Pro's size: it lays out and paints, and the live body keeps its element
/// as it changes slot. `SHOTS=dir` saves each frame.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  Future<void> pump(
    WidgetTester tester,
    double p, {
    required bool film,
    required bool committed,
    bool rest = false,
  }) {
    final from = film ? AppMode.film : AppMode.digital;
    final to = film ? AppMode.digital : AppMode.film;
    final dir = film ? -1 : 1;
    final live = Container(
      key: const ValueKey('face'),
      color: const Color(0x00000000),
      child: BodyStandIn(mode: committed ? to : from),
    );
    return tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: const Color(0xFF0C0B0A),
            child: SwapStage(
              progress: p,
              dir: dir,
              leaving: committed ? BodyStandIn(mode: from) : live,
              leavingMode: from,
              arriving: rest ? null : (committed ? live : BodyStandIn(mode: to)),
              arrivingMode: to,
              liveArriving: committed,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (shots == null) return;
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/swap_$name.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  testWidgets('bodies pass each other with their ends and straps', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);
    for (final film in [true, false]) {
      for (final (p, committed) in [(0.18, false), (0.42, false), (0.6, true), (0.85, true), (1.04, true)]) {
        await pump(tester, p, film: film, committed: committed);
        expect(tester.takeException(), isNull);
        await shoot(tester, '${film ? 'film' : 'digital'}_${(p * 100).round()}');
      }
    }
  });

  testWidgets('the live body keeps its state from rest, through the drag, to the commit', (tester) async {
    await pump(tester, 0, film: true, committed: false, rest: true);
    final before = tester.element(find.byKey(const ValueKey('face')));
    await pump(tester, 0.4, film: true, committed: false);
    expect(tester.element(find.byKey(const ValueKey('face'))), same(before));
    await pump(tester, 0.4, film: true, committed: true);
    expect(tester.element(find.byKey(const ValueKey('face'))), same(before));
  });
}
