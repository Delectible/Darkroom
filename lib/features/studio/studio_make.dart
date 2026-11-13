import 'dart:io';
import 'dart:ui' as ui;

import '../../core/db/media_repository.dart';
import '../../core/processing/video_pipeline.dart';
import '../viewer/presentation/media_actions.dart' show exportPathFor;
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

  /// How often a page shakes, and how long the flash between pages lasts.
  static const _shakeMs = 120, _flashMs = 34;

  /// A page's time: the speed slider's range and starting point.
  static const pageMsMin = 150, pageMsMax = 900, pageMsDefault = 360;

  /// A flip book: each photo snaps to the next with a flash of the print
  /// and a handheld shake, [pageMs] a page, as a 4:5 MP4 (a video, for
  /// Instagram).
  static Future<StudioWork> flipBook(
    List<MediaItem> prints,
    StudioPaper paper, {
    int pageMs = pageMsDefault,
  }) async {
    final id = _id();
    final dir = await StudioBook.folder();
    // the photos kept, one a page, for the book to riffle and new speeds
    final keep = Directory('${dir.path}/flipbook_$id');
    await keep.create(recursive: true);
    final images = await photos(prints, maxSide: 1200);
    final pages = <String>[];
    for (var i = 0; i < images.length; i++) {
      final f = '${keep.path}/page$i.jpg';
      await writeStudioJpeg(images[i], f, quality: 88);
      pages.add(f);
    }
    final out = '${dir.path}/flipbook_${id}_$pageMs.mp4';
    final cover = '${dir.path}/flipbook_$id.jpg';
    await writeStudioJpeg(await renderFlipPage(images.first, paper, 0), cover);
    await _encodeFlip(images, paper, pageMs, out);
    return StudioWork(
      id: id,
      kind: StudioKind.flipbook,
      path: out,
      cover: cover,
      createdAt: DateTime.now(),
      pages: pages,
      paper: paper.name,
      pageMs: pageMs,
    );
  }

  /// [work] (a flip book with its pages kept) made again at [pageMs] a
  /// page; the old video goes.
  static Future<StudioWork> reflip(StudioWork work, int pageMs) async {
    final paper = StudioPaper.values.asNameMap()[work.paper] ?? StudioPaper.cream;
    final images = [for (final p in work.pages) await loadStudioImage(p, maxSide: 1200)];
    final out = '${(await StudioBook.folder()).path}/flipbook_${work.id}_$pageMs.mp4';
    await _encodeFlip(images, paper, pageMs, out);
    if (out != work.path) {
      try {
        await File(work.path).delete();
      } catch (_) {}
    }
    return work.copyWith(path: out, pageMs: pageMs);
  }

  static Future<void> _encodeFlip(List<ui.Image> images, StudioPaper paper, int pageMs, String out) async {
    final work = Directory('${Directory.systemTemp.path}/flipbook_${_id()}');
    await work.create(recursive: true);
    try {
      final list = StringBuffer();
      // (each page shakes every 120 ms; a fast page holds one pose)
      final shakes = (pageMs / _shakeMs).round().clamp(1, 8);
      final hold = pageMs / shakes / 1000;
      String? last;
      for (var i = 0; i < images.length; i++) {
        if (i > 0) {
          // the incoming print flashes white as the page turns
          final f = '${work.path}/f$i.png';
          await writeStudioPng(await renderFlipPage(images[i], paper, i * 9, flash: true), f);
          list.writeln("file '$f'\nduration ${_flashMs / 1000}");
        }
        for (var k = 0; k < shakes; k++) {
          final f = '${work.path}/p${i}_$k.png';
          await writeStudioPng(await renderFlipPage(images[i], paper, i * 9 + k), f);
          list.writeln("file '$f'\nduration $hold");
          last = f;
        }
      }
      // (the concat demuxer wants the last file once more)
      if (last != null) list.writeln("file '$last'");
      final listPath = '${work.path}/list.txt';
      await File(listPath).writeAsString(list.toString());
      await VideoPipeline.ffmpeg([
        '-y', '-f', 'concat', '-safe', '0', '-i', listPath, //
        '-r', '30', '-pix_fmt', 'yuv420p', ...VideoPipeline.encoder(6000), out,
      ], timeout: const Duration(minutes: 3));
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }
}
