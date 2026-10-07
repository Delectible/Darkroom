import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/features/corkboard/presentation/projector_screen.dart';
import 'package:darkroom/features/viewer/presentation/media_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

/// The projector deck (reel + label, dial, drum counter, piano keys) at a
/// Pixel 9 Pro's width, in each transport state: no overflow, every key
/// reachable. `SHOTS=dir` saves each state.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();
  final item = MediaItem(
    id: 'r1',
    cameraId: 'super8',
    kind: MediaKind.video,
    status: MediaStatus.ready,
    fileName: 'Lake trip 26.MP4',
    capturedAt: DateTime(2026, 10, 6),
    readyAt: DateTime(2026, 10, 6),
    durationMs: 150000,
  );

  test('reel labels', () {
    expect(reelLabel(item), 'Lake trip 26');
  });

  for (final (name, shuttle, playing) in [
    ('stopped', ReelShuttle.none, false),
    ('playing', ReelShuttle.none, true),
    ('ffwd', ReelShuttle.forward, false),
  ]) {
    testWidgets('deck: $name', (tester) async {
      tester.view.physicalSize = const Size(1280, 2856);
      tester.view.devicePixelRatio = 3.1;
      addTearDown(tester.view.reset);
      final playback = ValueNotifier(
        const VideoPlayerValue(
          duration: Duration(minutes: 2, seconds: 30),
          position: Duration(seconds: 42),
          isInitialized: true,
        ).copyWith(isPlaying: playing),
      );
      var taps = 0, holds = 0, releases = 0;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF070605),
            body: Align(
              alignment: Alignment.bottomCenter,
              child: RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: const Color(0xFF070605),
                  child: ProjectorDeck(
                    playback: playback,
                    item: item,
                    run: const AlwaysStoppedAnimation(0),
                    shuttle: shuttle,
                    cuePos: shuttle == ReelShuttle.none ? null : const Duration(seconds: 80),
                    onRename: () => taps++,
                    onSeek: (_) => taps++,
                    onStart: () => taps++,
                    onRewind: (down) => down ? holds++ : releases++,
                    onPlay: () => taps++,
                    onForward: (down) => down ? holds++ : releases++,
                    onPrev: () => taps++,
                    onNext: () => taps++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      for (final key in ['START', 'PREV', 'NEXT']) {
        await tester.tap(find.text(key));
      }
      await tester.tap(find.text(playing ? 'PAUSE' : 'PLAY'));
      expect(taps, 4);
      // Rewind / fast forward run only while held.
      for (final key in ['REW', 'F.FWD']) {
        final g = await tester.startGesture(tester.getCenter(find.text(key)));
        await tester.pump(const Duration(milliseconds: 400));
        expect(releases, holds - 1);
        await g.up();
        await tester.pump();
      }
      expect((holds, releases), (2, 2));
      if (shots != null) {
        await tester.runAsync(() async {
          final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await ro.toImage(pixelRatio: 3.1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$shots/deck_$name.png').writeAsBytes(png!.buffer.asUint8List());
        });
      }
    });
  }
}
