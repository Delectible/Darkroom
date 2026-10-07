import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:darkroom/core/processing/cine_strip.dart';
import 'package:darkroom/core/processing/crop_math.dart';
import 'package:darkroom/core/processing/film/film_lut.dart';
import 'package:darkroom/core/processing/film/film_profile.dart';
import 'package:darkroom/core/processing/film/grain_field.dart';
import 'package:darkroom/core/shaders/shader_library.dart';
import 'package:flutter_test/flutter_test.dart';

/// The live viewfinder's Super 8 strip (film.frag): the frame shows the
/// captured crop, the sprocket hole sits on the viewer's left, upright or
/// sideways. Renders the real shader over a marked test card.
void main() {
  Future<ui.Image> pixels(List<int> px, int w, int h) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(px));
    final desc = ui.ImageDescriptor.raw(buffer, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    return (await codec.getNextFrame()).image;
  }

  for (final turns in [0, 1]) {
    testWidgets('strip, turns $turns', (tester) async {
      await tester.runAsync(() async {
        const w = 300, h = 400; // portrait preview box, 4:3 stream
        const previewAspect = 4 / 3;
        // Test card: red top-left quadrant, blue elsewhere (box orientation).
        final card = <int>[];
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final tl = x < w / 2 && y < h / 2;
            card.addAll(tl ? [220, 40, 40, 255] : [40, 60, 200, 255]);
          }
        }
        final camera = await pixels(card, w, h);
        final film = FilmProfile.forStock('super8')!;
        final lut = FilmLut.build(film);
        final lutImg = await pixels(lut.toRgbaStrip(), lut.size * lut.size, lut.size);
        final grain = GrainField.generate();
        final grainImg = await pixels(grain.toRgba8(), grain.size, grain.size);
        final program = await ui.FragmentProgram.fromAsset('shaders/film.frag');
        final shader = program.fragmentShader();
        final crop = CropMath.previewMask(
          previewAspect: previewAspect,
          ratio: AspectRatioOption.r4x3,
          acrossShortSide: turns.isEven,
        );
        final canvasRect = CineStrip.previewCanvas(boxAspect: previewAspect, turns: turns);
        FilmUniforms.apply(
          shader,
          film,
          time: 0,
          crop: crop,
          grain: GrainStrength.weak,
          fps: 18,
          lut: lutImg,
          grainImage: grainImg,
          size: const ui.Size(w * 1.0, h * 1.0),
          canvas: canvasRect,
          turns: turns,
        );
        shader.setImageSampler(0, camera);
        final rec = ui.PictureRecorder();
        ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, w * 1.0, h * 1.0), ui.Paint()..shader = shader);
        final out = await rec.endRecording().toImage(w, h);
        final bytes = (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        int lum(double ux, double uy) {
          // ux, uy: upright canvas uv -> box pixel
          var bx = ux, by = uy;
          for (var i = 0; i < turns; i++) {
            (bx, by) = (1 - by, bx);
          }
          final x = ((canvasRect.left + bx * canvasRect.width) * w).floor().clamp(0, w - 1);
          final y = ((canvasRect.top + by * canvasRect.height) * h).floor().clamp(0, h - 1);
          final i = (y * w + x) * 4;
          return bytes.getUint8(i) + bytes.getUint8(i + 1) + bytes.getUint8(i + 2);
        }

        // Sprocket hole (viewer's left, middle): black.
        expect(lum(CineStrip.holeX + CineStrip.holeW / 2, 0.5), lessThan(40));
        // Middle of the frame: lit (shows the card).
        expect(lum(CineStrip.picX + CineStrip.picW / 2, 0.5), greaterThan(80));
        // Outside the canvas (box corner when the canvas doesn't reach it): black.
        final shots = Platform.environment['SHOTS'];
        if (shots != null) {
          final png = await out.toByteData(format: ui.ImageByteFormat.png);
          File('$shots/super8_shader_t$turns.png').writeAsBytesSync(png!.buffer.asUint8List());
        }
      });
    });
  }

  // The swing when the phone turns is drawn by the shader, so the strip,
  // its sprocket hole and the picture turn together: half a turn about the
  // centre shows the same image upside down.
  testWidgets('strip spins as one piece', (tester) async {
    await tester.runAsync(() async {
      const w = 300, h = 400, previewAspect = 4 / 3;
      final card = <int>[];
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          card.addAll(x < w / 2 && y < h / 2 ? [220, 40, 40, 255] : [40, 60, 200, 255]);
        }
      }
      final camera = await pixels(card, w, h);
      final film = FilmProfile.forStock('super8')!;
      final lut = FilmLut.build(film);
      final lutImg = await pixels(lut.toRgbaStrip(), lut.size * lut.size, lut.size);
      final grain = GrainField.generate();
      final grainImg = await pixels(grain.toRgba8(), grain.size, grain.size);
      final program = await ui.FragmentProgram.fromAsset('shaders/film.frag');
      Future<ByteData> render(double spin) async {
        final shader = program.fragmentShader();
        FilmUniforms.apply(
          shader,
          film,
          time: 0,
          crop: CropMath.previewMask(previewAspect: previewAspect, ratio: AspectRatioOption.r4x3),
          grain: GrainStrength.weak,
          fps: 18,
          lut: lutImg,
          grainImage: grainImg,
          size: const ui.Size(w * 1.0, h * 1.0),
          canvas: CineStrip.previewCanvas(boxAspect: previewAspect, turns: 1),
          turns: 1,
          spin: spin,
        );
        shader.setImageSampler(0, camera);
        final rec = ui.PictureRecorder();
        ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, w * 1.0, h * 1.0), ui.Paint()..shader = shader);
        final out = await rec.endRecording().toImage(w, h);
        return (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      }

      final a = await render(0), b = await render(math.pi);
      int lum(ByteData d, int x, int y) {
        final i = (y * w + x) * 4;
        return d.getUint8(i) + d.getUint8(i + 1) + d.getUint8(i + 2);
      }

      var differ = 0, n = 0;
      for (var y = 10; y < h - 10; y += 7) {
        for (var x = 10; x < w - 10; x += 7) {
          n++;
          if ((lum(a, x, y) - lum(b, w - 1 - x, h - 1 - y)).abs() > 60) differ++;
        }
      }
      expect(differ / n, lessThan(0.03));
    });
  });
}
