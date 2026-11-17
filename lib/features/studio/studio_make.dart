import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/db/media_repository.dart';
import '../../core/processing/video_pipeline.dart';
import '../viewer/presentation/media_actions.dart' show exportPathFor;
import 'studio_flip_frames.dart';
import 'studio_render.dart';
import 'studio_store.dart';

/// Makes Studio pieces and files them in the book's folder.
class StudioMake {
  StudioMake._();

  static String _id() => DateTime.now().microsecondsSinceEpoch.toString();

  /// The prints' photos as they are (strips and collages frame them
  /// themselves).
  static Future<List<ui.Image>> photos(List<MediaItem> prints, {int maxSide = 1600}) async => [
    for (final m in prints)
      if (m.outputPath case final p?) await loadStudioImage(p, maxSide: maxSide),
  ];

  /// The prints as they leave the app, frames and all (the scrapbook keeps
  /// them).
  static Future<List<String>> framedPaths(List<MediaItem> prints) async => [
    for (final m in prints) ?(await exportPathFor(m) ?? m.outputPath),
  ];

  static Future<StudioWork> saveImage(ui.Image image, StudioKind kind) async {
    final id = _id();
    final path = '${(await StudioBook.folder()).path}/${kind.name}_$id.jpg';
    await writeStudioJpeg(image, path);
    return StudioWork(id: id, kind: kind, path: path, createdAt: DateTime.now());
  }

  /// A page's time: the speed slider's range and starting point.
  static const pageMsMin = 150, pageMsMax = 1400, pageMsDefault = 700;

  /// The flip book's frame: 4:5 at 1080 x 1350 (for Instagram).
  static const _frame = Size(1080, 1350);

  /// A flip book: the photos one after another, [pageMs] each, changing
  /// in [style]. The book is ready at once (its pages kept, a cover); its
  /// video, a 4:5 MP4 drawn by the same [FlipFrames] the app plays it with,
  /// is made afterwards, out of sight (see [flipVideo]).
  static Future<StudioWork> flipBook(
    List<MediaItem> prints,
    StudioPaper paper, {
    int pageMs = pageMsDefault,
    FlipStyle style = FlipStyle.standard,
    bool sound = true,
  }) async {
    final id = _id();
    final dir = await StudioBook.folder();
    // the photos kept, one a page, for the app to play it from: copied
    // without the GPU, several at a time
    final keep = Directory('${dir.path}/flipbook_$id');
    await keep.create(recursive: true);
    final from = [for (final m in prints) ?m.outputPath];
    final pages = [for (var i = 0; i < from.length; i++) '${keep.path}/page$i.jpg'];
    for (var i = 0; i < from.length; i += 4) {
      await Future.wait([
        for (var j = i; j < from.length && j < i + 4; j++)
          copyStudioPhoto(from[j], pages[j]).catchError((Object _) async {
            // (a picture the copier can't read: through the GPU after all)
            final image = await loadStudioImage(from[j], maxSide: 1200);
            try {
              await writeStudioJpeg(image, pages[j], quality: 88);
            } finally {
              image.dispose();
            }
          }),
      ]);
    }
    final work = StudioWork(
      id: id,
      kind: StudioKind.flipbook,
      path: '${dir.path}/flipbook_$id.mp4',
      cover: '${dir.path}/flipbook_$id.jpg',
      createdAt: DateTime.now(),
      pages: pages,
      paper: paper.name,
      pageMs: pageMs,
      flipStyle: style.name,
      silent: !sound,
    );
    // (the cover: the first photo, settled)
    final first = await loadStudioImage(pages.first, maxSide: 1200);
    try {
      final frames = FlipFrames(photos: [first], paper: paper, style: style, pageMs: pageMs);
      final pixels = await _framePixels(frames, pageMs * 0.92, 0, settle: true);
      await writeStudioPixels(pixels, work.cover!);
    } finally {
      first.dispose();
    }
    // The video once the new book has landed on the table and the Studio's
    // settled (making it is heavy work); sooner if it's asked for.
    unawaited(
      Future<void>.delayed(const Duration(seconds: 5), () => flipVideo(work)).then((_) {}, onError: (_) {}),
    );
    return work;
  }

  static final _videos = <String, Future<String>>{};

  /// [work]'s video, made now if it hasn't been yet (a new book's is made
  /// a little after the book; one whose making was cut short, when it's
  /// first wanted). Asked for twice, it's made once.
  static Future<String> flipVideo(StudioWork work) {
    if (File(work.path).existsSync()) return Future.value(work.path);
    return _videos[work.id] ??= _makeVideo(work).whenComplete(() => _videos.remove(work.id));
  }

  static Future<String> _makeVideo(StudioWork work) async {
    final images = <ui.Image>[];
    try {
      for (final p in work.pages) {
        images.add(await loadStudioImage(p, maxSide: 1200));
      }
      final frames = FlipFrames(
        photos: images,
        paper: StudioPaper.values.asNameMap()[work.paper] ?? StudioPaper.cream,
        style: FlipStyle.named(work.flipStyle),
        pageMs: work.pageMs ?? pageMsDefault,
      );
      // (under another name till it's whole: a half-made file is never taken for it)
      final part = work.path.replaceFirst(RegExp(r'\.mp4$'), '_part.mp4');
      await _encode(frames, part, sound: !work.silent);
      await File(part).rename(work.path);
      return work.path;
    } finally {
      clearStapledTextures();
      for (final i in images) {
        i.dispose();
      }
    }
  }

  /// The frame at [t], with two rows of [mark] below it (see [_framePixels]).
  static Future<ui.Image> _frameAt(FlipFrames frames, double t, Color mark) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Offset.zero & Size(_frame.width, _frame.height + 2));
    frames.paint(c, _frame, t);
    c.drawRect(Rect.fromLTWH(0, _frame.height, _frame.width, 2), Paint()..color = mark);
    return rec.endRecording().toImage(_frame.width.toInt(), _frame.height.toInt() + 2);
  }

  /// A colour only frame [n] has.
  static Color _markOf(int n) => Color.fromARGB(255, (n * 37 + 11) & 255, (n * 101 + 50) & 255, 0xA5);

  /// Frame [n]'s pixels, checked. Some phones' GPUs hand back whatever was in
  /// that memory when a picture is read too soon: noise (caught by
  /// readStudioPixels), but also an old picture (the book, a black frame),
  /// which looks fine. So each frame carries a mark of its own below it; one
  /// read back without it is read again after a frame, then drawn again.
  static Future<StudioPixels> _framePixels(FlipFrames frames, double t, int n, {bool settle = false}) async {
    final mark = _markOf(n);
    final w = _frame.width.toInt(), h = _frame.height.toInt();
    for (var i = 0; ; i++) {
      final image = await _frameAt(frames, t, mark);
      try {
        final px = await readStudioPixels(image, settle: settle || i > 0);
        if (_marked(px.bytes, w, h, mark)) {
          return (bytes: Uint8List.fromList(px.bytes.sublist(0, w * h * 4)), width: w, height: h);
        }
      } on StudioScrambled {
        // (read again below)
      } finally {
        image.dispose();
      }
      if (i >= 4) throw const StudioScrambled();
      await settleGpu();
      await Future<void>.delayed(Duration(milliseconds: 40 * (i + 1)));
    }
  }

  static bool _marked(Uint8List bytes, int w, int h, Color mark) {
    final r = (mark.r * 255).round(), g = (mark.g * 255).round(), b = (mark.b * 255).round();
    for (final x in [1, w ~/ 3, w ~/ 2, w * 2 ~/ 3, w - 2]) {
      for (final y in [h, h + 1]) {
        final i = (y * w + x) * 4;
        if (i + 2 >= bytes.length) return false;
        if ((bytes[i] - r).abs() > 2 || (bytes[i + 1] - g).abs() > 2 || (bytes[i + 2] - b).abs() > 2) {
          return false;
        }
      }
    }
    return true;
  }

  /// The video's settings: the encoder we ship (MPEG-4 part 2), by quality
  /// rather than a fixed bitrate (that blurred grainy photos), with its
  /// careful options on.
  static const _videoArgs = [
    '-c:v', 'mpeg4', '-q:v', '2', '-mbd', 'rd', '-trellis', '2', '-cmp', '2', '-subcmp', '2', //
    '-flags', '+mv4+aic', '-g', '30', '-vtag', 'mp4v',
  ];

  /// The page sounds under a stapled flip book: one take a turn, and in the
  /// riffle back a short, higher flick for each page as it lifts. Mixed here
  /// (a WAV for ffmpeg), louder than the app's own quiet sounds. Null for
  /// styles without sounds.
  static Future<String?> _flipAudio(FlipFrames frames, String dir) async {
    final cues = frames.cues();
    if (cues.isEmpty) return null;
    final takes = <Float32List>[];
    for (var i = 1; i <= 4; i++) {
      for (final v in ['a', 'b']) {
        final data = await rootBundle.load('assets/sfx/page_turn_$i$v.wav');
        takes.add(pcmOf(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
      }
    }
    final path = '$dir/sound.wav';
    final total = frames.totalMs.toDouble();
    final plan = [for (final (at, cue) in cues) (at, cue.index)];
    await Isolate.run(() => File(path).writeAsBytesSync(mixFlipSound(takes, plan, total)));
    return path;
  }

  /// 16-bit mono PCM from a WAV's data chunk, as -1..1.
  @visibleForTesting
  static Float32List pcmOf(Uint8List wav) {
    final bd = ByteData.sublistView(wav);
    var p = 12;
    while (p + 8 <= wav.length) {
      final id = String.fromCharCodes(wav.sublist(p, p + 4));
      final size = bd.getUint32(p + 4, Endian.little);
      if (id == 'data') {
        final n = math.min(size, wav.length - p - 8) ~/ 2;
        final out = Float32List(n);
        for (var i = 0; i < n; i++) {
          out[i] = bd.getInt16(p + 8 + i * 2, Endian.little) / 32768;
        }
        return out;
      }
      p += 8 + size + (size & 1);
    }
    return Float32List(0);
  }

  @visibleForTesting
  static Uint8List mixFlipSound(List<Float32List> takes, List<(double, int)> plan, double totalMs) {
    const sr = 44100;
    final out = Float32List((totalMs * sr / 1000).ceil());
    final rnd = math.Random(plan.length * 31 + 7);
    var last = -1;
    for (final (at, cue) in plan) {
      if (cue == FlipCue.riffle.index || takes.isEmpty) continue;
      var pick = rnd.nextInt(takes.length);
      if (pick == last) pick = (pick + 1) % takes.length;
      last = pick;
      final take = takes[pick];
      final back = cue == FlipCue.back.index;
      // a riffled page: quicker and higher, cut short, softer
      final speed = back ? 1.35 : 1.0, gain = back ? 0.55 : 1.0;
      final len = back ? math.min(take.length / speed, 0.26 * sr).floor() : take.length;
      final fade = (0.04 * sr).floor();
      final start = (at * sr / 1000).round();
      for (var i = 0; i < len && start + i < out.length; i++) {
        final src = i * speed;
        final j = src.floor();
        if (j + 1 >= take.length) break;
        final v = take[j] + (take[j + 1] - take[j]) * (src - j);
        final env = back && i > len - fade ? (len - i) / fade : 1.0;
        out[start + i] += v * gain * env;
      }
    }
    // up to -6 dB at its loudest
    var peak = 0.0;
    for (final v in out) {
      peak = math.max(peak, v.abs());
    }
    final k = peak > 0 ? 0.5 / peak : 1.0;
    final bytes = ByteData(44 + out.length * 2);
    void str(int at, String s) {
      for (var i = 0; i < 4; i++) {
        bytes.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    bytes.setUint32(4, 36 + out.length * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    bytes
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, sr, Endian.little)
      ..setUint32(28, sr * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    str(36, 'data');
    bytes.setUint32(40, out.length * 2, Endian.little);
    for (var i = 0; i < out.length; i++) {
      bytes.setInt16(44 + i * 2, (out[i] * k * 32767).round().clamp(-32768, 32767), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  static Future<void> _encode(FlipFrames frames, String out, {required bool sound}) async {
    final work = Directory('${Directory.systemTemp.path}/flipbook_${_id()}');
    await work.create(recursive: true);
    try {
      final list = StringBuffer();
      String? last;
      var n = 0;
      // Each frame drawn and read here, checked; its PNG written on
      // another core meanwhile, three at a time.
      final writing = <Future<void>>[];
      for (final k in frames.keyframes()) {
        final f = '${work.path}/f$n.png';
        final pixels = await _framePixels(frames, k.at, n++);
        writing.add(writeStudioPng(pixels, f));
        if (writing.length >= 3) await writing.removeAt(0);
        list.writeln("file '$f'\nduration ${k.hold / 1000}");
        last = f;
      }
      await Future.wait(writing);
      // (the concat demuxer wants the last file once more)
      if (last != null) list.writeln("file '$last'");
      final listPath = '${work.path}/list.txt';
      await File(listPath).writeAsString(list.toString());
      final audio = sound ? await _flipAudio(frames, work.path) : null;
      await VideoPipeline.ffmpeg([
        '-y', '-f', 'concat', '-safe', '0', '-i', listPath, //
        if (audio != null) ...['-i', audio],
        '-r', '30', '-pix_fmt', 'yuv420p', ..._videoArgs,
        if (audio != null) ...['-map', '0:v', '-map', '1:a', '-c:a', 'aac', '-b:a', '128k'],
        out,
      ], timeout: const Duration(minutes: 4));
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }
}
