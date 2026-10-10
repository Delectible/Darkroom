// Dev-only: runs sample photos through a digital camera's still pipeline
// (shrink, sharpen / grade with LookRenderer, the real low-quality JPEG
// pass) and writes each render plus a contact sheet (rows = photos,
// columns = original + render).
//   CAMERA=floppy99 dart run tool/look_preview.dart outdir photo1.jpg ...
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;

import 'package:darkroom/core/processing/look_renderer.dart';
import 'package:darkroom/core/processing/look_spec.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final out = Directory(args.first)..createSync(recursive: true);
  final spec = CameraCatalog.byId(Platform.environment['CAMERA'] ?? 'floppy99');
  final look = spec.look!;
  final profile = spec.output;
  final flash = Platform.environment['FLASH'] == '1' ? 1.0 : 0.0;
  final cells = <(img.Image, img.Image)>[];
  for (final (i, path) in args.skip(1).indexed) {
    var src = img.decodeImage(File(path).readAsBytesSync())!;
    src = src.convert(format: img.Format.uint8, numChannels: 3);
    // 4:3, like the camera
    final h43 = (src.width * 3 / 4).round();
    src = h43 <= src.height
        ? img.copyCrop(src, x: 0, y: (src.height - h43) ~/ 2, width: src.width, height: h43)
        : img.copyCrop(
            src,
            x: (src.width - src.height * 4 ~/ 3) ~/ 2,
            y: 0,
            width: src.height * 4 ~/ 3,
            height: src.height,
          );
    final long = profile.lowResLongEdge ?? profile.maxLongEdge;
    final scale = long / math.max(src.width, src.height);
    var image = img.copyResize(
      src,
      width: (src.width * scale).round(),
      height: (src.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
    final orig = image.clone();
    final w = image.width, h = image.height;
    final data = image.toUint8List();
    final r = LookRenderer(look, seed: 7 + i);
    if (look.kind == ShaderKind.ccd) {
      r.sharpen(data, w, h, radius: math.max(1, (w / LookSpec.referenceWidth).round()));
    } else if (look.kind == ShaderKind.jpegPixel) {
      r.sharpen(data, w, h);
    } else if (look.kind == ShaderKind.vhs) {
      r.vhsSignal(data, w, h);
    }
    r.grade(data, w, h, flash: flash);
    image = img.Image.fromBytes(width: w, height: h, bytes: data.buffer, numChannels: 3);
    if (profile.lowResJpegQuality != null) {
      image = img.decodeJpg(
        img.encodeJpg(image, quality: profile.lowResJpegQuality!, chroma: img.JpegChroma.yuv420),
      )!;
    }
    File('${out.path}/render_$i.jpg').writeAsBytesSync(img.encodeJpg(image, quality: profile.jpegQuality));
    cells.add((orig, image));
  }
  const cw = 480, ch = 360;
  final sheet = img.Image(width: cw * 2, height: ch * cells.length);
  for (final (i, (a, b)) in cells.indexed) {
    img.compositeImage(
      sheet,
      img.copyResize(a, width: cw, height: ch),
      dstX: 0,
      dstY: i * ch,
    );
    img.compositeImage(
      sheet,
      img.copyResize(b, width: cw, height: ch),
      dstX: cw,
      dstY: i * ch,
    );
  }
  File('${out.path}/sheet.jpg').writeAsBytesSync(img.encodeJpg(sheet, quality: 90));
  print('wrote ${cells.length} renders to ${out.path}');
}
