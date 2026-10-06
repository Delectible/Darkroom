import 'dart:math' as math;

import '../../features/cameras/domain/camera_spec.dart';
import 'cine_strip.dart';
import 'crop_math.dart';
import 'film/film_profile.dart';
import 'look_spec.dart';

/// Per-camera video encode settings.
class VideoProfile {
  const VideoProfile({
    required this.longEdge,
    required this.fps,
    required this.bitrateKbps,
    this.upscale = 1,
    this.audioArgs = const ['-c:a', 'aac', '-b:a', '128k'],
    this.audioFilter,
  });

  final int longEdge;
  final String fps;
  final int bitrateKbps;

  /// Nearest-neighbour upscale in a second pass (keeps fat pixels crisp).
  final int upscale;
  final List<String> audioArgs;
  final String? audioFilter;

  static VideoProfile forSpec(CameraSpec spec) {
    if (spec.film != null) {
      // Super 8: 18 fps, sound-camera style mono audio.
      return const VideoProfile(
        longEdge: 720,
        fps: '18',
        bitrateKbps: 4500, // grain is expensive to encode; starve it and it smears
        audioArgs: ['-c:a', 'aac', '-b:a', '80k', '-ac', '1', '-ar', '32000'],
        audioFilter: 'highpass=f=110,lowpass=f=6500,acompressor=threshold=0.125:ratio=2.5',
      );
    }
    return switch (spec.look!.kind) {
      // 2003 compacts: 640x480 movie mode at 15 fps, mono audio.
      ShaderKind.ccd || ShaderKind.film => const VideoProfile(
        longEdge: 640,
        fps: '15',
        bitrateKbps: 2500,
        audioArgs: ['-c:a', 'aac', '-b:a', '64k', '-ac', '1'],
        audioFilter: 'highpass=f=150,lowpass=f=7000',
      ),
      // QCIF-class phone video, 12 fps, 8 kHz voice-band audio.
      ShaderKind.jpegPixel => const VideoProfile(
        longEdge: 176,
        fps: '12',
        bitrateKbps: 96,
        upscale: 3,
        audioArgs: ['-c:a', 'aac', '-b:a', '24k', '-ac', '1', '-ar', '8000'],
        audioFilter: 'highpass=f=300,lowpass=f=3400',
      ),
      ShaderKind.vhs => const VideoProfile(
        longEdge: 640,
        fps: '30000/1001',
        bitrateKbps: 1800,
        audioArgs: ['-c:a', 'aac', '-b:a', '96k', '-ac', '1'],
        audioFilter: 'highpass=f=80,lowpass=f=9000,acompressor=threshold=0.1:ratio=3',
      ),
    };
  }
}

/// Builds FFmpeg filtergraphs that reproduce each look, using only filters
/// compiled into the LGPL "min" FFmpegKit build (no GPL filters such as
/// boxblur / eq / hqdn3d, no libfreetype). test/video_filters_lgpl_test.dart
/// fails the build if a GPL-only filter sneaks back in.
class VideoFilters {
  const VideoFilters._();

  static String _f(double v) => v.toStringAsFixed(5);

  /// lutrgb expression for one channel: offset, exposure, clip, gamma,
  /// S-curve, black/white points, optional posterise.
  static String toneExpr(LookSpec look, double offset, {double posterize = 0}) {
    final p = _f(look.pivot), k = _f(look.contrast), g = _f(look.gamma);
    final b = _f(look.black), w = _f(look.white - look.black);
    final x = 'st(0,pow(clip((val/255+${_f(offset)})*${_f(look.exposure)},0,1),$g))';
    final s = 'if(lt(ld(0),$p),$p*pow(ld(0)/$p,$k),1-(1-$p)*pow((1-ld(0))/(1-$p),$k))';
    final y = '($b+$w*$s)';
    final out = posterize > 1
        ? 'round(clip($y,0,1)*${_f(posterize)})/${_f(posterize)}*255'
        : 'clip($y,0,1)*255';
    return '$x;$out';
  }

  static String colorMatrix(LookSpec look) {
    final m = look.combinedMatrix();
    return 'colorchannelmixer='
        'rr=${_f(m[0])}:rg=${_f(m[1])}:rb=${_f(m[2])}:'
        'gr=${_f(m[3])}:gg=${_f(m[4])}:gb=${_f(m[5])}:'
        'br=${_f(m[6])}:bg=${_f(m[7])}:bb=${_f(m[8])}';
  }

  static String lut(LookSpec look, {double posterize = 0}) {
    final o = look.combinedOffset();
    return "lutrgb=r='${toneExpr(look, o[0], posterize: posterize)}'"
        ":g='${toneExpr(look, o[1], posterize: posterize)}'"
        ":b='${toneExpr(look, o[2], posterize: posterize)}'";
  }

  /// Even output size for an oriented crop.
  static (int, int) outputSize(PixelRect crop, VideoProfile profile) {
    final (w, h) = CropMath.fitLongEdge(crop.width, crop.height, profile.longEdge);
    return (math.max(2, w - w % 2), math.max(2, h - h % 2));
  }

  static List<String> _geometry(PixelRect crop, int rotateTurns, int outW, int outH, VideoProfile profile) =>
      [
        'crop=${crop.width}:${crop.height}:${crop.x}:${crop.y}',
        ...switch (rotateTurns % 4) {
          1 => ['transpose=1'],
          2 => ['hflip', 'vflip'],
          3 => ['transpose=2'],
          _ => const <String>[],
        },
        'scale=$outW:$outH:flags=area',
        'fps=${profile.fps}',
        'setsar=1',
      ];

  /// Digital looks. Inputs: [0:v] camera clip, [1:v] scanline PNG (VHS only,
  /// looped), [N:v] timestamp PNG sequence (if [hasOsd]). Output: [vout].
  static String graph({
    required LookSpec look,
    required PixelRect crop,
    required int outW,
    required int outH,
    required VideoProfile profile,
    required bool hasOsd,
    required int osdInputIndex,
    required int osdW,
    required int osdH,
    int rotateTurns = 0,
    List<String> extraOverlays = const [],
  }) {
    final chain = _geometry(crop, rotateTurns, outW, outH, profile);

    switch (look.kind) {
      case ShaderKind.ccd || ShaderKind.film:
        chain
          ..add('unsharp=5:5:${_f(look.sharpen * 1.6)}:5:5:0')
          ..add('format=gbrp')
          ..add(colorMatrix(look))
          ..add(lut(look))
          ..add('format=yuv420p');
        final cn = (look.chromaNoise * 255 * 0.6).round();
        chain.add('noise=c1s=$cn:c2s=$cn:c1f=t:c2f=t');
      case ShaderKind.jpegPixel:
        if (look.vignette > 0) chain.add('vignette=a=${_f(look.vignette * 3.2)}');
        chain
          ..add('format=gbrp')
          ..add(colorMatrix(look))
          ..add(lut(look, posterize: look.posterize))
          ..add('format=yuv420p')
          ..add('noise=alls=${(look.grainAmount * 255).round()}:allf=t');
      case ShaderKind.vhs:
        final bleedH = (look.bleed * 6).round();
        final jit = _f(look.jitter * 2.5);
        chain
          // ~240 lines of horizontal luma resolution.
          ..add('scale=${(outW * 0.55).round() & ~1}:$outH:flags=bilinear')
          ..add('scale=$outW:$outH:flags=bicubic')
          ..add('pad=${outW + 8}:$outH:4:0')
          ..add("crop=$outW:$outH:'4+$jit*sin(t*2.3)+$jit*(random(0)-0.5)':0")
          ..add('vignette=a=${_f(look.vignette * 3.2)}')
          ..add('format=gbrp')
          ..add(colorMatrix(look))
          ..add(lut(look))
          ..add('format=yuv444p')
          ..add('chromashift=cbh=$bleedH:crh=${(bleedH * 0.6).round()}')
          // Soft tape chroma. avgblur (LGPL) on the chroma planes only;
          // boxblur would be equivalent but is GPL-only and absent from the
          // min build ("Error initializing complex filters").
          ..add('avgblur=sizeX=3:sizeY=1:planes=6')
          ..add('noise=c0s=${(look.grainAmount * 255).round()}:c0f=t+u');
    }

    final g = StringBuffer('[0:v]${chain.join(',')}[base]');
    var last = 'base';
    if (look.kind == ShaderKind.vhs) {
      g.write(';[$last][1:v]overlay=0:0:shortest=1:format=auto[scan]');
      last = 'scan';
    }
    if (hasOsd) {
      final x = outW - osdW - (outW * 0.06).round();
      final y = outH - osdH - (outH * 0.06).round();
      g.write(';[$last][$osdInputIndex:v]overlay=$x:$y:eof_action=repeat[osd]');
      last = 'osd';
    }
    // Further decals: each entry is "[N:v]overlay=..." (see OsdLayer).
    for (var i = 0; i < extraOverlays.length; i++) {
      g.write(';[$last]${extraOverlays[i]}[dec$i]');
      last = 'dec$i';
    }
    g.write(';[$last]format=yuv420p[vout]');
    return g.toString();
  }

  /// Super 8. Inputs: [0:v] camera clip, [1:v] looping dust/hair PNG
  /// sequence, [2:v] the film strip around the frame (CineStrip, canvas
  /// [canvasW]x[canvasH]). [cubePath] is the stock's LUT with sRGB input
  /// (same film model as the preview and the stills). The picture is
  /// [outW]x[outH]; the reel is the full-gate scan around it.
  static String filmGraph({
    required FilmProfile film,
    required GrainStrength grain,
    required String cubePath,
    required PixelRect crop,
    required int outW,
    required int outH,
    required VideoProfile profile,
    int rotateTurns = 0,
    int? canvasW,
    int? canvasH,
  }) {
    final cw = canvasW ?? outW, chh = canvasH ?? outH;
    final weaveX = math.max(1.0, outH * 0.0035 * film.weave);
    final weaveY = math.max(1.0, outH * 0.0055 * film.weave);
    final pad = (math.max(weaveX, weaveY) * 2).ceil() + 2;
    final halSigma = _f(math.max(2.0, outH * 0.014));
    final res = film.grainResolution * grain.resolution;
    final grainW = (outW * res / outH / 1.3).round().clamp(64, outW) & ~1;
    final grainH = (res / 1.3).round().clamp(48, outH) & ~1;
    // The grain stream below has a std of ~24 levels; grainmerge adds it.
    // Matched to Gabe's Super 8 scans (fine, ~0.015 high-pass in the frame).
    final grainOpacity = _f((film.grainAmount * grain.factor * 255 / 24 * 0.3).clamp(0.0, 1.0));
    final halOpacity = _f((film.halation * 1.6).clamp(0.0, 1.0));
    final hr = (255 * film.halationColor[0]).round(), hg = (255 * film.halationColor[1]).round();
    final hb = (255 * film.halationColor[2]).round();

    final base = [
      ..._geometry(crop, rotateTurns, outW, outH, profile),
      // Super 8 is soft: a small lens on a 5.8 mm frame.
      'gblur=sigma=${_f(math.max(0.6, outH / 720 * 1.1))}',
      'format=gbrp',
      "lut3d=file='$cubePath':interp=tetrahedral",
      // Exposure flicker: a jump every frame plus a slow pulse (uneven
      // shutter and lamp), clearly visible like real home movies.
      'format=yuv444p',
      "hue=b='${_f(1.1 * film.flicker)}*(random(3)-0.5)+${_f(0.35 * film.flicker)}*sin(6.1*t)*sin(1.7*t)'",
      'format=gbrp',
      'split=2[img][hi]',
    ].join(',');
    // Full-gate composite: the frame, slivers of its neighbours across the
    // frame lines, then the strip (edges, sprocket hole) on top.
    final x0 = (CineStrip.picX * cw).round(), y0 = (CineStrip.picY * chh).round();
    final gapPx = (CineStrip.gap * chh).round();
    final topH = math.max(2, y0 - gapPx), botY = y0 + outH + gapPx, botH = math.max(2, chh - botY);
    final strip = film.gate > 0
        ? [
            '[dusty]split=3[fa][fb][fc]',
            '[fb]crop=$outW:$topH:0:${outH - topH}[ftop]',
            '[fc]crop=$outW:$botH:0:0[fbot]',
            '[fa]pad=$cw:$chh:$x0:$y0:color=0x120c0a[c0]',
            '[c0][ftop]overlay=$x0:0[c1]',
            '[c1][fbot]overlay=$x0:$botY[c2]',
            '[c2][2:v]overlay=0:0:format=auto[gated]',
          ]
        : ['[dusty]null[gated]'];

    return [
      '[0:v]$base',
      // Halation: highlights -> red-orange glow -> screen.
      "[hi]lutrgb=r='clip((val-205)*${hr / 255 * 4.2},0,255)':g='clip((val-205)*${hg / 255 * 4.2},0,255)'"
          ":b='clip((val-205)*${hb / 255 * 4.2},0,255)',gblur=sigma=$halSigma[glow]",
      '[img][glow]blend=all_mode=screen:all_opacity=$halOpacity[hal]',
      // Coarse grain: mid-grey noise at grain resolution, scaled up, merged.
      // Mostly-luma noise with a little chroma, like dye clouds.
      'color=c=0x808080:s=${grainW}x$grainH:r=${profile.fps},format=yuv444p,'
          'noise=c0s=100:c0f=t+u:c1s=${(60 * film.grainChroma).round()}:c1f=t+u'
          ':c2s=${(60 * film.grainChroma).round()}:c2f=t+u,scale=$outW:$outH:flags=bicubic,format=gbrp[grain]',
      '[hal][grain]blend=all_mode=grainmerge:all_opacity=$grainOpacity:shortest=1[grained]',
      '[grained]format=yuv444p,vignette=a=${_f(film.vignette * 2.2)}[vig]',
      '[vig][1:v]overlay=0:0:shortest=1:format=auto[dusty]',
      ...strip,
      // Gate weave: the film hops a pixel or two in the gate every frame.
      '[gated]pad=${cw + 2 * pad}:${chh + 2 * pad}:$pad:$pad:color=0x120c0a,'
          "crop=$cw:$chh:'$pad+${_f(weaveX)}*(random(1)-0.5)':'$pad+${_f(weaveY)}*(random(2)-0.5)',"
          'format=yuv420p[vout]',
    ].join(';');
  }

  /// Filter names used by a filtergraph string (for the LGPL test).
  static Set<String> filterNames(String graph) {
    final names = <String>{};
    for (final chain in graph.split(';')) {
      var rest = chain.trim();
      // Strip leading [labels].
      while (rest.startsWith('[')) {
        rest = rest.substring(rest.indexOf(']') + 1);
      }
      for (final part in _splitTopLevel(rest, ',')) {
        var f = part.trim();
        while (f.startsWith('[')) {
          f = f.substring(f.indexOf(']') + 1);
        }
        final name = f.split(RegExp(r'[=\[]')).first.trim();
        if (name.isNotEmpty) names.add(name);
      }
    }
    return names;
  }

  /// Splits on [sep] outside single quotes.
  static List<String> _splitTopLevel(String s, String sep) {
    final out = <String>[];
    var quoted = false;
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == "'") quoted = !quoted;
      if (!quoted && c == sep) {
        out.add(s.substring(start, i));
        start = i + 1;
      }
    }
    out.add(s.substring(start));
    return out;
  }

  /// Sanity check used by tests: profile + timestamp style combination.
  static bool wantsOsd(CameraSpec spec, bool timestampEnabled) =>
      timestampEnabled && spec.timestampStyle != TimestampStyle.none;
}
