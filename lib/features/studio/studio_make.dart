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

  /// How long each page shows, and how often it shakes within that.
  static const _pageMs = 360, _shakeMs = 120, _flashMs = 34;

  /// A flip book: each photo snaps to the next with a white flash and a
  /// handheld shake, as a 4:5 MP4 (a video, for Instagram).
  static Future<StudioWork> flipBook(List<MediaItem> prints, StudioPaper paper) async {
    final id = _id();
    final dir = await StudioBook.folder();
    final work = Directory('${Directory.systemTemp.path}/flipbook_$id');
    await work.create(recursive: true);
    try {
      final images = await photos(prints, maxSide: 1200);
      final list = StringBuffer();
      final flash = '${work.path}/flash.png';
      await writeStudioPng(await _flat(const ui.Color(0xFFFFFFFF)), flash);
      String? last;
      for (var i = 0; i < images.length; i++) {
        if (i > 0) list.writeln("file '$flash'\nduration ${_flashMs / 1000}");
        for (var k = 0; k < _pageMs ~/ _shakeMs; k++) {
          final f = '${work.path}/p${i}_$k.png';
          await writeStudioPng(await renderFlipPage(images[i], paper, i * 3 + k), f);
          list.writeln("file '$f'\nduration ${_shakeMs / 1000}");
          last = f;
        }
      }
      // (the concat demuxer wants the last file once more)
      if (last != null) list.writeln("file '$last'");
      final listPath = '${work.path}/list.txt';
      await File(listPath).writeAsString(list.toString());
      final out = '${dir.path}/flipbook_$id.mp4';
      final cover = '${dir.path}/flipbook_$id.jpg';
      await writeStudioJpeg(await renderFlipPage(images.first, paper, 0), cover);
      await VideoPipeline.ffmpeg([
        '-y', '-f', 'concat', '-safe', '0', '-i', listPath, //
        '-r', '30', '-pix_fmt', 'yuv420p', ...VideoPipeline.encoder(6000), out,
      ], timeout: const Duration(minutes: 3));
      return StudioWork(
        id: id,
        kind: StudioKind.flipbook,
        path: out,
        cover: cover,
        createdAt: DateTime.now(),
      );
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<ui.Image> _flat(ui.Color color) {
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 1080, 1350), ui.Paint()..color = color);
    return rec.endRecording().toImage(1080, 1350);
  }
}
