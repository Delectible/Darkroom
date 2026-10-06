import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:darkroom/core/processing/crop_math.dart';
import 'package:darkroom/core/processing/film/film_lut.dart';
import 'package:darkroom/core/processing/film/film_profile.dart';
import 'package:darkroom/core/processing/film/film_uniforms.dart';
import 'package:darkroom/core/processing/film/grain_field.dart';
import 'package:darkroom/core/processing/look_spec.dart';
import 'package:darkroom/core/processing/video_filters.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';

/// Counts float slots of the non-sampler uniforms declared in a .frag file.
int _floatSlots(String source) {
  const sizes = {'float': 1, 'vec2': 2, 'vec3': 3, 'vec4': 4, 'mat2': 4, 'mat3': 9, 'mat4': 16};
  final re = RegExp(r'^\s*uniform\s+(\w+)\s+\w+\s*;', multiLine: true);
  var n = 0;
  for (final m in re.allMatches(source)) {
    n += sizes[m.group(1)] ?? 0; // sampler2D => 0
  }
  return n;
}

int _samplers(String source) =>
    RegExp(r'^\s*uniform\s+sampler2D\s', multiLine: true).allMatches(source).length;

/// Filters that need --enable-gpl or an external library, i.e. that are NOT
/// in FFmpegKit's LGPL "min" build. Using any of them makes the whole
/// filtergraph fail with "Error initializing complex filters".
/// (From FFmpeg's configure: *_filter_deps="gpl" plus external-lib filters.)
const _notInMinBuild = {
  'blackframe', 'boxblur', 'colormatrix', 'cover_rect', 'cropdetect', 'delogo', 'eq', 'find_rect', //
  'fspp', 'histeq', 'hqdn3d', 'interlace', 'kerndeint', 'mcdeint', 'mpdecimate', 'mptestsrc', 'nnedi',
  'owdenoise', 'perspective', 'phase', 'pp', 'pp7', 'pullup', 'repeatfields', 'sab', 'signature',
  'smartblur', 'spp', 'stereo3d', 'super2xsai', 'tinterlace', 'uspp', 'vaguedenoiser', 'vidstabdetect',
  'vidstabtransform', 'drawtext', 'subtitles', 'ass', 'zscale', 'frei0r', 'ocr', 'libplacebo', 'zmq',
};

void main() {
  group('Dart <-> GLSL uniform layout', () {
    for (final kind in ShaderKind.values.where((k) => k != ShaderKind.film)) {
      test(kind.asset, () {
        final src = File(kind.asset).readAsStringSync();
        final look = CameraCatalog.all.firstWhere((c) => c.look?.kind == kind).look!;
        final dart = 2 + look.commonUniforms(time: 0).length + look.extraUniforms().length;
        expect(_floatSlots(src), dart);
        expect(2 + look.commonUniforms(time: 0).length, LookSpec.extraUniformStart);
        expect(_samplers(src), 1);
      });
    }

    test('shaders/film.frag', () {
      final src = File(ShaderKind.film.asset).readAsStringSync();
      final floats = FilmUniformLayout.floats(
        FilmProfile.forStock('super8')!,
        time: 0,
        crop: const UnitRect(0, 0, 1, 1),
        grain: GrainStrength.normal,
        fps: 18,
      );
      expect(_floatSlots(src), 2 + floats.length);
      expect(2 + floats.length, FilmUniformLayout.floatCount);
      expect(_samplers(src), 3); // camera, LUT, grain
    });
  });

  group('Film model', () {
    for (final spec in CameraCatalog.film) {
      test('${spec.id}: neutral axis stays neutral-ish and monotonic', () {
        final lut = FilmLut.build(spec.film!, size: 17);
        final out = List<double>.filled(3, 0);
        var prev = -1.0;
        for (var i = 0; i <= 40; i++) {
          final s = LutShaper.encode(i / 40 * 1.5);
          lut.sample(s, s, s, out);
          final l = 0.2126 * out[0] + 0.7152 * out[1] + 0.0722 * out[2];
          expect(l, greaterThanOrEqualTo(prev - 1e-3), reason: 'step $i');
          prev = l;
          // Split toning allowed, but greys must not turn into colours.
          expect((out[0] - out[2]).abs(), lessThan(0.09), reason: 'step $i');
        }
      });
    }

    test('mid grey maps near mid grey', () {
      for (final spec in CameraCatalog.film) {
        final out = List<double>.filled(3, 0);
        FilmModel(spec.film!).evaluate(0.18, 0.18, 0.18, out);
        final l = 0.2126 * out[0] + 0.7152 * out[1] + 0.0722 * out[2];
        expect(l, inInclusiveRange(0.36, 0.62), reason: spec.id);
      }
    });

    test('B&W stocks are exactly neutral', () {
      final out = List<double>.filled(3, 0);
      FilmModel(FilmProfile.forStock('hp5plus400')!).evaluate(0.6, 0.1, 0.3, out);
      expect(out[0], closeTo(out[1], 1e-9));
      expect(out[1], closeTo(out[2], 1e-9));
    });

    test('shaper round-trips', () {
      for (final x in [0.0, 0.001, 0.18, 1.0, 3.9]) {
        expect(LutShaper.decode(LutShaper.encode(x)), closeTo(x, 1e-9));
      }
    });

    test('GLSL shaper constant matches Dart', () {
      final src = File(ShaderKind.film.asset).readAsStringSync();
      final norm = double.parse(RegExp(r'kShaperNorm = ([0-9.]+)').firstMatch(src)!.group(1)!);
      expect(norm, closeTo(math.log(1 + 31 * LutShaper.maxLinear), 1e-6));
      final dec = double.parse(RegExp(r'kGrainDecode = ([0-9.]+)').firstMatch(src)!.group(1)!);
      expect(dec, closeTo(255 / GrainField.encodeScale, 1e-6));
    });

    test('grain tile is zero-mean unit-variance and tileable', () {
      final g = GrainField.generate(size: 64);
      for (var c = 0; c < 3; c++) {
        var sum = 0.0, sum2 = 0.0;
        for (var i = 0; i < 64 * 64; i++) {
          final v = g.data[i * 3 + c];
          sum += v;
          sum2 += v * v;
        }
        expect(sum / 4096, closeTo(0, 1e-3));
        expect(math.sqrt(sum2 / 4096), closeTo(1, 1e-3));
      }
      // wrap-around sampling is continuous across the seam
      expect((g.sample(63.999, 10, 0) - g.sample(-0.001, 10, 0)).abs(), lessThan(1e-2));
    });

    test('.cube export has size^3 rows', () {
      final cube = FilmLut.build(FilmProfile.forStock('super8')!, size: 9, input: LutInput.srgb).toCube();
      final rows = cube.split('\n').where((l) => RegExp(r'^[0-9]').hasMatch(l)).length;
      expect(rows, 9 * 9 * 9);
    });
  });

  group('VideoFilters', () {
    test('lutrgb expressions are single-quoted (filtergraph-safe)', () {
      final lut = VideoFilters.lut(CameraCatalog.camcorder.look!);
      expect(RegExp("r='[^']+'").hasMatch(lut), isTrue);
      expect(lut.contains('st(0,'), isTrue);
    });

    test('every graph only uses filters present in the LGPL min build', () {
      const crop = PixelRect(0, 0, 1080, 1440);
      final graphs = <String>[];
      for (final spec in CameraCatalog.all) {
        final profile = VideoProfile.forSpec(spec);
        for (final turns in [0, 1]) {
          if (spec.film != null) {
            graphs.add(
              VideoFilters.filmGraph(
                film: spec.film!,
                grain: GrainStrength.strong,
                cubePath: '/tmp/x.cube',
                crop: crop,
                outW: 720,
                outH: 540,
                profile: profile,
                rotateTurns: turns,
              ),
            );
          } else {
            graphs.add(
              VideoFilters.graph(
                look: spec.look!,
                crop: crop,
                outW: 640,
                outH: 480,
                profile: profile,
                hasOsd: true,
                osdInputIndex: 2,
                osdW: 100,
                osdH: 20,
                rotateTurns: turns,
              ),
            );
          }
        }
      }
      for (final g in graphs) {
        final used = VideoFilters.filterNames(g);
        expect(used.intersection(_notInMinBuild), isEmpty, reason: g);
        expect(used, isNotEmpty);
      }
      expect(VideoFilters.filterNames(graphs.first).contains('crop'), isTrue);
    });
  });
}
