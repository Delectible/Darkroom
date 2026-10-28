import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/features/corkboard/presentation/projector_room.dart';
import 'package:darkroom/features/corkboard/presentation/projector_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

/// The projector's room (wood wall, screen, console with lamp and plant)
/// with the deck, upright and turned, for 4:3 Super 8, 2.20 and tall
/// reels: the screen stays inside the room and above the floor, nothing
/// overflows. `SHOTS=dir` saves each (`SRC=photo.jpg` puts a picture on
/// the screen).
void main() {
  final shots = Platform.environment['SHOTS'];
  final src = Platform.environment['SRC'];

  test('layout: the biggest picture, the console below it, never lifted off the floor', () {
    for (final size in const [Size(412, 560), Size(515, 380), Size(380, 300), Size(560, 330)]) {
      for (final aspect in [4 / 3, 2.2, 9 / 16]) {
        final l = ProjectorRoom.layout(size, aspect);
        final room = Offset.zero & size;
        expect(room.contains(l.screen.topLeft) && room.contains(l.screen.bottomRight), isTrue);
        expect(l.screen.width / l.screen.height, closeTo(aspect, 0.01));
        // As big as the room allows for this shape (14 side, 12 top, 8 bottom).
        final aw = size.width - 28, ah = size.height - 20;
        final maxW = aw / aspect <= ah ? aw : ah * aspect;
        expect(l.screen.width, closeTo(maxW, 0.6), reason: '$size $aspect');
        // The lamp and the plant stay clear of the picture.
        final above = l.console.height * 362 / 640;
        expect(l.console.top + above * 0.08, greaterThanOrEqualTo(l.screen.bottom), reason: '$size $aspect');
        // Standing on the floor or lower, never floating up.
        expect(l.console.bottom, greaterThanOrEqualTo(size.height - 8.5), reason: '$size $aspect');
      }
    }
  });

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

  for (final (name, land, aspect) in [
    ('portrait_43', false, 4 / 3),
    ('portrait_220', false, 2.2),
    ('portrait_tall', false, 9 / 16),
    ('landscape_43', true, 4 / 3),
    ('landscape_220', true, 2.2),
  ]) {
    testWidgets('room: $name', (tester) async {
      tester.view.physicalSize = land ? const Size(2836, 1280) : const Size(1280, 2836);
      tester.view.devicePixelRatio = 3.1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      final playback = ValueNotifier(
        const VideoPlayerValue(
          duration: Duration(minutes: 2, seconds: 30),
          position: Duration(seconds: 42),
          isInitialized: true,
        ).copyWith(isPlaying: true),
      );
      final Widget picture = src == null
          ? const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFFB89A6A), Color(0xFF6E5A40)]),
              ),
            )
          : Image.file(File(src), fit: BoxFit.cover);
      if (src != null) {
        await tester.runAsync(() async {
          final el = tester.binding.rootElement!;
          await precacheImage(FileImage(File(src)), el);
        });
      }
      final room = ProjectorRoom(aspect: aspect, picture: picture, run: const AlwaysStoppedAnimation(0));
      final deck = ProjectorDeck(
        playback: playback,
        item: item,
        run: const AlwaysStoppedAnimation(0),
        shuttle: ReelShuttle.none,
        cuePos: null,
        onRename: () {},
        onSeek: (_) {},
        onStart: () {},
        onRewind: (_) {},
        onPlay: () {},
        onForward: (_) {},
      );
      const header = SizedBox(
        height: 56,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: 56),
            child: Text('Lake trip 26', style: TextStyle(color: Color(0xFFF3E3C8), fontWeight: FontWeight.w800)),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              backgroundColor: const Color(0xFF070605),
              body: land
                  ? Row(
                      children: [
                        Expanded(child: room),
                        SizedBox(
                          width: 400,
                          child: Column(children: [header, const Spacer(), deck, const SizedBox(height: 48)]),
                        ),
                      ],
                    )
                  : Column(children: [header, Expanded(child: room), deck, const SizedBox(height: 52)]),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      if (src != null) await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (shots != null) {
        await tester.runAsync(() async {
          final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await ro.toImage(pixelRatio: 3.1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$shots/room_$name.png').writeAsBytes(png!.buffer.asUint8List());
        });
      }
    });
  }
}
