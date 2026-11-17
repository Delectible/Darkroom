import 'dart:ui' as ui;

import 'dart:io';
import 'dart:typed_data';

import 'package:darkroom/features/studio/studio_flip_frames.dart';
import 'package:darkroom/features/studio/studio_make.dart';
import 'package:darkroom/features/studio/studio_render.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _photo(int i) {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawColor(ui.Color.fromARGB(255, 40 * i, 120, 200 - 30 * i), ui.BlendMode.src);
  return rec.endRecording().toImage(80, 100);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stapled: cues, keyframes and every moment drawn', () async {
    final photos = [for (var i = 0; i < 5; i++) await _photo(i)];
    final f = FlipFrames(
      photos: photos,
      paper: StudioPaper.values.first,
      style: FlipStyle.stapled,
      pageMs: 700,
    );
    final cues = f.cues();
    expect(cues.where((c) => c.$2 == FlipCue.turn).length, 4);
    expect(cues.where((c) => c.$2 == FlipCue.riffle).length, 1);
    expect(cues.where((c) => c.$2 == FlipCue.back).length, 4);
    // the keyframes cover the loop exactly, in order
    final keys = f.keyframes();
    var at = 0.0;
    for (final k in keys) {
      expect(k.at, closeTo(at, 0.01));
      at += k.hold;
    }
    expect(at, closeTo(f.totalMs, 0.5));
    for (var t = 0.0; t < f.totalMs; t += 47) {
      final rec = ui.PictureRecorder();
      f.paint(ui.Canvas(rec), const ui.Size(540, 675), t);
      rec.endRecording().dispose();
    }
    clearStapledTextures();
    expect(FlipStyle.standard, FlipStyle.stapled);
  });
  test('the video\'s page sounds: read, mixed, a WAV of the loop\'s length', () {
    final takes = [
      for (final f in Directory(
        'assets/sfx',
      ).listSync().whereType<File>().where((f) => f.path.contains('page_turn_')))
        StudioMake.pcmOf(f.readAsBytesSync()),
    ];
    expect(takes.length, 8);
    expect(takes.every((t) => t.length > 10000), isTrue);
    final wav = StudioMake.mixFlipSound(takes, [
      (100, FlipCue.turn.index),
      (900, FlipCue.riffle.index),
      (900, FlipCue.back.index),
      (1010, FlipCue.back.index),
    ], 2000);
    final bd = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(bd.getUint32(40, Endian.little), 88200 * 2);
    var peak = 0;
    for (var i = 44; i < wav.length; i += 2) {
      final v = bd.getInt16(i, Endian.little).abs();
      if (v > peak) peak = v;
    }
    expect(peak, closeTo(16384, 2));
    // silent before the first turn
    expect(bd.getInt16(44 + 2 * 2000, Endian.little), 0);
  });
}
