import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../features/cameras/domain/camera_spec.dart';
import 'lens_renderer.dart';

/// A movie camera's lens in the FFmpeg graph: the same lenses the viewfinder
/// shows (shaders/lens.frag), on the [w]x[h] picture before the strip / OSD.
/// LGPL filters only (remap, overlay, split, gblur, blend, lut, vignette).
class VideoLens {
  VideoLens._(this.inputArgs, this._chain);

  /// Extra inputs it needs (appended after the graph's own).
  final List<String> inputArgs;
  final String Function(String from, String to, int firstInput) _chain;

  /// The filters from label [from] to label [to]; its inputs start at
  /// [firstInput] (the number of inputs before them).
  String chain(String from, String to, int firstInput) => _chain(from, to, firstInput);

  /// What [lens] needs at [w]x[h] (files written to [dir]); null: nothing.
  static VideoLens? prepare(LensKind lens, int w, int h, String dir) => switch (lens) {
    LensKind.fisheye => _fisheye(w, h, dir),
    LensKind.mist => VideoLens._(
      const [],
      (from, to, _) =>
          '[$from]format=gbrp,split[mista][mistb];'
          "[mistb]lutrgb=r='clip((val-89)*1.54,0,255)':g='clip((val-89)*1.54,0,255)':b='clip((val-89)*1.54,0,255)',"
          'gblur=sigma=${_f(math.max(2.0, h * 0.02))}[mistg];'
          '[mista][mistg]blend=all_mode=screen:all_opacity=0.6,'
          "lutrgb=r='val*0.9+15':g='val*0.9+15':b='val*0.9+15'[$to]",
    ),
    LensKind.anamorphic => VideoLens._(
      const [],
      (from, to, _) =>
          '[$from]format=gbrp,split[anaa][anab];'
          "[anab]format=gray,lut=c0='clip((val-217)*12,0,255)',"
          'gblur=sigma=${_f(math.max(4.0, w * 0.07))}:sigmaV=0.6,format=gbrp,'
          'colorchannelmixer=rr=0.35:gg=0.6:bb=1[anas];'
          '[anaa][anas]blend=all_mode=screen,vignette=angle=0.5[$to]',
    ),
    _ => null,
  };

  /// The fish-eye: a pixel map (where each output pixel comes from, at half
  /// a pixel's precision: the picture is doubled first, remap is nearest)
  /// and an overlay for the black outside, the falloff and the coating line.
  static VideoLens _fisheye(int w, int h, String dir) {
    final xs = Uint8List(w * h * 2), ys = Uint8List(w * h * 2);
    final over = img.Image(width: w, height: h, numChannels: 4);
    final mn = math.min(w, h).toDouble();
    final rad = LensRenderer.fishRadius(w, h), sh = 0.5 * mn;
    const bevel = LensRenderer.fishBevel, jog = LensRenderer.fishJog, cap = LensRenderer.fishCap;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final px = x + 0.5 - w / 2, py = y + 0.5 - h / 2;
        final len = math.sqrt(px * px + py * py);
        final rm = len / rad;
        final dx = len > 1e-4 ? px / len : 0.0, dy = len > 1e-4 ? py / len : 0.0;
        final r1 = math.min(rm, 1.0);
        final b = ((r1 - bevel) / (1 - bevel)).clamp(0.0, 1.0);
        final sb = b * b * (3 - 2 * b);
        final rq = r1 - jog * (1 - bevel) * sb;
        final th = 2 * math.asin(rq * 0.7071068);
        final rs = math.tan(th * cap / 1.5707963) / math.tan(cap);
        // (source, in the doubled picture's pixels)
        final sx = ((w / 2 + dx * rs * sh) * 2).round().clamp(0, w * 2 - 1);
        final sy = ((h / 2 + dy * rs * sh) * 2).round().clamp(0, h * 2 - 1);
        final i = (y * w + x) * 2;
        xs[i] = sx >> 8;
        xs[i + 1] = sx & 255;
        ys[i] = sy >> 8;
        ys[i + 1] = sy & 255;
        // the overlay: black outside, the falloff inside, the blue line
        final edge = ((1 - rm) * rad / (0.004 * mn) + 0.5).clamp(0.0, 1.0);
        final f = ((r1 - 0.86) / 0.14).clamp(0.0, 1.0);
        final keep = (1 - 0.22 * math.pow(r1, 4)) * (1 - 0.5 * f * f) * edge;
        final ring = math.pow(((r1 - 0.982) / 0.018).clamp(0.0, 1.0), 1.5).toDouble() * edge;
        final dark = 1 - keep;
        final a = (dark + ring * 0.55 * (1 - dark)).clamp(0.0, 1.0);
        final blueShare = a <= 0 ? 0.0 : ring * 0.55 * (1 - dark) / a;
        over.setPixelRgba(
          x,
          y,
          (8 * blueShare).round(),
          (25 * blueShare).round(),
          (80 * blueShare).round(),
          (a * 255).round(),
        );
      }
    }
    Uint8List pgm(Uint8List data) {
      final head = 'P5\n$w $h\n65535\n'.codeUnits;
      return Uint8List.fromList([...head, ...data]);
    }

    final xp = p.join(dir, 'fish_x.pgm'), yp = p.join(dir, 'fish_y.pgm'), op = p.join(dir, 'fish_over.png');
    File(xp).writeAsBytesSync(pgm(xs));
    File(yp).writeAsBytesSync(pgm(ys));
    File(op).writeAsBytesSync(img.encodePng(over, level: 1));
    return VideoLens._(
      ['-i', xp, '-i', yp, '-loop', '1', '-i', op],
      (from, to, n) =>
          '[$from]scale=${w * 2}:${h * 2}:flags=bilinear[fishup];'
          '[fishup][$n:v][${n + 1}:v]remap[fishr];'
          '[fishr][${n + 2}:v]overlay=0:0:shortest=1:format=auto[$to]',
    );
  }

  static String _f(double v) => v.toStringAsFixed(2);
}
