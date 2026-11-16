import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

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
    FlipStyle style = FlipStyle.shutter,
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
    );
    // (the cover: the first photo, settled)
    final first = await loadStudioImage(pages.first, maxSide: 1200);
    try {
      final frames = FlipFrames(photos: [first], paper: paper, style: style, pageMs: pageMs);
      final pixels = await drawStudioPixels(() => _frameAt(frames, pageMs * 0.92));
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
      await _encode(frames, part);
      await File(part).rename(work.path);
      return work.path;
    } finally {
      for (final i in images) {
        i.dispose();
      }
    }
  }

  static Future<ui.Image> _frameAt(FlipFrames frames, double t) {
    final rec = ui.PictureRecorder();
    frames.paint(Canvas(rec, Offset.zero & _frame), _frame, t);
    return rec.endRecording().toImage(_frame.width.toInt(), _frame.height.toInt());
  }

  static Future<void> _encode(FlipFrames frames, String out) async {
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
        final f = '${work.path}/f${n++}.png';
        final pixels = await drawStudioPixels(() => _frameAt(frames, k.at), settle: false);
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
      await VideoPipeline.ffmpeg([
        '-y', '-f', 'concat', '-safe', '0', '-i', listPath, //
        '-r', '30', '-pix_fmt', 'yuv420p', ...VideoPipeline.encoder(6000), out,
      ], timeout: const Duration(minutes: 4));
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }
}
