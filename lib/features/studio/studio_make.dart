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
  static const pageMsMin = 150, pageMsMax = 900, pageMsDefault = 360;

  /// The flip book's frame: 4:5 at 1080 x 1350 (for Instagram).
  static const _frame = Size(1080, 1350);

  /// A flip book: the photos one after another, [pageMs] each, changing
  /// in [style], as a 4:5 MP4. The frames are drawn by the same
  /// [FlipFrames] the app plays it with, so the two always match.
  static Future<StudioWork> flipBook(
    List<MediaItem> prints,
    StudioPaper paper, {
    int pageMs = pageMsDefault,
    FlipStyle style = FlipStyle.shutter,
  }) async {
    final id = _id();
    final dir = await StudioBook.folder();
    // the photos kept, one a page, for the app to play it from
    final keep = Directory('${dir.path}/flipbook_$id');
    await keep.create(recursive: true);
    final images = await photos(prints, maxSide: 1200);
    final pages = <String>[];
    for (var i = 0; i < images.length; i++) {
      final f = '${keep.path}/page$i.jpg';
      await writeStudioJpeg(images[i], f, quality: 88);
      pages.add(f);
    }
    final frames = FlipFrames(photos: images, paper: paper, style: style, pageMs: pageMs);
    final out = '${dir.path}/flipbook_$id.mp4';
    final cover = '${dir.path}/flipbook_$id.jpg';
    await writeStudioJpeg(await _frameAt(frames, 0), cover);
    await _encode(frames, out);
    return StudioWork(
      id: id,
      kind: StudioKind.flipbook,
      path: out,
      cover: cover,
      createdAt: DateTime.now(),
      pages: pages,
      paper: paper.name,
      pageMs: pageMs,
      flipStyle: style.name,
    );
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
      for (final k in frames.keyframes()) {
        final f = '${work.path}/f${n++}.png';
        final image = await _frameAt(frames, k.at);
        await writeStudioPng(image, f);
        image.dispose();
        list.writeln("file '$f'\nduration ${k.hold / 1000}");
        last = f;
      }
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
