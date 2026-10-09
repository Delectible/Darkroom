import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cameras/domain/camera_spec.dart';
import '../../settings/application/settings_controllers.dart';
import 'art_cache.dart';

/// The photoreal cameras (1.6): each body rendered whole in Blender
/// (tool/render/blender/whole_body.py) through one perspective camera,
/// face-on (`rest`, without its moving parts), each moving part alone in
/// each state with the shadow it casts (`layers`), and the whole body
/// turned every few degrees for the swap (`turns`, the shutters on their own
/// so Super 8 / camcorder can swap theirs in).
///
/// Everything sits in one design space, 412 x 968 dp: the face is laid out
/// from the same numbers (manifest `layout`) and scaled to the screen's
/// width. Phones less tall than that lose a band out of the middle of the
/// viewfinder ([DesignFit]), which the live picture covers.
class WholeArt {
  WholeArt._(this.design, this.cutY, this.dist, this.bodies);

  static const root = 'assets/body3';

  final Size design;

  /// Design y the image is split at for shorter phones (in the viewfinder).
  final double cutY;

  /// Camera distance from the face, design dp.
  final double dist;
  final Map<AppMode, WholeBody> bodies;

  /// Frames that weren't decoded yet when drawn (tests: a swap needs none).
  static int lateFrames = 0;

  /// Turn frames are decoded as rendered (sharp when a turn is held mid-
  /// drag); all of them stay decoded, ~250 MB for both bodies. Lower this
  /// (e.g. 1.2) to trade sharpness for memory.
  static const double? turnPx = null;

  static Future<WholeArt?> load() async {
    try {
      final j = jsonDecode(await rootBundle.loadString('$root/manifest.json')) as Map<String, dynamic>;
      final d = j['design'] as Map<String, dynamic>;
      final bodies = <AppMode, WholeBody>{};
      for (final mode in AppMode.values) {
        final b = j[mode.name] as Map<String, dynamic>?;
        final lay = (j['layout'] as Map<String, dynamic>?)?[mode.name] as Map<String, dynamic>?;
        if (b == null || lay == null || b['rest'] == null || b['turns'] == null) continue;
        bodies[mode] = WholeBody._fromJson(b, lay);
      }
      if (bodies.isEmpty) return null;
      return WholeArt._(
        Size((d['w'] as num).toDouble(), (d['h'] as num).toDouble()),
        (d['cutY'] as num).toDouble(),
        (d['dist'] as num).toDouble(),
        bodies,
      );
    } catch (_) {
      return null; // not bundled: the classic bodies
    }
  }

  /// Decodes what a swap and the face need, rest and layers first, and
  /// keeps it for the session ([ArtCache]).
  Future<void> precache(BuildContext context) => warm(
    MediaQuery.devicePixelRatioOf(context),
    MediaQuery.sizeOf(context).width,
    config: createLocalImageConfiguration(context),
  );

  /// [precache] without a context (at launch, behind the launch screen);
  /// the turned frames too unless [turned] is false.
  Future<void> warm(double dpr, double width, {ImageConfiguration? config, bool turned = true}) async {
    final cfg = config ?? ImageConfiguration(devicePixelRatio: dpr);
    final s = width / design.width;
    final first = <ImageProvider>[], then = <ImageProvider>[];
    for (final b in bodies.values) {
      first.add(b.rest.image(s * dpr));
      for (final l in b.layers.values) {
        first.add(l.image(s * dpr));
      }
      for (final t in b.turns) {
        then.add(t.body.image(turnPx));
        for (final sh in t.shutters.values) {
          then.add(sh.image(turnPx));
        }
      }
    }
    await ArtCache.pinAll(first, cfg);
    if (turned) await ArtCache.pinAll(then, cfg);
  }
}

/// One image of the art: its file and where it goes, in design dp.
class ArtRect {
  ArtRect(this.path, this.rect, this.px);

  factory ArtRect.fromJson(Map<String, dynamic> j) {
    final r = (j['rect'] as List<dynamic>).cast<num>();
    return ArtRect(
      '${WholeArt.root}/${j['path']}',
      Rect.fromLTWH(r[0].toDouble(), r[1].toDouble(), r[2].toDouble(), r[3].toDouble()),
      (j['px'] as num?)?.toDouble() ?? 1,
    );
  }

  final String path;
  final Rect rect;

  /// Pixels per design dp in the file.
  final double px;

  /// Decoded at [pxPerDp] (screen pixels per design dp), or as stored.
  ImageProvider image(double? pxPerDp) {
    final asset = AssetImage(path);
    if (pxPerDp == null || pxPerDp >= px * 0.95) return asset;
    return ResizeImage(asset, width: (rect.width * pxPerDp).round(), policy: ResizeImagePolicy.fit);
  }
}

class TurnFrame {
  TurnFrame(this.yaw, this.body, this.shutters, this.lug);

  final int yaw;
  final ArtRect body;

  /// Each shutter (film release, Super 8 RUN, digital key, camcorder REC)
  /// turned with the body, drawn over [body].
  final Map<String, ArtRect> shutters;

  /// The strap lug, design dp.
  final Offset lug;
}

class WholeBody {
  WholeBody._(this.rest, this.layers, this.turns, this.layout);

  factory WholeBody._fromJson(Map<String, dynamic> j, Map<String, dynamic> lay) {
    final turns = <TurnFrame>[];
    for (final MapEntry(key: yaw, value: t) in (j['turns'] as Map<String, dynamic>).entries) {
      final t2 = t as Map<String, dynamic>;
      final lug = (t2['lug'] as List<dynamic>?)?.cast<num>() ?? const [0, 0];
      turns.add(
        TurnFrame(int.parse(yaw), ArtRect.fromJson(t2), {
          for (final MapEntry(key: k, value: v)
              in ((t2['shutters'] as Map<String, dynamic>?) ?? const {}).entries)
            k: ArtRect.fromJson(v as Map<String, dynamic>),
        }, Offset(lug[0].toDouble(), lug[1].toDouble())),
      );
    }
    turns.sort((a, b) => a.yaw.compareTo(b.yaw));
    return WholeBody._(
      ArtRect.fromJson(j['rest'] as Map<String, dynamic>),
      {
        for (final MapEntry(key: k, value: v) in ((j['layers'] as Map<String, dynamic>?) ?? const {}).entries)
          k: ArtRect.fromJson(v as Map<String, dynamic>),
      },
      turns,
      WholeLayout._fromJson(lay),
    );
  }

  final ArtRect rest;
  final Map<String, ArtRect> layers;
  final List<TurnFrame> turns;
  final WholeLayout layout;

  ArtRect? layer(String name, [String? state]) =>
      layers[state == null ? name : '$name-$state'] ?? layers[name];

  /// The two rendered turns either side of [deg] and how far between.
  (TurnFrame, TurnFrame, double) bracket(double deg) {
    final d = deg.abs().clamp(0.0, turns.last.yaw.toDouble());
    var i = 0;
    while (i + 1 < turns.length && turns[i + 1].yaw <= d) {
      i++;
    }
    final lo = turns[i], hi = turns[math.min(i + 1, turns.length - 1)];
    final f = hi.yaw == lo.yaw ? 0.0 : (d - lo.yaw) / (hi.yaw - lo.yaw);
    return (lo, hi, f);
  }
}

/// Where things are on the face, design dp.
class WholeLayout {
  WholeLayout._(this.frame, this.screenInset, this.label, this.parts);

  factory WholeLayout._fromJson(Map<String, dynamic> j) {
    Rect r(Object? v) {
      final l = (v! as List<dynamic>).cast<num>();
      return Rect.fromLTRB(l[0].toDouble(), l[1].toDouble(), l[2].toDouble(), l[3].toDouble());
    }

    return WholeLayout._(r(j['frame']), (j['screenInset'] as num).toDouble(), r(j['memo'] ?? j['lcd']), {
      for (final MapEntry(key: k, value: v) in (j['parts'] as Map<String, dynamic>).entries)
        k: Offset(((v as List<dynamic>)[0] as num).toDouble(), (v[1] as num).toDouble()),
    });
  }

  /// The viewfinder's frame; the live picture fills it less [screenInset].
  final Rect frame;
  final double screenInset;

  /// Memo holder (film) / LCD (digital).
  final Rect label;
  final Map<String, Offset> parts;

  Rect get screen => frame.deflate(screenInset);
}

/// Design space onto a screen: scaled to its width, and a band taken out of
/// the middle (at [WholeArt.cutY], inside the viewfinder) on phones less
/// tall than the design (added there, stretched, on taller ones).
class DesignFit {
  DesignFit(this.art, Size screen)
    : s = screen.width / art.design.width,
      trim = art.design.height - screen.height / (screen.width / art.design.width);

  final WholeArt art;

  /// Screen dp per design dp.
  final double s;

  /// Design dp taken out at the cut (negative: added).
  final double trim;

  double y(double dy) => (dy <= art.cutY ? dy : dy - trim) * s;
  Offset point(Offset d) => Offset(d.dx * s, y(d.dy));
  Rect rect(Rect d) => Rect.fromLTRB(d.left * s, y(d.top), d.right * s, y(d.bottom));

  /// The screen point the body turns about (the cut, mid-width).
  Offset get pivot => Offset(art.design.width / 2 * s, art.cutY * s);
}

final wholeArtProvider = FutureProvider<WholeArt?>((ref) => WholeArt.load());

/// The whole-body art for [mode] when 3D is on and it's bundled.
final wholeBodyProvider = Provider.family<WholeBody?, AppMode>((ref, mode) {
  final art = ref.watch(wholeArtProvider).value;
  final body = art?.bodies[mode];
  if (body == null) return null; // (settings untouched: tests run without them)
  return ref.watch(globalSettingsProvider.select((s) => s.controls3d)) ? body : null;
});

// ------------------------------------------------------------------ drawing

/// Resolves [providers] to images and keeps each until its replacement has
/// decoded (gapless); [paint] gets what's ready (null where nothing yet).
class ArtImages extends StatefulWidget {
  const ArtImages({super.key, required this.providers, required this.painter, this.size = Size.infinite});

  final List<ImageProvider?> providers;
  final CustomPainter Function(List<ui.Image?> images) painter;
  final Size size;

  @override
  State<ArtImages> createState() => _ArtImagesState();
}

class _Slot {
  ImageStream? stream;
  ImageStreamListener? listener;
  ImageInfo? info;

  void dispose() {
    if (listener != null) stream?.removeListener(listener!);
    info?.dispose();
  }
}

class _ArtImagesState extends State<ArtImages> {
  final _slots = <_Slot>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ArtImages old) {
    super.didUpdateWidget(old);
    _resolve();
  }

  void _resolve() {
    while (_slots.length < widget.providers.length) {
      _slots.add(_Slot());
    }
    final config = createLocalImageConfiguration(context);
    for (var i = 0; i < widget.providers.length; i++) {
      final p = widget.providers[i];
      if (p == null) continue;
      final slot = _slots[i];
      final stream = p.resolve(config);
      if (slot.stream?.key == stream.key) continue;
      if (slot.listener != null) slot.stream?.removeListener(slot.listener!);
      slot.stream = stream;
      slot.listener = ImageStreamListener((info, _) {
        if (!mounted) return info.dispose();
        setState(() {
          slot.info?.dispose();
          slot.info = info;
        });
      });
      final before = slot.info;
      stream.addListener(slot.listener!);
      if (identical(slot.info, before)) WholeArt.lateFrames++;
    }
  }

  @override
  void dispose() {
    for (final s in _slots) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: widget.size,
    painter: widget.painter([
      for (var i = 0; i < widget.providers.length; i++)
        widget.providers[i] == null ? null : _slots.elementAtOrNull(i)?.info?.image,
    ]),
  );
}

final _paint = Paint()..filterQuality = FilterQuality.medium;

/// Draws [img] (art covering design rect [r]) onto the screen through [fit]:
/// the part above the cut as is, the part below moved up by the trim (or a
/// band stretched across the cut on taller phones).
void drawFitted(Canvas c, ui.Image img, Rect r, DesignFit fit, Paint paint) {
  final ky = img.height / r.height;
  final cut = fit.art.cutY;
  Rect src(double y0, double y1) =>
      Rect.fromLTRB(0, (y0 - r.top) * ky, img.width.toDouble(), (y1 - r.top) * ky);
  Rect dst(double y0, double y1) =>
      Rect.fromLTRB(r.left * fit.s, fit.y(y0), r.right * fit.s, y1 <= cut ? y1 * fit.s : fit.y(y1));
  if (r.bottom <= cut || r.top >= cut + math.max(0, fit.trim)) {
    // wholly above the cut, or wholly below the band taken out
    final top = r.top <= cut ? r.top * fit.s : fit.y(r.top);
    final bottom = r.bottom <= cut ? r.bottom * fit.s : fit.y(r.bottom);
    c.drawImageRect(
      img,
      src(r.top, r.bottom),
      Rect.fromLTRB(r.left * fit.s, top, r.right * fit.s, bottom),
      paint,
    );
    return;
  }
  // above the cut
  c.drawImageRect(
    img,
    src(r.top, cut),
    Rect.fromLTRB(r.left * fit.s, r.top * fit.s, r.right * fit.s, cut * fit.s),
    paint,
  );
  if (fit.trim >= 0) {
    final from = math.min(cut + fit.trim, r.bottom);
    c.drawImageRect(img, src(from, r.bottom), dst(from, r.bottom), paint);
  } else {
    // taller phone: a thin band at the cut stretched over the extra height
    final band = 2.0;
    c.drawImageRect(
      img,
      src(cut, cut + band),
      Rect.fromLTRB(r.left * fit.s, cut * fit.s, r.right * fit.s, (cut - fit.trim + band) * fit.s),
      paint,
    );
    c.drawImageRect(img, src(cut + band, r.bottom), dst(cut + band, r.bottom), paint);
  }
}

/// [a] and [b] mixed as (1 - f) a + f b in a layer: exact, so an opaque body
/// stays opaque and its shadows don't double up between turns.
void drawMixed(
  Canvas c,
  Rect bounds,
  double f,
  double opacity,
  void Function(Paint) a,
  void Function(Paint)? b,
) {
  Paint p(double alpha) => Paint()
    ..filterQuality = FilterQuality.medium
    ..color = Color.fromRGBO(0, 0, 0, alpha);
  if (b == null || f <= 0.02) return a(p(opacity));
  if (f >= 0.98) return b(p(opacity));
  c.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
  a(p(1 - f));
  b(p(f)..blendMode = BlendMode.plus);
  c.restore();
}

/// The resting body, face-on, fitted to the screen (moving parts and the
/// live picture go on top).
class WholeRest extends StatelessWidget {
  const WholeRest({super.key, required this.art, required this.body});

  final WholeArt art;
  final WholeBody body;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final fit = DesignFit(art, size);
    return ArtImages(
      providers: [body.rest.image(fit.s * dpr)],
      painter: (imgs) => RestPainter(imgs[0], body.rest.rect, fit),
    );
  }
}

class RestPainter extends CustomPainter {
  RestPainter(this.img, this.rect, this.fit);

  final ui.Image? img;
  final Rect rect;
  final DesignFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final i = img;
    if (i != null) drawFitted(canvas, i, rect, fit, _paint);
  }

  @override
  bool shouldRepaint(RestPainter o) => o.img != img || o.fit.s != fit.s || o.fit.trim != fit.trim;
}

/// One moving part's layer, at its place on the fitted face. Positioned in
/// a Stack the size of the screen. [turn] spins it about [pivot] (design dp),
/// [shift] slides it (design dp).
class WholeLayer extends StatelessWidget {
  const WholeLayer({
    super.key,
    required this.fit,
    required this.layer,
    this.turn = 0,
    this.pivot,
    this.shift = Offset.zero,
    this.opacity = 1,
  });

  final DesignFit fit;
  final ArtRect layer;
  final double turn;
  final Offset? pivot;
  final Offset shift;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final r = fit.rect(layer.rect.shift(shift));
    Widget img = ArtImages(
      providers: [layer.image(fit.s * dpr)],
      size: r.size,
      painter: (imgs) => _LayerPainter(imgs[0], opacity),
    );
    if (turn != 0) {
      final p = pivot ?? layer.rect.center;
      img = Transform.rotate(
        angle: turn,
        alignment: Alignment(
          (p.dx - layer.rect.left) / layer.rect.width * 2 - 1,
          (p.dy - layer.rect.top) / layer.rect.height * 2 - 1,
        ),
        child: img,
      );
    }
    return Positioned.fromRect(
      rect: r,
      child: IgnorePointer(child: img),
    );
  }
}

class _LayerPainter extends CustomPainter {
  _LayerPainter(this.img, this.opacity);

  final ui.Image? img;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final i = img;
    if (i == null) return;
    canvas.drawImageRect(
      i,
      Offset.zero & Size(i.width.toDouble(), i.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
  }

  @override
  bool shouldRepaint(_LayerPainter o) => o.img != img || o.opacity != opacity;
}

/// The body turned [deg] degrees mid-swap: the two nearest rendered turns
/// mixed, with [shutter]'s turned layer over them; fitted like the rest.
class WholeTurn extends StatelessWidget {
  const WholeTurn({super.key, required this.art, required this.body, required this.deg, this.shutter});

  final WholeArt art;
  final WholeBody body;
  final double deg;
  final String? shutter;

  @override
  Widget build(BuildContext context) {
    final fit = DesignFit(art, MediaQuery.sizeOf(context));
    final (lo, hi, f) = body.bracket(deg);
    final mix = f > 0.02 && hi != lo;
    final shLo = shutter == null ? null : lo.shutters[shutter];
    final shHi = shutter == null || !mix ? null : hi.shutters[shutter];
    return ArtImages(
      providers: [
        lo.body.image(WholeArt.turnPx),
        mix ? hi.body.image(WholeArt.turnPx) : null,
        shLo?.image(WholeArt.turnPx),
        shHi?.image(WholeArt.turnPx),
      ],
      painter: (imgs) => _TurnPainter(
        fit: fit,
        lo: imgs[0],
        hi: imgs[1],
        shLo: imgs[2],
        shHi: imgs[3],
        loRect: lo.body.rect,
        hiRect: hi.body.rect,
        shLoRect: shLo?.rect,
        shHiRect: shHi?.rect,
        f: f,
      ),
    );
  }
}

class _TurnPainter extends CustomPainter {
  _TurnPainter({
    required this.fit,
    required this.lo,
    required this.hi,
    required this.shLo,
    required this.shHi,
    required this.loRect,
    required this.hiRect,
    required this.shLoRect,
    required this.shHiRect,
    required this.f,
  });

  final DesignFit fit;
  final ui.Image? lo, hi, shLo, shHi;
  final Rect loRect, hiRect;
  final Rect? shLoRect, shHiRect;
  final double f;

  @override
  void paint(Canvas canvas, Size size) {
    final a = lo, b = hi;
    if (a == null) return;
    final bounds = fit.rect(loRect.expandToInclude(hiRect)).inflate(2);
    void frame(ui.Image body, Rect r, ui.Image? sh, Rect? sr, Paint p) {
      drawFitted(canvas, body, r, fit, p);
      if (sh != null && sr != null) drawFitted(canvas, sh, sr, fit, p);
    }

    drawMixed(
      canvas,
      bounds,
      f,
      1,
      (p) => frame(a, loRect, shLo, shLoRect, p),
      b == null ? null : (p) => frame(b, hiRect, shHi, shHiRect, p),
    );
  }

  @override
  bool shouldRepaint(_TurnPainter o) =>
      o.lo != lo || o.hi != hi || o.shLo != shLo || o.shHi != shHi || o.f != f || o.fit.trim != fit.trim;
}
