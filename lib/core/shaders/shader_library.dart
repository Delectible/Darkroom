import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../processing/crop_math.dart';
import '../processing/film/film_lut.dart';
import '../processing/film/film_profile.dart';
import '../processing/film/film_uniforms.dart';
import '../processing/film/grain_field.dart';
import '../processing/isolate_jobs.dart';
import '../processing/look_spec.dart';

/// Loads every compiled .frag once per app run.
class ShaderPrograms {
  const ShaderPrograms(this.looks, this.cork);

  final Map<ShaderKind, ui.FragmentProgram> looks;
  final ui.FragmentProgram cork;

  static Future<ShaderPrograms> load() async {
    final entries = await Future.wait(
      ShaderKind.values.map((k) async {
        return MapEntry(k, await ui.FragmentProgram.fromAsset(k.asset));
      }),
    );
    final cork = await ui.FragmentProgram.fromAsset('shaders/cork_board.frag');
    return ShaderPrograms(Map.fromEntries(entries), cork);
  }
}

final shaderProgramsProvider = FutureProvider<ShaderPrograms>((ref) => ShaderPrograms.load());

Future<ui.Image> _imageFromPixels(Uint8List px, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// The shared grain tile (built off the UI thread once per run).
final grainImageProvider = FutureProvider<ui.Image>((ref) async {
  final px = await grainPixelsInIsolate();
  final img = await _imageFromPixels(px, GrainField.defaultSize, GrainField.defaultSize);
  ref.onDispose(img.dispose);
  return img;
});

/// A film stock's LUT as a GPU texture.
final filmLutImageProvider = FutureProvider.family<ui.Image, String>((ref, stockId) async {
  final px = await filmLutPixelsInIsolate(stockId);
  const n = FilmLut.defaultSize;
  final img = await _imageFromPixels(px, n * n, n);
  ref.onDispose(img.dispose);
  return img;
});

/// Writes a digital [LookSpec]'s uniforms using the float layout documented
/// at the top of each .frag file.
class LookUniforms {
  const LookUniforms._();

  /// [size] is null when the shader is used through ImageFilter.shader (the
  /// engine owns `uSize`), set for the sampler-based fallback.
  static void apply(
    ui.FragmentShader shader,
    LookSpec look, {
    required double time,
    required UnitRect crop,
    double flash = 0,
    ui.Size? size,
  }) {
    if (size != null) {
      shader
        ..setFloat(0, size.width)
        ..setFloat(1, size.height);
    }
    var i = 2;
    for (final v in look.commonUniforms(
      time: time,
      flash: flash,
      crop: [crop.left, crop.top, crop.width, crop.height],
    )) {
      shader.setFloat(i++, v);
    }
    assert(i == LookSpec.extraUniformStart, 'uniform layout drifted from the .frag files');
    for (final v in look.extraUniforms()) {
      shader.setFloat(i++, v);
    }
  }
}

/// Uniforms + textures for shaders/film.frag.
class FilmUniforms {
  const FilmUniforms._();

  static void apply(
    ui.FragmentShader shader,
    FilmProfile p, {
    required double time,
    required UnitRect crop,
    required GrainStrength grain,
    required double fps,
    required ui.Image lut,
    required ui.Image grainImage,
    ui.Size? size,
  }) {
    if (size != null) {
      shader
        ..setFloat(0, size.width)
        ..setFloat(1, size.height);
    }
    var i = 2;
    for (final v in FilmUniformLayout.floats(p, time: time, crop: crop, grain: grain, fps: fps)) {
      shader.setFloat(i++, v);
    }
    assert(i == FilmUniformLayout.floatCount, 'film uniform layout drifted from shaders/film.frag');
    shader
      ..setImageSampler(1, lut, filterQuality: ui.FilterQuality.low)
      ..setImageSampler(2, grainImage, filterQuality: ui.FilterQuality.low);
  }
}
