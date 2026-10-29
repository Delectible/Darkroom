import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:darkroom/core/processing/crop_math.dart';
import 'package:darkroom/core/processing/look_renderer.dart';
import 'package:darkroom/core/processing/look_spec.dart';
import 'package:darkroom/core/shaders/shader_library.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The digital viewfinder (the real shader) against the saved photo (the
/// still pipeline's shrink, look and JPEG) for the bodies that save small
/// photos: they should look alike. `SRC=photo.jpg SHOTS=dir` saves
/// viewfinder | photo pairs; without SRC a test card just runs the shader.
void main() {
  final src = Platform.environment['SRC'];
  final shots = Platform.environment['SHOTS'];

  Future<ui.Image> toUi(img.Image im) async {
    final rgba = im.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
    final buffer = await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(rgba));
    final desc = ui.ImageDescriptor.raw(
      buffer,
      width: im.width,
      height: im.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    return (await (await desc.instantiateCodec()).getNextFrame()).image;
  }

  Future<img.Image> fromUi(ui.Image im) async {
    final bytes = (await im.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return img.Image.fromBytes(
      width: im.width,
      height: im.height,
      bytes: bytes.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
  }

  for (final id in [
    'floppy99',
    'webcam05',
    'ccd2003',
    'dslr08',
    'flipphone',
    'toycam',
    'camcorder90',
    'minidv04',
  ]) {
    testWidgets('viewfinder matches the photo: $id', (tester) async {
      await tester.runAsync(() async {
        final spec = CameraCatalog.byId(id);
        final look = spec.look!;
        // The scene, 3:4 portrait like the frame.
        var scene = src == null
            ? img.Image(width: 900, height: 1200)
            : img.decodeImage(File(src).readAsBytesSync())!;
        if (src == null) {
          for (final p in scene) {
            p
              ..r = (p.x * 255 ~/ 900)
              ..g = (p.y * 255 ~/ 1200)
              ..b = ((p.x ~/ 30 + p.y ~/ 30) % 2) * 200;
          }
        }
        scene = scene.convert(format: img.Format.uint8, numChannels: 3);
        final h = (scene.width * 4 / 3).round().clamp(1, scene.height);
        scene = img.copyCrop(scene, x: 0, y: (scene.height - h) ~/ 2, width: scene.width, height: h);

        // Viewfinder: the preview stream (1080 wide) drawn on a phone's
        // viewfinder (1236 px wide) through the look shader.
        final stream = img.copyResize(scene, width: 1080, interpolation: img.Interpolation.average);
        const vw = 1236.0;
        final vh = (vw * stream.height / stream.width).roundToDouble();
        final program = await ui.FragmentProgram.fromAsset(look.kind.asset);
        final shader = program.fragmentShader();
        shader.setImageSampler(0, await toUi(stream));
        LookUniforms.apply(shader, look, time: 0, crop: const UnitRect(0, 0, 1, 1), size: ui.Size(vw, vh));
        final rec = ui.PictureRecorder();
        ui.Canvas(rec).drawRect(ui.Rect.fromLTWH(0, 0, vw, vh), ui.Paint()..shader = shader);
        final finder = await fromUi(await rec.endRecording().toImage(vw.toInt(), vh.toInt()));

        // Photo: as photo_pipeline does it.
        final profile = spec.output;
        final (tw, th) = CropMath.fitLongEdge(
          scene.width,
          scene.height,
          profile.lowResLongEdge ?? profile.maxLongEdge,
        );
        var photo = img.copyResize(scene, width: tw, height: th, interpolation: img.Interpolation.average);
        final data = photo.getBytes(order: img.ChannelOrder.rgb);
        final r = LookRenderer(look, seed: 7);
        switch (look.kind) {
          case ShaderKind.ccd:
            r.sharpen(data, tw, th, radius: math.max(1, (tw / LookSpec.referenceWidth).round()));
          case ShaderKind.vhs:
            r.vhsSignal(data, tw, th);
          case ShaderKind.jpegPixel:
            r.sharpen(data, tw, th);
          case ShaderKind.film:
            break;
        }
        r.grade(data, tw, th, flash: 0);
        photo = img.Image.fromBytes(width: tw, height: th, bytes: data.buffer, numChannels: 3);
        if (profile.lowResJpegQuality != null) {
          photo = img.decodeJpg(img.encodeJpg(photo, quality: profile.lowResJpegQuality!))!;
        }
        if (profile.upscale > 1) {
          photo = img.copyResize(
            photo,
            width: tw * profile.upscale,
            height: th * profile.upscale,
            interpolation: img.Interpolation.nearest,
          );
        }

        // Same tone on average (the colour maths is shared).
        double mean(img.Image im) {
          var s = 0.0;
          for (final p in im) {
            s += p.r + p.g + p.b;
          }
          return s / (im.width * im.height * 3);
        }

        expect((mean(finder) - mean(photo)).abs(), lessThan(12));

        if (shots != null) {
          // before | viewfinder | photo; "before" = the full-size viewfinder
          // (no saved-size pixels or JPEG).
          if (look.kind == ShaderKind.ccd) {
            shader
              ..setFloat(LookSpec.extraUniformStart + 4, 0)
              ..setFloat(LookSpec.extraUniformStart + 5, 0);
          }
          final rec2 = ui.PictureRecorder();
          ui.Canvas(rec2).drawRect(ui.Rect.fromLTWH(0, 0, vw, vh), ui.Paint()..shader = shader);
          final before = await fromUi(await rec2.endRecording().toImage(vw.toInt(), vh.toInt()));
          final shown = img.copyResize(photo, width: finder.width, height: finder.height);
          final row = img.Image(width: finder.width * 3 + 32, height: finder.height);
          img.fill(row, color: img.ColorRgb8(255, 255, 255));
          img.compositeImage(row, before.convert(numChannels: 3));
          img.compositeImage(row, finder.convert(numChannels: 3), dstX: finder.width + 16);
          img.compositeImage(row, shown.convert(numChannels: 3), dstX: finder.width * 2 + 32);
          File('$shots/match_$id.png').writeAsBytesSync(img.encodePng(row));
        }
      });
    });
  }
}
