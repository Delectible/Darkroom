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

void _text(Canvas c, String s, Offset centre, double size, Color color, {double spacing = 3}) {
  final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: size))
    ..pushStyle(
      ui.TextStyle(color: color, fontSize: size, letterSpacing: spacing, fontWeight: FontWeight.w700),
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

/// Where each frame of a booth strip of [n] goes, and the strip's size.
(List<Rect>, Size) stripCells(int n, DateTime date) {
  const w = 600.0, cellW = 520.0, cellH = 390.0, top = 40.0, gap = 26.0, foot = 120.0;
  final h = top + n * cellH + (n - 1) * gap + foot;
  final rnd = math.Random(n * 31 + date.day);
  final cells = <Rect>[];
  var y = top;
  for (var i = 0; i < n; i++) {
    final jitter = (rnd.nextDouble() - 0.5) * 6;
    cells.add(Rect.fromLTWH((w - cellW) / 2 + jitter, y, cellW, cellH));
    y += cellH + gap + (rnd.nextDouble() - 0.5) * 4;
  }
  return (cells, Size(w, h));
}

/// A photo booth strip: 3 or 4 frames down booth paper, the date at the
/// foot, the gaps a touch uneven like a real booth's; each photo framed as
/// [crops] says.
Future<ui.Image> renderStrip(
  List<ui.Image> photos,
  StudioPaper paper,
  DateTime date, {
  List<PhotoCrop>? crops,
}) {
  const foot = 120.0;
  final (cells, size) = stripCells(photos.length, date);
  final w = size.width, h = size.height;
  return _record(size, (c) {
    paintPaper(c, Rect.fromLTWH(0, 0, w, h), paper);
    for (var i = 0; i < photos.length; i++) {
      drawCover(c, photos[i], cells[i], crop: crops?[i] ?? PhotoCrop.middle);
    }
    _text(c, studioDate(date), Offset(w / 2, h - foot / 2 - 12), 26, paper.ink);
    _text(c, 'DARKROOM', Offset(w / 2, h - foot / 2 + 22), 15, paper.ink.withValues(alpha: 0.7), spacing: 6);
  });
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
Future<void> writeStudioJpeg(ui.Image image, String path, {int quality = 92}) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('No pixels');
  final w = image.width, h = image.height;
  final bytes = data.buffer.asUint8List();
  await Isolate.run(() {
    final out = img.Image.fromBytes(width: w, height: h, bytes: bytes.buffer, numChannels: 4);
    File(path).writeAsBytesSync(img.encodeJpg(out, quality: quality));
  });
}

/// [image] as a PNG at [path] (the flip book's pages, for the encoder).
Future<void> writeStudioPng(ui.Image image, String path) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('No pixels');
  await File(path).writeAsBytes(Uint8List.sublistView(data));
}
