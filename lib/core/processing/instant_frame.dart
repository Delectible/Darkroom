import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// Proportions of an integral instant print (square picture, thin sides and
/// top, deep writing strip at the bottom), as fractions of the picture side.
/// One source for the corkboard, the viewer and exported files.
class InstantFrame {
  const InstantFrame._();

  static const side = 0.057;
  static const top = 0.072;
  static const bottom = 0.28;

  /// Width / height of the whole print.
  static const aspect = (1 + 2 * side) / (1 + top + bottom);

  static const paper = Color(0xFFF7F5EF);

  /// Felt-tip ink for notes.
  static const ink = Color(0xFF1F2A44);

  static const maxNoteLength = 40;

  /// Handwriting for a picture [side] px wide (font bundled in pubspec).
  static TextStyle noteStyle(double pictureSide) => TextStyle(
    fontFamily: 'Caveat',
    fontWeight: FontWeight.w600,
    fontSize: pictureSide * 0.09,
    height: 1.05,
    color: ink,
  );

  /// The picture's rect inside a print of the given picture side.
  static Rect pictureRect(double s) => Rect.fromLTWH(side * s, top * s, s, s);

  /// The writing strip under the picture.
  static Rect noteRect(double s) => Rect.fromLTWH(side * s, (top + 1) * s, s, bottom * s);

  /// Slight tilt so the note reads as written by hand.
  static const noteAngle = -0.025;

  /// Lays out [note] to fit the writing strip (two lines at most).
  static TextPainter notePainter(String note, double s) {
    final tp = TextPainter(
      text: TextSpan(text: note, style: noteStyle(s)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: s * 0.94);
    return tp;
  }

  /// Renders the framed print (picture + border + note) to a JPEG at
  /// [outPath]. Runs the drawing on the UI isolate (needs the font engine)
  /// and the JPEG encode on a background isolate.
  static Future<String> exportJpeg({required String picturePath, required String? note, required String outPath}) async {
    final codec = await ui.instantiateImageCodec(await File(picturePath).readAsBytes());
    final picture = (await codec.getNextFrame()).image;
    codec.dispose();
    final s = math.min(picture.width, picture.height).toDouble();
    final w = (s * (1 + 2 * side)).round(), h = (s * (1 + top + bottom)).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = paper);
    final dst = pictureRect(s);
    final src = Rect.fromCenter(
      center: Offset(picture.width / 2, picture.height / 2),
      width: s,
      height: s,
    );
    canvas.drawImageRect(picture, src, dst, Paint()..filterQuality = FilterQuality.high);
    // The picture sits a hair below the paper surface.
    canvas.drawRect(
      dst,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, s / 600)
        ..color = const Color(0x22000000),
    );
    if (note != null && note.trim().isNotEmpty) {
      final tp = notePainter(note.trim(), s);
      final area = noteRect(s);
      canvas.save();
      canvas.translate(area.center.dx, area.center.dy);
      canvas.rotate(noteAngle);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    final framed = await recorder.endRecording().toImage(w, h);
    picture.dispose();
    final rgba = await framed.toByteData(format: ui.ImageByteFormat.rawRgba);
    framed.dispose();
    final jpeg = await compute(_encode, (rgba!.buffer.asUint8List(), w, h));
    final out = File(outPath);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(jpeg, flush: true);
    return outPath;
  }

  static Uint8List _encode((Uint8List, int, int) a) {
    final (bytes, w, h) = a;
    final image = img.Image.fromBytes(width: w, height: h, bytes: bytes.buffer, numChannels: 4);
    return img.encodeJpg(image, quality: 92);
  }
}
