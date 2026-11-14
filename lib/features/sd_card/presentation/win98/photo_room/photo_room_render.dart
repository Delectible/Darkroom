import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import '../../../../../core/db/media_repository.dart';
import '../../../../../core/paths/app_paths.dart';
import '../../../../cameras/domain/camera_catalog.dart';
import '../../../../studio/studio_render.dart';
import '../../../../viewer/presentation/media_actions.dart';

/// What Photo Room makes, and how many photos each takes.
enum PhotoRoomMake {
  collage('Collage', 'COLLG', 'A grid of 2, 4, 6 or 9 photos with a border.', 2, 9, [2, 4, 6, 9]),
  sheet(
    'Contact sheet',
    'SHEET',
    'Every photo you pick, numbered, with its file name, like an index print.',
    2,
    36,
  ),
  card('Greeting card or poster', 'CARD', 'Photos, WordArt and clip art on a card you arrange.', 1, 4),
  gif('Animated GIF', 'ANIM', 'Your photos one after another, looping, at the speed you pick.', 2, 30),
  strip('Photo booth strip', 'STRIP', 'Three or four photos down a booth strip with the date.', 3, 4);

  const PhotoRoomMake(this.label, this.prefix, this.blurb, this.min, this.max, [this.only = const []]);
  final String label;

  /// The start of its file names (8.3: COLLG001.JPG).
  final String prefix;
  final String blurb;
  final int min, max;

  /// Only these counts (else anything from [min] to [max]).
  final List<int> only;

  bool fits(int n) => only.isEmpty ? n >= min && n <= max : only.contains(n);

  String get needs => switch (this) {
    PhotoRoomMake.collage => '2, 4, 6 or 9',
    PhotoRoomMake.sheet => '2 to 36',
    PhotoRoomMake.card => '1 to 4',
    PhotoRoomMake.gif => '2 to 30',
    PhotoRoomMake.strip => '3 or 4',
  };
}

/// Backgrounds from the 98 palette.
enum Backdrop {
  white('White', Color(0xFFFFFFFF), Color(0xFF000000)),
  black('Black', Color(0xFF000000), Color(0xFFFFFFFF)),
  teal('Teal', Color(0xFF008080), Color(0xFFFFFFFF)),
  silver('Silver', Color(0xFFC0C0C0), Color(0xFF000000)),
  navy('Navy', Color(0xFF000080), Color(0xFFFFFF00));

  const Backdrop(this.label, this.color, this.ink);
  final String label;
  final Color color;
  final Color ink;
}

Future<ui.Image> _record(Size size, void Function(Canvas c) draw) {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec, Offset.zero & size));
  return rec.endRecording().toImage(size.width.round(), size.height.round());
}

void _pixelText(
  Canvas c,
  String s,
  Offset at,
  double size,
  Color color, {
  TextAlign align = TextAlign.left,
  double? width,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontFamily: 'W98', fontSize: size, color: color),
    ),
    textAlign: align,
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: width ?? 4000);
  final dx = switch (align) {
    TextAlign.center => (width ?? tp.width) / 2 - tp.width / 2,
    TextAlign.right => (width ?? tp.width) - tp.width,
    _ => 0.0,
  };
  tp.paint(c, at + Offset(dx, 0));
}

/// The collage: an even grid of square-ish frames on the backdrop.
Future<ui.Image> renderRoomCollage(List<ui.Image> photos, Backdrop back, {bool thick = false}) {
  final n = photos.length;
  final (cols, rows) = switch (n) {
    2 => (2, 1),
    4 => (2, 2),
    6 => (3, 2),
    _ => (3, 3),
  };
  const w = 1800.0;
  final gap = thick ? 60.0 : 24.0;
  final cell = (w - gap * (cols + 1)) / cols;
  final ch = cell * 0.78;
  final h = gap * (rows + 1) + ch * rows;
  return _record(Size(w, h), (c) {
    c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = back.color);
    for (var i = 0; i < n; i++) {
      final r = Rect.fromLTWH(gap + (i % cols) * (cell + gap), gap + (i ~/ cols) * (ch + gap), cell, ch);
      drawCover(c, photos[i], r);
    }
  });
}

/// The contact sheet: every photo small and numbered, its name under it,
/// a heading along the top.
Future<ui.Image> renderContactSheet(List<ui.Image> photos, List<String> names, Backdrop back, DateTime date) {
  final n = photos.length;
  final cols = n <= 4 ? 2 : (n <= 12 ? 3 : 4);
  final rows = (n / cols).ceil();
  const w = 1800.0, margin = 60.0, gap = 30.0, head = 120.0, label = 64.0;
  final cell = (w - margin * 2 - gap * (cols - 1)) / cols;
  final ch = cell * 0.75;
  final h = head + margin + rows * (ch + label) + (rows - 1) * gap + margin;
  return _record(Size(w, h), (c) {
    c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = back.color);
    _pixelText(c, r'C:\MY PICTURES', const Offset(margin, 40), 40, back.ink);
    _pixelText(
      c,
      '$n FRAMES  ·  ${studioDate(date)}',
      const Offset(margin, 40),
      40,
      back.ink,
      align: TextAlign.right,
      width: w - margin * 2,
    );
    c.drawRect(
      const Rect.fromLTWH(margin, head - 10, w - margin * 2, 4),
      Paint()..color = back.ink.withValues(alpha: 0.6),
    );
    for (var i = 0; i < n; i++) {
      final x = margin + (i % cols) * (cell + gap);
      final y = head + margin * 0.5 + (i ~/ cols) * (ch + label + gap);
      final r = Rect.fromLTWH(x, y, cell, ch);
      drawCover(c, photos[i], r);
      c.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = back.ink.withValues(alpha: 0.5),
      );
      _pixelText(c, '${i + 1}'.padLeft(2, '0'), Offset(x, y + ch + 12), 34, back.ink);
      _pixelText(
        c,
        names[i],
        Offset(x + 70, y + ch + 12),
        34,
        back.ink.withValues(alpha: 0.8),
        width: cell - 70,
      );
    }
  });
}

/// A photo booth strip with a 98 touch: its frames down the strip, the
/// date and DARKROOM 98 in pixel letters at the foot.
Future<ui.Image> renderRoomStrip(List<ui.Image> photos, Backdrop back, DateTime date) {
  const w = 600.0, cellW = 520.0, cellH = 390.0, top = 40.0, gap = 30.0, foot = 130.0;
  final h = top + photos.length * cellH + (photos.length - 1) * gap + foot;
  return _record(Size(w, h), (c) {
    c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = back.color);
    for (var i = 0; i < photos.length; i++) {
      drawCover(c, photos[i], Rect.fromLTWH((w - cellW) / 2, top + i * (cellH + gap), cellW, cellH));
    }
    final y = h - foot + 30;
    _pixelText(c, 'DARKROOM 98', Offset(0, y), 38, back.ink, align: TextAlign.center, width: w);
    _pixelText(
      c,
      studioDate(date),
      Offset(0, y + 48),
      30,
      back.ink.withValues(alpha: 0.75),
      align: TextAlign.center,
      width: w,
    );
  });
}

/// GIF sizes: the longest side.
enum GifSize {
  small('Small', 320),
  medium('Medium', 480);

  const GifSize(this.label, this.side);
  final String label;
  final int side;
}

/// An animated GIF of [photos], each held [frameMs], looping; every frame
/// cropped to 4:3 at [size]. Encoded off the UI isolate.
Future<Uint8List> encodeGif(List<String> paths, int frameMs, GifSize size) async {
  final w = size.side, h = (size.side * 3 / 4).round();
  final frames = <Uint8List>[];
  for (final p in paths) {
    final photo = await loadStudioImage(p, maxSide: size.side * 2);
    final frame = await _record(Size(w.toDouble(), h.toDouble()), (c) {
      drawCover(c, photo, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    });
    photo.dispose();
    final bytes = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.dispose();
    frames.add(bytes!.buffer.asUint8List());
  }
  final delay = (frameMs / 10).round().clamp(2, 300);
  return Isolate.run(() {
    final enc = img.GifEncoder(repeat: 0, samplingFactor: 20);
    for (final f in frames) {
      final im = img.Image.fromBytes(width: w, height: h, bytes: f.buffer, numChannels: 4);
      enc.addFrame(im, duration: delay);
    }
    return enc.finish()!;
  });
}

/// Files [bytes] (a JPEG or GIF made by Photo Room) on C: in its folder:
/// the file, a thumbnail, its row (moved to C: and saved), and a copy in
/// the photo library like everything on C:. Returns the item.
Future<MediaItem> keepOnC({
  required MediaRepository repo,
  required List<MediaItem> existing,
  required PhotoRoomMake make,
  required String ext,
  required Future<void> Function(String path) write,
  required ui.Image thumb,
}) async {
  final paths = await AppPaths.resolve();
  final dir = Directory('${paths.documentsDir.path}/photoroom');
  await dir.create(recursive: true);
  await paths.thumbsDir.create(recursive: true);
  // the next free number for this kind (COLLG001, COLLG002...)
  var n = 1;
  final taken = {for (final m in existing) m.fileName.toUpperCase()};
  String name() => '${make.prefix}${n.toString().padLeft(8 - make.prefix.length, '0')}.$ext';
  while (taken.contains(name())) {
    n++;
  }
  final file = name();
  final id = 'photoroom_${DateTime.now().microsecondsSinceEpoch}';
  final out = '${dir.path}/${id}_$file';
  await write(out);
  final thumbPath = '${paths.thumbsDir.path}/$id.jpg';
  final s = math.min(1.0, 400 / math.max(thumb.width, thumb.height));
  final small = await _record(Size(thumb.width * s, thumb.height * s), (c) {
    drawCover(c, thumb, Rect.fromLTWH(0, 0, thumb.width * s, thumb.height * s));
  });
  await writeStudioJpeg(small, thumbPath, quality: 85);
  small.dispose();
  final now = DateTime.now();
  await repo.insertReady(
    id: id,
    cameraId: CameraCatalog.photoRoomId,
    fileName: file,
    outputPath: out,
    thumbPath: thumbPath,
    width: thumb.width,
    height: thumb.height,
    capturedAt: now,
  );
  await repo.markSaved([id], moveToC: true);
  final item = MediaItem(
    id: id,
    cameraId: CameraCatalog.photoRoomId,
    kind: MediaKind.photo,
    status: MediaStatus.ready,
    fileName: file,
    capturedAt: now,
    readyAt: now,
    outputPath: out,
    thumbPath: thumbPath,
    width: thumb.width,
    height: thumb.height,
    location: MediaLocation.c,
    savedAt: now,
  );
  // (like everything on C:, a copy in the photo library; fine if refused)
  await saveToGallery(item, album: digitalAlbum);
  return item;
}
