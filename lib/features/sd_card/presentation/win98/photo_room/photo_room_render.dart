import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
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
  collage(
    'Collage or contact sheet',
    'COLLG',
    'A grid of your photos with a border, or a contact sheet: each one numbered with its file name, '
        'like an index print.',
    2,
    36,
  ),
  card('Greeting card or poster', 'CARD', 'Photos, WordArt and clip art on a card you arrange.', 1, 4),
  gif('Animated GIF', 'ANIM', 'Your photos one after another, looping, at the speed you pick.', 2, 30),
  strip('Photo booth strip', 'STRIP', 'Three or four photos down a booth strip with the date.', 3, 4);

  const PhotoRoomMake(this.label, this.prefix, this.blurb, this.min, this.max);
  final String label;

  /// The start of its file names (8.3: COLLG001.JPG).
  final String prefix;
  final String blurb;
  final int min, max;

  bool fits(int n) => n >= min && n <= max;

  String get needs => switch (this) {
    PhotoRoomMake.collage => '2 to 36',
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
  final cols = n <= 4 ? 2 : (n <= 9 ? 3 : (n <= 16 ? 4 : 5));
  final rows = (n / cols).ceil();
  const w = 1800.0;
  final gap = thick ? 60.0 : 24.0;
  final cell = (w - gap * (cols + 1)) / cols;
  final ch = cell * 0.78;
  final h = gap * (rows + 1) + ch * rows;
  return _record(Size(w, h), (c) {
    c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = back.color);
    for (var i = 0; i < n; i++) {
      // (a short last row sits in the middle)
      final row = i ~/ cols;
      final inRow = row == rows - 1 ? n - row * cols : cols;
      final x0 = (w - (inRow * cell + (inRow - 1) * gap)) / 2;
      final r = Rect.fromLTWH(x0 + (i % cols) * (cell + gap), gap + row * (ch + gap), cell, ch);
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

/// A date as a PC writes it: 11/14/26.
String pcDate(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';

/// The doodled strip's paint-bucket backgrounds.
enum StripFill {
  lemon('Lemon', Color(0xFFFFFF80)),
  mint('Mint', Color(0xFF9CF2C8)),
  sky('Sky', Color(0xFF9EE6FF)),
  bubblegum('Bubblegum', Color(0xFFFFB3DA)),
  lilac('Lilac', Color(0xFFC9C2FF)),
  paper('Paper', Color(0xFFFFFFFF)),
  brown('Brown', Color(0xFF7A4A24)),
  black('Black', Color(0xFF000000));

  /// Dark enough for white outlines and lettering.
  bool get dark => this == brown || this == black;

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
    this.crooked = false,
  });

  final StripFill fill;
  final String caption;
  final int seed;
  final bool doodles;
  final bool date;

  /// Each shot stuck on a little off true.
  final bool crooked;

  StripLook copyWith({
    StripFill? fill,
    String? caption,
    int? seed,
    bool? doodles,
    bool? date,
    bool? crooked,
  }) => StripLook(
    fill: fill ?? this.fill,
    caption: caption ?? this.caption,
    seed: seed ?? this.seed,
    doodles: doodles ?? this.doodles,
    date: date ?? this.date,
    crooked: crooked ?? this.crooked,
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

const _brightInks = [
  Color(0xFFFFFF00),
  Color(0xFF00FFFF),
  Color(0xFFFF60FF),
  Color(0xFF60FF60),
  Color(0xFFFFA040),
  Color(0xFFFFFFFF),
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
    // the photos: a hard offset shadow, a 4 px outline (white on the dark
    // fills), a little crooked if asked
    final dark = look.fill.dark;
    final outline = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    final shadow = look.fill == StripFill.black ? const Color(0xFF4A4A4A) : const Color(0xFF000000);
    final tilt = math.Random(look.seed * 31 + 7);
    for (var i = 0; i < photos.length; i++) {
      final r = cells[i];
      c.save();
      if (look.crooked) {
        c.translate(r.center.dx, r.center.dy);
        c.rotate((tilt.nextDouble() - 0.5) * 0.07 + (i.isEven ? -0.012 : 0.012));
        c.translate(-r.center.dx, -r.center.dy);
      }
      c.drawRect(r.shift(const Offset(8, 8)), Paint()..color = shadow);
      c.drawRect(r.inflate(4), Paint()..color = outline);
      drawCover(c, photos[i], r);
      c.restore();
    }
    // (bright inks on the dark fills)
    final inks = dark ? _brightInks : _inks;
    if (look.doodles) _doodle(c, rnd, cells, Size(w, h), foot, inks);
    // the caption: pixel letters with a hard shadow, in one of the inks
    final ink = inks[rnd.nextInt(inks.length)];
    final capY = h - foot + 34;
    if (look.caption.trim().isNotEmpty) {
      _pixelText(c, look.caption, Offset(4, capY + 4), 46, shadow, align: TextAlign.center, width: w);
      _pixelText(c, look.caption, Offset(0, capY), 46, ink, align: TextAlign.center, width: w);
    }
    if (look.date) {
      _pixelText(
        c,
        pcDate(date),
        Offset(0, capY + 70),
        26,
        dark ? const Color(0xDDFFFFFF) : const Color(0xCC000000),
        align: TextAlign.center,
        width: w,
      );
    }
  });
}

void _doodle(Canvas c, math.Random rnd, List<Rect> cells, Size size, double foot, List<Color> inks) {
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
    final ink = inks[rnd.nextInt(inks.length)];
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

/// How one photo gives way to the next in a GIF.
enum GifTransition {
  cut('Cut'),
  fade('Fade'),
  circle('Circle'),
  slide('Slide'),
  dissolve('Dissolve'),
  blinds('Blinds');

  const GifTransition(this.label);
  final String label;
}

/// How long a change takes, in a slot of [frameMs] (none for a cut).
int transitionMs(GifTransition k, int frameMs) =>
    k == GifTransition.cut ? 0 : math.min(frameMs * 0.5, 420).round();

/// [path] cropped to a [w] x [h] frame (4:3).
Future<ui.Image> gifFrameOf(String path, int w, int h) async {
  final photo = await loadStudioImage(path, maxSide: math.max(w, h) * 2);
  final frame = await _record(Size(w.toDouble(), h.toDouble()), (c) {
    drawCover(c, photo, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  });
  photo.dispose();
  return frame;
}

/// One moment of the change from [a] to [b], [t] of the way (0..1).
void paintGifChange(Canvas c, Size size, ui.Image a, ui.Image b, double t, GifTransition k) {
  final r = Offset.zero & size;
  final paint = Paint()..filterQuality = FilterQuality.medium;
  void draw(ui.Image im, [Offset at = Offset.zero, double opacity = 1]) => c.drawImageRect(
    im,
    Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
    r.shift(at),
    paint..color = Color.fromRGBO(0, 0, 0, opacity),
  );
  switch (k) {
    case GifTransition.cut:
      draw(t < 0.5 ? a : b);
    case GifTransition.fade:
      draw(a);
      draw(b, Offset.zero, t);
    case GifTransition.circle:
      draw(a);
      c.save();
      final radius = t * math.sqrt(size.width * size.width + size.height * size.height) / 2;
      c.clipPath(Path()..addOval(Rect.fromCircle(center: r.center, radius: radius)));
      draw(b);
      c.restore();
    case GifTransition.slide:
      final e = Curves.easeInOut.transform(t);
      draw(a, Offset(-e * size.width, 0));
      draw(b, Offset((1 - e) * size.width, 0));
    case GifTransition.dissolve:
      // square blocks flip over in a scattered order, like a 98 screen wipe
      draw(a);
      const n = 12;
      final bw = size.width / n, bh = size.height / (n * 3 / 4).round();
      final rows = (size.height / bh).ceil();
      final path = Path();
      final rnd = math.Random(3);
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < n; x++) {
          if (rnd.nextDouble() < t) {
            // (whole pixels, no soft edges: no seams between blocks)
            path.addRect(
              Rect.fromLTRB(
                (x * bw).floorToDouble(),
                (y * bh).floorToDouble(),
                ((x + 1) * bw).ceilToDouble(),
                ((y + 1) * bh).ceilToDouble(),
              ),
            );
          }
        }
      }
      c.save();
      c.clipPath(path, doAntiAlias: false);
      draw(b);
      c.restore();
    case GifTransition.blinds:
      draw(a);
      const strips = 8;
      final sh = size.height / strips;
      // each slat opens to its whole height (whole pixels, hard edges): no
      // thin lines left between them as it finishes
      final open = Curves.easeOut.transform(t);
      final path = Path();
      for (var i = 0; i < strips; i++) {
        final top = (i * sh).floorToDouble();
        final full = ((i + 1) * sh).ceilToDouble();
        path.addRect(
          Rect.fromLTRB(0, top, size.width, math.min(full, (top + (full - top) * open).ceilToDouble())),
        );
      }
      c.save();
      c.clipPath(path, doAntiAlias: false);
      draw(b);
      c.restore();
  }
}

/// An animated GIF of the photos at [paths], each held [frameMs] (its
/// change to the next, [transition], included), looping back to the
/// first; every frame cropped to 4:3 at [size]. Encoded off the UI isolate.
Future<Uint8List> encodeGif(
  List<String> paths,
  int frameMs,
  GifSize size, {
  GifTransition transition = GifTransition.cut,
}) async {
  final w = size.side, h = (size.side * 3 / 4).round();
  final photos = [for (final p in paths) await gifFrameOf(p, w, h)];
  final change = transitionMs(transition, frameMs);
  // fewer in-between frames on long GIFs (the file stays a sensible size)
  final steps = change == 0 ? 0 : (paths.length > 12 ? 3 : 5);
  final frames = <(Uint8List, int)>[];
  Future<void> add(ui.Image frame, int ms) async {
    final bytes = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    frames.add((bytes!.buffer.asUint8List(), (ms / 10).round().clamp(2, 300)));
  }

  for (var i = 0; i < photos.length; i++) {
    await add(photos[i], frameMs - change);
    if (steps == 0) continue;
    final next = photos[(i + 1) % photos.length];
    for (var k = 1; k <= steps; k++) {
      final f = await _record(Size(w.toDouble(), h.toDouble()), (c) {
        paintGifChange(c, Size(w.toDouble(), h.toDouble()), photos[i], next, k / (steps + 1), transition);
      });
      await add(f, change ~/ steps);
      f.dispose();
    }
  }
  for (final p in photos) {
    p.dispose();
  }
  return _encodeOff(frames, w, h);
}

// (its own function, so only the bytes cross to the other isolate: a
// closure inside encodeGif would carry its dart:ui images along)
Future<Uint8List> _encodeOff(List<(Uint8List, int)> frames, int w, int h) =>
    Isolate.run(() => _gifBytes(frames, w, h));

bool _thumbsRepaired = false;

/// Photo Room thumbnails made before they came from the files (some strips'
/// were garbled): drawn again from each file, once a run. True if any was.
Future<bool> repairPhotoRoomThumbs(List<MediaItem> items) async {
  if (_thumbsRepaired) return false;
  _thumbsRepaired = true;
  var any = false;
  for (final m in items) {
    final from = m.outputPath, to = m.thumbPath;
    if (from == null || to == null || !File(from).existsSync()) continue;
    try {
      await Isolate.run(() => _thumbFromFile(from, to));
      any = true;
    } catch (_) {
      // (leave that one as it was)
    }
  }
  return any;
}

/// A thumbnail of the picture (or a GIF's first frame) at [from], at most
/// 400 px on its longest side.
void _thumbFromFile(String from, String to) {
  final bytes = File(from).readAsBytesSync();
  final pic = img.decodeImage(bytes);
  if (pic == null) throw StateError('Could not read $from');
  final first = pic.frames.isEmpty ? pic : pic.frames.first;
  final s = math.min(1.0, 400 / math.max(first.width, first.height));
  final small = img.copyResize(
    first,
    width: math.max(1, (first.width * s).round()),
    height: math.max(1, (first.height * s).round()),
    interpolation: img.Interpolation.average,
  );
  File(to).writeAsBytesSync(img.encodeJpg(small, quality: 85));
}

Uint8List _gifBytes(List<(Uint8List, int)> frames, int w, int h) {
  final enc = img.GifEncoder(repeat: 0, samplingFactor: 20);
  for (final (f, cs) in frames) {
    enc.addFrame(
      img.Image.fromBytes(width: w, height: h, bytes: f.buffer, numChannels: 4),
      duration: cs,
    );
  }
  return enc.finish()!;
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
  // The thumbnail is made from the saved file itself, on the CPU: drawing
  // it from the on-screen picture could read a texture the GPU had already
  // reused (garbled strip thumbnails, bits of other screens in them).
  await Isolate.run(() => _thumbFromFile(out, thumbPath));
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
