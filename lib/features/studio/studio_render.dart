import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// The Studio's pictures, drawn with Flutter's canvas: photo strips,
/// collages and the flip book's pages. Photos of any shape are cropped to
/// one shape per piece (a strip's 4:3 windows, a collage's squares), so a
/// mix of film formats still makes one tidy picture.

/// Paper for strips and collages.
enum StudioPaper {
  white('White', Color(0xFFF4F1EA), Color(0xFF5B544A)),
  black('Black', Color(0xFF151515), Color(0xFFBDBDBD)),
  cream('Cream', Color(0xFFEFE2C6), Color(0xFF6A5638)),
  kraft('Kraft', Color(0xFFB98E5E), Color(0xFF3E2A16));

  const StudioPaper(this.label, this.color, this.ink);
  final String label;
  final Color color;

  /// Writing on it (the date stamp).
  final Color ink;
}

/// How a collage lays its photos out.
enum CollageStyle {
  grid('Grid'),
  edge('Edge to edge'),
  loose('Loose');

  const CollageStyle(this.label);
  final String label;
}

/// [paper] over [r]: a flat colour, and kraft's rough grain (fibres,
/// flecks and a mottled tone, the same every time for the same size).
void paintPaper(Canvas c, Rect r, StudioPaper paper) {
  c.drawRect(r, Paint()..color = paper.color);
  if (paper != StudioPaper.kraft) return;
  final rnd = math.Random(r.width.round() * 31 + r.height.round());
  final scale = r.shortestSide / 400;
  // mottling: soft darker and lighter patches
  for (var i = 0; i < 40; i++) {
    final o = Offset(r.left + rnd.nextDouble() * r.width, r.top + rnd.nextDouble() * r.height);
    final rad = (40 + rnd.nextDouble() * 90) * scale;
    final dark = rnd.nextBool();
    c.drawCircle(
      o,
      rad,
      Paint()
        ..color = (dark ? const Color(0xFF5A3A1C) : const Color(0xFFE2C08E)).withValues(alpha: 0.13)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.6),
    );
  }
  // fibres: short pale and dark strands every which way
  final fibre = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeWidth = math.max(0.6, 0.9 * scale);
  final n = (r.width * r.height / 60 / (scale * scale)).clamp(300, 8000).round();
  for (var i = 0; i < n; i++) {
    final o = Offset(r.left + rnd.nextDouble() * r.width, r.top + rnd.nextDouble() * r.height);
    final a = rnd.nextDouble() * math.pi;
    final len = (2 + rnd.nextDouble() * 7) * scale;
    fibre.color = rnd.nextDouble() < 0.55
        ? const Color(0xFF4A2E14).withValues(alpha: 0.14 + rnd.nextDouble() * 0.16)
        : const Color(0xFFF2D9AE).withValues(alpha: 0.14 + rnd.nextDouble() * 0.18);
    c.drawLine(o, o + Offset(math.cos(a), math.sin(a)) * len, fibre);
  }
  // flecks: the odd dark speck of pulp
  final fleck = Paint()..color = const Color(0x553A2210);
  for (var i = 0; i < n ~/ 12; i++) {
    c.drawCircle(
      Offset(r.left + rnd.nextDouble() * r.width, r.top + rnd.nextDouble() * r.height),
      (0.4 + rnd.nextDouble() * 0.9) * scale,
      fleck,
    );
  }
}

/// [paintPaper] as a widget background.
class StudioPaperView extends StatelessWidget {
  const StudioPaperView({super.key, required this.paper});

  final StudioPaper paper;

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(painter: _PaperPainter(paper)));
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter(this.paper);

  final StudioPaper paper;

  @override
  void paint(Canvas canvas, Size size) => paintPaper(canvas, Offset.zero & size, paper);

  @override
  bool shouldRepaint(_PaperPainter old) => old.paper != paper;
}

/// A photo, decoded no bigger than [maxSide] on its long edge.
Future<ui.Image> loadStudioImage(String path, {int maxSide = 1600}) async {
  final buf = await ui.ImmutableBuffer.fromUint8List(await File(path).readAsBytes());
  final desc = await ui.ImageDescriptor.encoded(buf);
  final s = math.min(1.0, maxSide / math.max(desc.width, desc.height));
  final codec = await desc.instantiateCodec(
    targetWidth: math.max(1, (desc.width * s).round()),
    targetHeight: math.max(1, (desc.height * s).round()),
  );
  final frame = await codec.getNextFrame();
  desc.dispose();
  buf.dispose();
  return frame.image;
}

/// Which part of a photo fills its frame: [x] and [y] from -1 (the left /
/// top edge) through 0 (the middle) to 1 (the right / bottom edge), and how
/// far it's zoomed in (1: the whole frame filled, no more).
class PhotoCrop {
  const PhotoCrop({this.x = 0, this.y = 0, this.zoom = 1});

  final double x, y, zoom;

  static const middle = PhotoCrop();

  bool get isMiddle => x == 0 && y == 0 && zoom == 1;
}

/// The part of [image] that fills a frame shaped [aspect] (width / height)
/// with [crop].
Rect coverSource(ui.Image image, double aspect, [PhotoCrop crop = PhotoCrop.middle]) {
  final iw = image.width.toDouble(), ih = image.height.toDouble();
  var sw = iw, sh = ih;
  if (iw / ih > aspect) {
    sw = ih * aspect;
  } else {
    sh = iw / aspect;
  }
  sw /= crop.zoom;
  sh /= crop.zoom;
  final cx = iw / 2 + crop.x.clamp(-1.0, 1.0) * (iw - sw) / 2;
  final cy = ih / 2 + crop.y.clamp(-1.0, 1.0) * (ih - sh) / 2;
  return Rect.fromCenter(center: Offset(cx, cy), width: sw, height: sh);
}

/// [image] filling [dst], cropped from its middle (or as [crop] says).
void drawCover(Canvas c, ui.Image image, Rect dst, {Paint? paint, PhotoCrop crop = PhotoCrop.middle}) {
  c.drawImageRect(
    image,
    coverSource(image, dst.width / dst.height, crop),
    dst,
    paint ?? (Paint()..filterQuality = FilterQuality.high),
  );
}

void _text(
  Canvas c,
  String s,
  Offset centre,
  double size,
  Color color, {
  double spacing = 3,
  String? family,
}) {
  final pb =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: size, maxLines: 1, fontFamily: family),
        )
        ..pushStyle(
          ui.TextStyle(
            color: color,
            fontSize: size,
            letterSpacing: spacing,
            fontWeight: family == null ? FontWeight.w700 : FontWeight.w600,
            fontFamily: family,
          ),
        )
        ..addText(s);
  final p = pb.build()..layout(const ui.ParagraphConstraints(width: 2000));
  c.drawParagraph(p, Offset(centre.dx - 1000, centre.dy - p.height / 2));
}

String studioDate(DateTime d) {
  const m = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

Future<ui.Image> _record(Size size, void Function(Canvas c) draw) {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec, Offset.zero & size));
  return rec.endRecording().toImage(size.width.round(), size.height.round());
}

/// How a booth strip's date is written.
enum StripDate {
  booth('Printed'),
  hand('Handwritten'),
  off('None');

  const StripDate(this.label);
  final String label;
}

/// Where each frame of a booth strip of [n] goes, and the strip's size
/// ([sprockets]: narrower frames, room down both edges for film holes).
(List<Rect>, Size) stripCells(int n, DateTime date, {bool sprockets = false}) {
  const w = 600.0, cellH = 390.0, top = 40.0, gap = 26.0, foot = 120.0;
  final cellW = sprockets ? 436.0 : 520.0;
  final h = top + n * cellH + (n - 1) * gap + foot;
  final rnd = math.Random(n * 31 + date.day);
  final cells = <Rect>[];
  var y = top;
  for (var i = 0; i < n; i++) {
    final jitter = (rnd.nextDouble() - 0.5) * (sprockets ? 2 : 6);
    cells.add(Rect.fromLTWH((w - cellW) / 2 + jitter, y, cellW, cellH));
    y += cellH + gap + (rnd.nextDouble() - 0.5) * 4;
  }
  return (cells, Size(w, h));
}

/// A photo booth strip: 3 or 4 frames down booth paper, the gaps a touch
/// uneven like a real booth's; each photo framed as [crops] says. At the
/// foot the date ([dateStyle]) and [caption]; [sprockets] punches film
/// holes down both edges.
Future<ui.Image> renderStrip(
  List<ui.Image> photos,
  StudioPaper paper,
  DateTime date, {
  List<PhotoCrop>? crops,
  StripDate dateStyle = StripDate.booth,
  String caption = 'DARKROOM',
  bool sprockets = false,
}) {
  const foot = 120.0;
  final (cells, size) = stripCells(photos.length, date, sprockets: sprockets);
  final w = size.width, h = size.height;
  return _record(size, (c) {
    paintPaper(c, Rect.fromLTWH(0, 0, w, h), paper);
    for (var i = 0; i < photos.length; i++) {
      drawCover(c, photos[i], cells[i], crop: crops?[i] ?? PhotoCrop.middle);
    }
    if (sprockets) {
      // film holes: punched through (the table shows), evenly down each edge
      final hole = Paint()
        ..color = paper == StudioPaper.black ? const Color(0xFF5C4A3A) : const Color(0xFF2A1F17);
      const holeW = 34.0, holeH = 46.0, pitch = 78.0;
      final count = ((h - 30) / pitch).floor();
      final start = (h - (count - 1) * pitch - holeH) / 2;
      for (var i = 0; i < count; i++) {
        for (final x in [24.0, w - 24.0 - holeW]) {
          c.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, start + i * pitch, holeW, holeH),
              const Radius.circular(8),
            ),
            hole,
          );
        }
      }
    }
    final cap = caption.trim();
    final both = dateStyle != StripDate.off && cap.isNotEmpty;
    final mid = h - foot / 2 + 4;
    switch (dateStyle) {
      case StripDate.booth:
        _text(c, studioDate(date), Offset(w / 2, both ? mid - 16 : mid), 26, paper.ink);
      case StripDate.hand:
        // (in pen, a little off the level)
        c.save();
        c.translate(w / 2, both ? mid - 18 : mid);
        c.rotate(-0.035);
        _text(c, _handDate(date), Offset.zero, 46, paper.ink, spacing: 0, family: 'Caveat');
        c.restore();
      case StripDate.off:
        break;
    }
    if (cap.isNotEmpty) {
      _text(
        c,
        cap.toUpperCase(),
        Offset(w / 2, both ? mid + 22 : mid),
        both ? 15 : 22,
        paper.ink.withValues(alpha: both ? 0.7 : 0.9),
        spacing: both ? 6 : 7,
      );
    }
  });
}

String _handDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'June', 'July', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  return "${m[d.month - 1]} ${d.day}, '${(d.year % 100).toString().padLeft(2, '0')}";
}

/// Columns and rows for a collage of [n].
(int, int) collageGrid(int n) => switch (n) {
  2 => (2, 1),
  4 => (2, 2),
  6 => (3, 2),
  _ => (3, 3),
};

/// Where each photo of a collage of [n] in [style] goes (a loose print's
/// photo, untilted), and the collage's size.
(List<Rect>, Size) collageCells(int n, CollageStyle style) {
  final (cols, rows) = collageGrid(n);
  const cell = 800.0;
  final g = switch (style) {
    CollageStyle.grid => 40.0,
    CollageStyle.edge => 0.0,
    CollageStyle.loose => 110.0,
  };
  final w = cols * cell + (cols + 1) * g, h = rows * cell + (rows + 1) * g;
  return (
    [
      for (var i = 0; i < n; i++)
        Rect.fromLTWH(g + (i % cols) * (cell + g), g + (i ~/ cols) * (cell + g), cell, cell),
    ],
    Size(w, h),
  );
}

/// A collage: square photos on [paper], in a neat grid, edge to edge, or
/// loose (bordered prints laid by hand, slightly turned and overlapping);
/// each photo framed as [crops] says.
Future<ui.Image> renderCollage(
  List<ui.Image> photos,
  CollageStyle style,
  StudioPaper paper, {
  List<PhotoCrop>? crops,
}) {
  final (cells, size) = collageCells(photos.length, style);
  final rnd = math.Random(photos.length * 7 + style.index);
  return _record(size, (c) {
    paintPaper(c, Offset.zero & size, paper);
    for (var i = 0; i < photos.length; i++) {
      final r = cells[i];
      final crop = crops?[i] ?? PhotoCrop.middle;
      if (style != CollageStyle.loose) {
        drawCover(c, photos[i], r, crop: crop);
        continue;
      }
      // Loose: a print with a white border, a little bigger than its cell,
      // turned and nudged so neighbours overlap a touch.
      final turn = (rnd.nextDouble() - 0.5) * 0.12;
      final nudge = Offset((rnd.nextDouble() - 0.5) * 40, (rnd.nextDouble() - 0.5) * 40);
      // (a little over its cell: neighbours overlap, the edges stay clear)
      final cardSize = r.width + 60;
      c.save();
      c.translate(r.center.dx + nudge.dx, r.center.dy + nudge.dy);
      c.rotate(turn);
      final card = Rect.fromCenter(center: Offset.zero, width: cardSize, height: cardSize);
      c.drawRect(
        card.shift(const Offset(6, 10)),
        Paint()
          ..color = const Color(0x55000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      c.drawRect(card, Paint()..color = const Color(0xFFF7F4EE));
      drawCover(c, photos[i], card.deflate(26), crop: crop);
      c.restore();
    }
  });
}

/// [image] as a JPEG at [path] (encoded off the UI isolate).
Future<void> writeStudioJpeg(ui.Image image, String path, {int quality = 92}) async =>
    writeStudioPixels(await readStudioPixels(image), path, quality: quality);

/// A picture's pixels (RGBA, 8 bits each), off the GPU.
typedef StudioPixels = ({Uint8List bytes, int width, int height});

/// Reading a picture back from the GPU kept giving noise.
class StudioScrambled implements Exception {
  const StudioScrambled();

  @override
  String toString() => 'The picture came out scrambled. Please try again.';
}

/// True if [bytes] (RGBA, [w] x [h]) is noise, not a picture: what some
/// phones' GPUs hand back now and then when a picture is read from them
/// (saved cards, flip book pages and GIF frames that were coloured snow).
/// In a picture neighbouring pixels are alike; in noise they aren't, all
/// over. Looked at in a 5 x 5 grid of patches, so a busy corner of a real
/// picture doesn't count.
bool looksScrambled(Uint8List bytes, int w, int h) {
  if (w < 40 || h < 40 || bytes.length < w * h * 4) return false;
  var noisy = 0;
  const grid = 5, span = 24;
  for (var gy = 0; gy < grid; gy++) {
    for (var gx = 0; gx < grid; gx++) {
      final x0 = ((gx + 0.5) * w / grid).floor() - span ~/ 2,
          y0 = ((gy + 0.5) * h / grid).floor() - span ~/ 2;
      var sum = 0, n = 0;
      for (var y = y0; y < y0 + span; y += 3) {
        for (var x = x0; x < x0 + span - 1; x++) {
          final i = (y * w + x) * 4;
          sum +=
              (bytes[i] - bytes[i + 4]).abs() +
              (bytes[i + 1] - bytes[i + 5]).abs() +
              (bytes[i + 2] - bytes[i + 6]).abs();
          n += 3;
        }
      }
      // (random bytes differ by 85 on average; a grainy photo by 20 or so)
      if (sum / n > 55) noisy++;
    }
  }
  return noisy >= grid * grid * 0.4;
}

/// Waits for the next frame to be drawn. A picture made off screen is only
/// certain to be finished by the GPU once a frame has gone through after
/// it; read back sooner, some phones hand over whatever was in that memory
/// (see [looksScrambled]). At most 120 ms (nothing may be drawing frames).
Future<void> settleGpu() async {
  try {
    final binding = WidgetsBinding.instance;
    binding.scheduleFrame();
    await Future.any([binding.endOfFrame, Future<void>.delayed(const Duration(milliseconds: 120))]);
  } catch (_) {
    // (no app running: a plain test)
  }
}

/// [image]'s pixels as the GPU gives them, unchecked; [flat]: through a
/// copy drawn into a plain 8-bit picture. Null if it gives none.
Future<Uint8List?> rawStudioPixels(ui.Image image, {required bool flat}) async {
  final w = image.width, h = image.height;
  ByteData? data;
  if (flat) {
    // (through a plain 8-bit picture, whatever the image's own format)
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImage(image, Offset.zero, Paint());
    final picture = rec.endRecording();
    final copy = await picture.toImage(w, h);
    picture.dispose();
    data = await copy.toByteData(format: ui.ImageByteFormat.rawRgba);
    copy.dispose();
  } else {
    data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  }
  if (data == null || data.lengthInBytes != w * h * 4) return null;
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// [image]'s pixels. First the GPU is given a frame to finish it
/// ([settleGpu]: the cure; [settle] false skips that for a first try, where
/// hundreds are read in a row). Then they're checked all the same: if they
/// come back as noise (see [looksScrambled]) they're read again, a frame
/// and a moment later and another way, a few times; [StudioScrambled] if
/// they never come back right. For a picture of something on screen (a
/// RepaintBoundary's): read it before the screen changes.
Future<StudioPixels> readStudioPixels(ui.Image image, {bool settle = true}) async {
  final w = image.width, h = image.height;
  for (var i = 0; i < 4; i++) {
    if (settle || i > 0) await settleGpu();
    if (i > 1) await Future<void>.delayed(Duration(milliseconds: 90 * i));
    final bytes = await rawStudioPixels(image, flat: i.isOdd);
    if (bytes != null && !looksScrambled(bytes, w, h)) return (bytes: bytes, width: w, height: h);
  }
  throw const StudioScrambled();
}

/// The pixels of the picture [draw] makes, checked like [readStudioPixels];
/// drawn afresh if it stays scrambled (up to [tries] times).
Future<StudioPixels> drawStudioPixels(
  Future<ui.Image> Function() draw, {
  int tries = 3,
  bool settle = true,
}) async {
  for (var i = 0; ; i++) {
    final image = await draw();
    try {
      return await readStudioPixels(image, settle: settle);
    } on StudioScrambled {
      if (i + 1 >= tries) rethrow;
    } finally {
      image.dispose();
    }
  }
}

/// [pixels] as a JPEG at [path].
Future<void> writeStudioPixels(StudioPixels pixels, String path, {int quality = 92}) async {
  final (:bytes, width: w, height: h) = pixels;
  await Isolate.run(() {
    final out = img.Image.fromBytes(width: w, height: h, bytes: bytes.buffer, numChannels: 4);
    File(path).writeAsBytesSync(img.encodeJpg(out, quality: quality));
  });
}

/// [pixels] as a PNG at [path] (the flip book's video frames, for the
/// encoder), on another core.
Future<void> writeStudioPng(StudioPixels pixels, String path) {
  final (:bytes, width: w, height: h) = pixels;
  return Isolate.run(() {
    final out = img.Image.fromBytes(width: w, height: h, bytes: bytes.buffer, numChannels: 4);
    File(path).writeAsBytesSync(img.encodePng(out, level: 1, filter: img.PngFilter.none));
  });
}

/// The photo at [from] as a JPEG at [to], at most [maxSide] on its longest
/// side: read, sized and written on another core, never near the GPU (so
/// it can't come out scrambled).
Future<void> copyStudioPhoto(String from, String to, {int maxSide = 1200, int quality = 88}) =>
    Isolate.run(() {
      final decoded = img.decodeImage(File(from).readAsBytesSync());
      if (decoded == null) throw StateError('Could not read $from');
      final pic = img.bakeOrientation(decoded);
      final s = math.min(1.0, maxSide / math.max(pic.width, pic.height));
      final out = s < 1
          ? img.copyResize(
              pic,
              width: math.max(1, (pic.width * s).round()),
              height: math.max(1, (pic.height * s).round()),
              interpolation: img.Interpolation.average,
            )
          : pic;
      File(to).writeAsBytesSync(img.encodeJpg(out, quality: quality));
    });
