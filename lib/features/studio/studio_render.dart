import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
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

/// [image] filling [dst], cropped from its middle.
void drawCover(Canvas c, ui.Image image, Rect dst, {Paint? paint}) {
  final iw = image.width.toDouble(), ih = image.height.toDouble();
  final want = dst.width / dst.height;
  var src = Rect.fromLTWH(0, 0, iw, ih);
  if (iw / ih > want) {
    final w = ih * want;
    src = Rect.fromLTWH((iw - w) / 2, 0, w, ih);
  } else {
    final h = iw / want;
    src = Rect.fromLTWH(0, (ih - h) / 2, iw, h);
  }
  c.drawImageRect(image, src, dst, paint ?? (Paint()..filterQuality = FilterQuality.high));
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

/// A photo booth strip: 3 or 4 frames down booth paper, the date at the
/// foot, the gaps a touch uneven like a real booth's.
Future<ui.Image> renderStrip(List<ui.Image> photos, StudioPaper paper, DateTime date) {
  const w = 600.0, cellW = 520.0, cellH = 390.0, top = 40.0, gap = 26.0, foot = 120.0;
  final h = top + photos.length * cellH + (photos.length - 1) * gap + foot;
  final rnd = math.Random(photos.length * 31 + date.day);
  return _record(Size(w, h), (c) {
    c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = paper.color);
    var y = top;
    for (final p in photos) {
      final jitter = (rnd.nextDouble() - 0.5) * 6;
      drawCover(c, p, Rect.fromLTWH((w - cellW) / 2 + jitter, y, cellW, cellH));
      y += cellH + gap + (rnd.nextDouble() - 0.5) * 4;
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

/// A collage: square photos on [paper], in a neat grid, edge to edge, or
/// loose (bordered prints laid by hand, slightly turned and overlapping).
Future<ui.Image> renderCollage(List<ui.Image> photos, CollageStyle style, StudioPaper paper) {
  final (cols, rows) = collageGrid(photos.length);
  const cell = 800.0;
  final g = switch (style) {
    CollageStyle.grid => 40.0,
    CollageStyle.edge => 0.0,
    CollageStyle.loose => 110.0,
  };
  final w = cols * cell + (cols + 1) * g, h = rows * cell + (rows + 1) * g;
  final rnd = math.Random(photos.length * 7 + style.index);
  return _record(Size(w, h), (c) {
    c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = paper.color);
    for (var i = 0; i < photos.length; i++) {
      final col = i % cols, row = i ~/ cols;
      final r = Rect.fromLTWH(g + col * (cell + g), g + row * (cell + g), cell, cell);
      if (style != CollageStyle.loose) {
        drawCover(c, photos[i], r);
        continue;
      }
      // Loose: a print with a white border, a little bigger than its cell,
      // turned and nudged so neighbours overlap a touch.
      final turn = (rnd.nextDouble() - 0.5) * 0.12;
      final nudge = Offset((rnd.nextDouble() - 0.5) * 40, (rnd.nextDouble() - 0.5) * 40);
      // (a little over its cell: neighbours overlap, the edges stay clear)
      final size = cell + 60;
      c.save();
      c.translate(r.center.dx + nudge.dx, r.center.dy + nudge.dy);
      c.rotate(turn);
      final card = Rect.fromCenter(center: Offset.zero, width: size, height: size);
      c.drawRect(
        card.shift(const Offset(6, 10)),
        Paint()
          ..color = const Color(0x55000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      c.drawRect(card, Paint()..color = const Color(0xFFF7F4EE));
      drawCover(c, photos[i], card.deflate(26));
      c.restore();
    }
  });
}

/// A flip book page (4:5, Instagram's tall post): the photo as a bordered
/// print on [paper], shaken by [shake] (0..1 picks the wobble) for the
/// handheld snap from page to page.
Future<ui.Image> renderFlipPage(ui.Image photo, StudioPaper paper, int shake) {
  const w = 1080.0, h = 1350.0;
  final rnd = math.Random(shake * 977 + photo.width);
  return _record(const Size(w, h), (c) {
    c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = paper.color);
    final aspect = photo.width / photo.height;
    var pw = 920.0, ph = pw / aspect;
    if (ph > 1120) {
      ph = 1120;
      pw = ph * aspect;
    }
    c.save();
    c.translate(w / 2 + (rnd.nextDouble() - 0.5) * 14, h / 2 + (rnd.nextDouble() - 0.5) * 14);
    c.rotate((rnd.nextDouble() - 0.5) * 0.025);
    final card = Rect.fromCenter(center: Offset.zero, width: pw + 40, height: ph + 40);
    c.drawRect(
      card.shift(const Offset(5, 9)),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    c.drawRect(card, Paint()..color = const Color(0xFFF7F4EE));
    c.drawImageRect(
      photo,
      Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: pw, height: ph),
      Paint()..filterQuality = FilterQuality.high,
    );
    c.restore();
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
