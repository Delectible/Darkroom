// Dev-only: renders sample photos through every film profile and writes a
// contact sheet (rows = photos, columns = original + stocks).
//   dart run tool/film_preview.dart out.jpg photo1.jpg photo2.png ...
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:darkroom/core/processing/film/film_profile.dart';
import 'package:darkroom/core/processing/film/film_renderer.dart';

void main(List<String> args) {
  final out = args.first;
  final stocks = (Platform.environment['STOCKS'] ?? 'ektar100,portra400,hp5plus400').split(',');
  final cell = int.parse(Platform.environment['CELL'] ?? '360');
  final strength = GrainStrength.fromName(Platform.environment['GRAIN']);
  final rows = <List<img.Image>>[];
  for (final path in args.skip(1)) {
    var src = img.decodeImage(File(path).readAsBytesSync())!;
    src = src.convert(format: img.Format.uint8, numChannels: 3);
    // Simulate a camera-resolution frame, render at that size, then shrink for
    // the sheet (grain must be judged at viewing scale, not at 1:1).
    final res = int.parse(Platform.environment['RES'] ?? '2400');
    final up = res / (src.width > src.height ? src.width : src.height);
    src = img.copyResize(
      src,
      width: (src.width * up).round(),
      height: (src.height * up).round(),
      interpolation: img.Interpolation.cubic,
    );
    final scale = cell / (src.width > src.height ? src.width : src.height);
    img.Image shrink(img.Image i) => img.copyResize(
      i,
      width: (i.width * scale).round(),
      height: (i.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
    final row = <img.Image>[shrink(src)];
    for (final id in stocks) {
      final p = FilmProfile.forStock(id)!;
      final copy = src.clone();
      final data = copy.toUint8List();
      final sw = Stopwatch()..start();
      FilmRenderer(p, seed: 42, grain: strength).render(data, copy.width, copy.height, flash: 0);
      sw.stop();
      final done = img.Image.fromBytes(
        width: copy.width,
        height: copy.height,
        bytes: data.buffer,
        numChannels: 3,
      );
      row.add(shrink(done));
      if (Platform.environment['CROP'] == '1') {
        row.add(
          img.copyCrop(done, x: done.width ~/ 2 - cell ~/ 2, y: done.height ~/ 3, width: cell, height: cell),
        );
      }
      stderr.writeln('$path $id ${sw.elapsedMilliseconds}ms');
    }
    rows.add(row);
  }
  final cols = rows.first.length;
  final sheet = img.Image(width: cols * (cell + 8) + 8, height: rows.length * (cell + 8) + 8);
  img.fill(sheet, color: img.ColorRgb8(18, 18, 18));
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < cols; c++) {
      final im = rows[r][c];
      img.compositeImage(
        sheet,
        im,
        dstX: 8 + c * (cell + 8) + (cell - im.width) ~/ 2,
        dstY: 8 + r * (cell + 8) + (cell - im.height) ~/ 2,
      );
    }
  }
  File(out).writeAsBytesSync(img.encodeJpg(sheet, quality: 90));
  print('wrote $out');
}
