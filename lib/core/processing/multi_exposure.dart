import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// A double exposure: two captures on one frame, as film takes them (the
/// light of both added on the negative, each a little under so the sum
/// isn't blown out). Done on the captures themselves, before the shot is
/// queued, so the film's processing sees one frame as ever.
class MultiExposure {
  MultiExposure._();

  /// Blends [first] and [second] (camera JPEGs) into [out], keeping the first
  /// one's EXIF (the exposure the film reads), turned upright.
  static Future<void> blend(String first, String second, String out) => compute(_blend, (first, second, out));

  static void _blend((String, String, String) a) {
    final (firstPath, secondPath, outPath) = a;
    final first = img.decodeJpg(File(firstPath).readAsBytesSync());
    final second = img.decodeJpg(File(secondPath).readAsBytesSync());
    if (first == null || second == null) throw const FormatException('Capture could not be decoded');
    final exif = img.ExifData.from(first.exif);
    var a0 = img.bakeOrientation(first);
    var b0 = img.bakeOrientation(second);
    a0 = a0.convert(format: img.Format.uint8, numChannels: 3);
    // the second fills the first's frame (cropped to its shape if the phone
    // was turned between them)
    final k = math.max(a0.width / b0.width, a0.height / b0.height);
    final cw = (a0.width / k).round().clamp(1, b0.width), ch = (a0.height / k).round().clamp(1, b0.height);
    b0 = img.copyCrop(b0, x: (b0.width - cw) ~/ 2, y: (b0.height - ch) ~/ 2, width: cw, height: ch);
    b0 = img.copyResize(b0, width: a0.width, height: a0.height, interpolation: img.Interpolation.average);
    b0 = b0.convert(format: img.Format.uint8, numChannels: 3);
    final pa = a0.toUint8List(), pb = b0.toUint8List();
    final out = Uint8List(pa.length);
    final lin = Float64List(256);
    for (var i = 0; i < 256; i++) {
      final c = i / 255;
      lin[i] = c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }
    // light added in linear terms, each frame about two thirds of a stop
    // under; a soft shoulder instead of a hard clip
    const gain = 0.62;
    for (var i = 0; i < pa.length; i++) {
      final l = (lin[pa[i]] + lin[pb[i]]) * gain;
      final s = l / (1 + l * 0.18) * 1.18;
      final v = s <= 0.0031308 ? s * 12.92 : 1.055 * math.pow(s, 1 / 2.4) - 0.055;
      out[i] = (v * 255).round().clamp(0, 255);
    }
    final result = img.Image.fromBytes(width: a0.width, height: a0.height, bytes: out.buffer, numChannels: 3);
    exif.imageIfd.orientation = 1;
    result.exif = exif;
    File(outPath).writeAsBytesSync(img.encodeJpg(result, quality: 95), flush: true);
  }
}
