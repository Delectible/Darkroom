import 'dart:async';
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

  /// Off-white, not paper-white: real 600 frames scan at ~220-243.
  static const paper = Color(0xFFE9E8E4);

  /// Size of one pebble of the frame's embossed texture, as a fraction of the
  /// print width (matched to scans of real prints).
  static const pebble = 0.0014;

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

  static const maxPictureSide = 3072.0;

  /// Renders the framed print (picture + border + note) to a JPEG at
  /// [outPath]. Runs the drawing on the UI isolate (needs the font engine)
  /// and the JPEG encode on a background isolate.
  static Future<String> exportJpeg({
    required String picturePath,
    required String? note,
    required String outPath,
  }) async {
    // Decoded straight at the export size: a full-resolution decode of a
    // 12 MP shot was most of the wait.
    final buffer = await ui.ImmutableBuffer.fromUint8List(await File(picturePath).readAsBytes());
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final shortSide = math.min(descriptor.width, descriptor.height);
    final k = math.min(1.0, maxPictureSide / shortSide);
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * k).round(),
      targetHeight: (descriptor.height * k).round(),
    );
    final picture = (await codec.getNextFrame()).image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    final side0 = math.min(picture.width, picture.height).toDouble();
    // The camera's full square (a 12 MP sensor's short side), capped so the
    // (pure-Dart) JPEG encode stays quick.
    final s = math.min(side0, maxPictureSide);
    final w = (s * (1 + 2 * side)).round(), h = (s * (1 + top + bottom)).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final texture = await PaperTexture.image();
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      PaperTexture.paint(texture, w.toDouble()),
    );
    final dst = pictureRect(s);
    final src = Rect.fromCenter(
      center: Offset(picture.width / 2, picture.height / 2),
      width: side0,
      height: side0,
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

/// The frame's surface: a fine embossed pebble with faint mottling, as a
/// seamless tile (pure Dart, so tests and isolates can make it too).
class PaperTexture {
  const PaperTexture._();

  static const size = 256;

  /// RGBA8 tile: [InstantFrame.paper] lit from the top left.
  static Uint8List pixels({int seed = 600}) {
    const n = size * size;
    final rnd = math.Random(seed);
    final noise = Float64List(n);
    for (var i = 0; i < n; i++) {
      noise[i] = rnd.nextDouble() - 0.5;
    }
    final pebbles = _blur(noise, 1.3);
    final mottle = _blur(noise, 14);
    // Normalise both.
    double sd(Float64List a) {
      var s2 = 0.0;
      for (final v in a) {
        s2 += v * v;
      }
      return math.sqrt(s2 / a.length);
    }

    final ps = sd(pebbles), ms = sd(mottle);
    final out = Uint8List(n * 4);
    final base = InstantFrame.paper;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        double at(int dx, int dy) =>
            pebbles[((y + dy) % size + size) % size * size + ((x + dx) % size + size) % size];
        // Emboss: slope towards the light.
        final relief = (at(-1, -1) - at(1, 1)) / ps;
        final shade = relief * 2.6 + mottle[y * size + x] / ms * 1.2;
        final i = (y * size + x) * 4;
        out[i] = (base.r * 255 + shade).round().clamp(0, 255);
        out[i + 1] = (base.g * 255 + shade).round().clamp(0, 255);
        out[i + 2] = (base.b * 255 + shade * 0.9).round().clamp(0, 255);
        out[i + 3] = 255;
      }
    }
    return out;
  }

  static Float64List _blur(Float64List src, double sigma) {
    final r = (sigma * 3).ceil();
    final k = Float64List(2 * r + 1);
    var ks = 0.0;
    for (var i = -r; i <= r; i++) {
      k[i + r] = math.exp(-0.5 * (i / sigma) * (i / sigma));
      ks += k[i + r];
    }
    final tmp = Float64List(src.length), dst = Float64List(src.length);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        var a = 0.0;
        for (var i = -r; i <= r; i++) {
          a += src[y * size + (x + i + size) % size] * k[i + r];
        }
        tmp[y * size + x] = a / ks;
      }
    }
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        var a = 0.0;
        for (var i = -r; i <= r; i++) {
          a += tmp[((y + i + size) % size) * size + x] * k[i + r];
        }
        dst[y * size + x] = a / ks;
      }
    }
    return dst;
  }

  static Future<ui.Image>? _image;

  /// The tile as a GPU image (made once).
  static Future<ui.Image> image() => _image ??= () {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels(), size, size, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }();

  /// Loaded tile for painting on screen (null until ready: plain paper).
  static final ValueNotifier<ui.Image?> loaded = ValueNotifier(null);

  static void ensureLoaded() {
    if (loaded.value == null) unawaited(image().then((i) => loaded.value = i));
  }

  /// Paint that fills with the textured paper for a print [printWidth] wide
  /// ([minTexel] keeps a pebble at least that many target pixels across).
  static Paint paint(ui.Image tile, double printWidth, {double minTexel = 1}) {
    final scale = math.max(printWidth * InstantFrame.pebble, minTexel);
    return Paint()
      ..shader = ImageShader(
        tile,
        TileMode.repeated,
        TileMode.repeated,
        Float64List.fromList([scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
      )
      ..filterQuality = FilterQuality.medium;
  }
}
