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
import '../pixel_icons.dart';

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

/// The doodled strip's paint-bucket backgrounds.
enum StripFill {
  lemon('Lemon', Color(0xFFFFFF80)),
  mint('Mint', Color(0xFF9CF2C8)),
  sky('Sky', Color(0xFF9EE6FF)),
  bubblegum('Bubblegum', Color(0xFFFFB3DA)),
  lilac('Lilac', Color(0xFFC9C2FF)),
  paper('Paper', Color(0xFFFFFFFF));

  const StripFill(this.label, this.color);
  final String label;
  final Color color;
}

/// How the doodled strip looks: its fill, caption, the doodles' shuffle
/// ([seed]) and what's shown.
class StripLook {
  const StripLook({
    this.fill = StripFill.lemon,
    this.caption = 'best day ever!!',
    this.seed = 1,
    this.doodles = true,
    this.date = true,
  });

  final StripFill fill;
  final String caption;
  final int seed;
  final bool doodles;
  final bool date;

  StripLook copyWith({StripFill? fill, String? caption, int? seed, bool? doodles, bool? date}) => StripLook(
    fill: fill ?? this.fill,
    caption: caption ?? this.caption,
    seed: seed ?? this.seed,
    doodles: doodles ?? this.doodles,
    date: date ?? this.date,
  );
}

// The doodles' inks: strong colours off the 98 palette.
const _inks = [
  Color(0xFFE0001B),
  Color(0xFF0050E0),
  Color(0xFFD000C8),
  Color(0xFF008A2E),
  Color(0xFFFF7A00),
  Color(0xFF000080),
];

const _clips = [
  PixelIcon.clipStar,
  PixelIcon.clipHeart,
  PixelIcon.clipSmiley,
  PixelIcon.clipFlower,
  PixelIcon.clipSun,
  PixelIcon.clipNote,
  PixelIcon.clipBalloon,
];

/// The doodled photo strip, paint-program style: a bucket-filled
/// background, each shot outlined in black with a hard pixel shadow, a
/// few doodles round the corners and in the gaps (pixel clip art, spray
/// paint, sparkles, squiggles, never over the middle of a photo), the
/// caption in pixel letters, the date. [look.seed] reshuffles the doodles.
Future<ui.Image> renderRoomStrip(List<ui.Image> photos, StripLook look, DateTime date) {
  const w = 600.0, side = 44.0, top = 48.0, gap = 46.0, foot = 170.0;
  const cellW = w - side * 2, cellH = cellW * 0.75;
  final h = top + photos.length * cellH + (photos.length - 1) * gap + foot;
  return _record(Size(w, h), (c) {
    c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = look.fill.color);
    final rnd = math.Random(look.seed * 7919 + photos.length);
    final cells = [
      for (var i = 0; i < photos.length; i++) Rect.fromLTWH(side, top + i * (cellH + gap), cellW, cellH),
    ];
    // the photos: a hard offset shadow, a 4 px black outline
    for (var i = 0; i < photos.length; i++) {
      final r = cells[i];
      c.drawRect(r.shift(const Offset(8, 8)), Paint()..color = const Color(0xFF000000));
      c.drawRect(r.inflate(4), Paint()..color = const Color(0xFF000000));
      drawCover(c, photos[i], r);
    }
    if (look.doodles) _doodle(c, rnd, cells, Size(w, h), foot);
    // the caption: pixel letters with a hard shadow, in one of the inks
    final ink = _inks[rnd.nextInt(_inks.length)];
    final capY = h - foot + 34;
    if (look.caption.trim().isNotEmpty) {
      _pixelText(
        c,
        look.caption,
        Offset(4, capY + 4),
        46,
        const Color(0xFF000000),
        align: TextAlign.center,
        width: w,
      );
      _pixelText(c, look.caption, Offset(0, capY), 46, ink, align: TextAlign.center, width: w);
    }
    if (look.date) {
      _pixelText(
        c,
        studioDate(date),
        Offset(0, capY + 70),
        26,
        const Color(0xCC000000),
        align: TextAlign.center,
        width: w,
      );
    }
  });
}

void _doodle(Canvas c, math.Random rnd, List<Rect> cells, Size size, double foot) {
  // spots for doodles: the photos' corners (half on, half off) and the gaps
  final spots = <Offset>[
    for (final r in cells) ...[r.topLeft, r.topRight, r.bottomLeft, r.bottomRight],
    for (var i = 0; i < cells.length - 1; i++) ...[
      Offset(cells[i].left + 40, (cells[i].bottom + cells[i + 1].top) / 2),
      Offset(cells[i].right - 40, (cells[i].bottom + cells[i + 1].top) / 2),
    ],
    Offset(70, size.height - foot + 60),
    Offset(size.width - 70, size.height - foot + 60),
  ]..shuffle(rnd);
  final count = 5 + rnd.nextInt(3) + cells.length;
  final used = <Offset>[];
  for (final at in spots) {
    if (used.length >= count) break;
    // (room round each, so they don't pile up)
    if (used.any((u) => (u - at).distance < 110)) continue;
    used.add(at);
    final ink = _inks[rnd.nextInt(_inks.length)];
    switch (rnd.nextInt(5)) {
      case 0 || 1:
        final s = 64.0 + rnd.nextInt(3) * 10;
        paintPixelIcon(
          c,
          _clips[rnd.nextInt(_clips.length)],
          Rect.fromCenter(center: at, width: s, height: s),
        );
      case 2:
        _spray(c, rnd, at, ink);
      case 3:
        _sparkles(c, rnd, at, ink);
      default:
        _squiggle(c, rnd, at, ink);
    }
  }
}

/// A burst of spray-can paint: square pixel dots, thick in the middle.
void _spray(Canvas c, math.Random rnd, Offset at, Color ink) {
  final p = Paint()..color = ink;
  for (var i = 0; i < 90; i++) {
    final a = rnd.nextDouble() * math.pi * 2;
    final d = math.pow(rnd.nextDouble(), 1.6) * 42;
    final q = at + Offset(math.cos(a), math.sin(a)) * d.toDouble();
    c.drawRect(Rect.fromLTWH((q.dx / 3).round() * 3, (q.dy / 3).round() * 3, 3, 3), p);
  }
}

/// Little pixel sparkles: plus shapes of different sizes.
void _sparkles(Canvas c, math.Random rnd, Offset at, Color ink) {
  final p = Paint()..color = ink;
  for (var i = 0; i < 3; i++) {
    final q = at + Offset((rnd.nextDouble() - 0.5) * 60, (rnd.nextDouble() - 0.5) * 50);
    final s = (5 + rnd.nextInt(4)) * 3.0;
    final x = (q.dx / 3).round() * 3.0, y = (q.dy / 3).round() * 3.0;
    c.drawRect(Rect.fromLTWH(x - 1.5, y - s, 3, s * 2), p);
    c.drawRect(Rect.fromLTWH(x - s, y - 1.5, s * 2, 3), p);
  }
}

/// A pencil squiggle: a wave drawn in chunky pixels.
void _squiggle(Canvas c, math.Random rnd, Offset at, Color ink) {
  final p = Paint()..color = ink;
  final len = 70 + rnd.nextInt(40);
  final amp = 8 + rnd.nextInt(8);
  for (var x = -len / 2; x < len / 2; x += 3) {
    final y = math.sin(x / 9) * amp;
    c.drawRect(Rect.fromLTWH(((at.dx + x) / 3).round() * 3, ((at.dy + y) / 3).round() * 3, 4, 4), p);
  }
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
