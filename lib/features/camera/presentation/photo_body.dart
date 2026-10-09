import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sfx.dart';
import '../../../core/device/haptics.dart';
import '../../cameras/domain/camera_spec.dart';
import '../../settings/application/settings_controllers.dart';
import 'art_cache.dart';
import 'body_swap.dart' show BodyYaw;
import 'whole_body.dart';

/// The photoreal camera bodies: every part path-traced on its own
/// (tool/render/items/body.js, rendered by tool/render/body/render_queue.py)
/// and drawn here into the app's normal, responsive layout. All parts share
/// one studio light and a straight-down view, so they sit together like one
/// object on any screen size. Parts that stand proud of the body were also
/// rendered turned 0..48 degrees about the body's long axis, and follow the
/// body's turn while it is swapped ([BodyYaw]).
///
/// Assets: `assets/body/manifest.json` and `assets/body/<mode>/<part>[-<state>]-a<deg>.webp`.
class BodyArt {
  BodyArt._(this.px, this._parts, {this.whole});

  /// Since 1.7 the bodies are live 3D models ([WholeArt]): the controls'
  /// parts draw nothing themselves; the moving ones move their piece of the
  /// model ([LivePart]), the rest are just part of it.
  final WholeArt? whole;

  static const _wholeParts = {
    AppMode.film: [
      'flash', 'flashtab', 'aspect', 'aspecttop', 'lens', 'lensdot', 'menu', 'memo', 'print', 'tray', //
      'shutter', 'release', 'lever', 'run', 'frame',
    ],
    AppMode.digital: [
      'pill', 'pillwide', 'pillsmall', 'lens', 'lensdot', 'lcd', 'review', 'rocker', 'tray', 'shutter', //
      'rec', 'frame',
    ],
  };

  /// The layout part each control part sits on (its rest place).
  static String anchorOf(String part) => _layerAt[part] ?? part;

  static const _layerAt = {
    'aspecttop': 'aspect',
    'release': 'shutter',
    'lever': 'shutter',
    'run': 'shutter',
    'rec': 'shutter',
  };

  /// States of the parts that have them (pressed keys, the rocker).
  static const _wholeStates = {
    'menu': ['up', 'down'],
    'pill': ['up', 'down'],
    'pillwide': ['up', 'down'],
    'pillsmall': ['up', 'down'], //
    'shutter': ['up', 'down'], 'release': ['up', 'down'], 'run': ['up', 'down'], 'rec': ['up', 'down'],
    'rocker': ['mid', 'w', 't'],
  };

  factory BodyArt.fromWhole(WholeArt w) {
    final parts = <String, Map<String, BodyPart>>{
      for (final mode in w.bodies.keys)
        mode.name: {
          for (final name in _wholeParts[mode]!)
            name: BodyPart.whole(mode.name, name, _wholeStates[name] ?? const []),
        },
    };
    return BodyArt._(1, parts, whole: w);
  }

  static const root = 'assets/body';

  /// Performance mode: parts stay face-on while the body turns (no turned
  /// frames decoded or drawn; the swap moves the body as one picture).
  static bool faceOnly = false;

  /// Frames that weren't decoded yet when drawn (they pop in a frame late);
  /// tests check a swap never needs one.
  static int lateFrames = 0;

  /// Pixels per dp the sprites were saved at.
  final double px;
  final Map<String, Map<String, BodyPart>> _parts;

  BodyPart? part(AppMode mode, String name) => _parts[mode.name]?[name];

  bool has(AppMode mode) =>
      whole?.bodies.containsKey(mode) ?? (_parts[mode.name]?.containsKey('panel') ?? false);

  /// Decodes every sprite ahead of time and keeps it ([ArtCache]), so
  /// nothing pops in or janks mid-swap, ever.
  Future<void> precache(BuildContext context) => warm(
    MediaQuery.devicePixelRatioOf(context),
    MediaQuery.sizeOf(context).width,
    config: createLocalImageConfiguration(context),
  );

  /// [precache] without a context (at launch, behind the splash screen):
  /// the face-on sprites, then the turned frames unless [faceOnly] or
  /// [turned] is false.
  Future<void> warm(double dpr, double width, {ImageConfiguration? config, bool turned = true}) async {
    if (whole != null) return; // the models load with the art
    final cfg = config ?? ImageConfiguration(devicePixelRatio: dpr);
    final face = <ImageProvider>[], frames = <ImageProvider>[];
    for (final parts in _parts.values) {
      for (final p in parts.values) {
        final panel = p.name == 'panel' || p.name.startsWith('plate');
        final w = panel ? width : p.canvas.width;
        for (final st in p.states.isEmpty ? <String?>[null] : p.states) {
          face.add(bodyImage(p.asset(st, 0), w * dpr));
        }
        for (final y in p.yaws.where((y) => y != 0)) {
          frames.add(bodyImage(p.asset(null, y), w * dpr * 0.6));
        }
      }
    }
    await ArtCache.pinAll(face, cfg);
    if (faceOnly || !turned) return;
    await ArtCache.pinAll(frames, cfg);
  }

  static Future<BodyArt?> load() async {
    final w = await WholeArt.load();
    if (w != null) return BodyArt.fromWhole(w);
    try {
      final json = jsonDecode(await rootBundle.loadString('$root/manifest.json')) as Map<String, dynamic>;
      final parts = <String, Map<String, BodyPart>>{};
      for (final MapEntry(key: mode, value: ps) in (json['parts'] as Map<String, dynamic>).entries) {
        parts[mode] = {
          for (final MapEntry(key: name, value: p) in (ps as Map<String, dynamic>).entries)
            name: BodyPart.fromJson(mode, name, p as Map<String, dynamic>, (json['px'] as num).toDouble()),
        };
      }
      return BodyArt._((json['px'] as num).toDouble(), parts);
    } catch (_) {
      return null; // no art bundled: the classic drawn bodies
    }
  }
}

class BodyPart {
  BodyPart._({
    required this.mode,
    required this.name,
    required this.canvas,
    required this.yaws,
    required this.states,
    required this.yaw0States,
    required this.px,
    this.slice,
    this.sliceX,
    this.box,
    this.edge = 0,
  }) : layers = null;

  BodyPart.whole(this.mode, this.name, this.states)
    : layers = const {},
      canvas = Size.zero,
      yaws = const [0],
      yaw0States = const [],
      px = 1,
      slice = null,
      sliceX = null,
      box = null,
      edge = 0;

  factory BodyPart.fromJson(String mode, String name, Map<String, dynamic> j, double px) {
    List<T> list<T>(Object? v) => (v as List<dynamic>? ?? const []).cast<T>();
    final c = list<num>(j['canvas']);
    final b = j['box'] == null ? null : list<num>(j['box']);
    return BodyPart._(
      mode: mode,
      name: name,
      canvas: Size(c[0].toDouble(), c[1].toDouble()),
      yaws: list<num>(j['yaws']).map((e) => e.toInt()).toList()..sort(),
      states: list<String>(j['states']),
      yaw0States: list<String>(j['stateYaw0']),
      px: (j['px'] as num?)?.toDouble() ?? px,
      slice: (j['slice'] as num?)?.toDouble(),
      sliceX: (j['sliceX'] as num?)?.toDouble(),
      box: b == null ? null : Size(b[0].toDouble(), b[1].toDouble()),
      edge: (j['edge'] as num?)?.toDouble() ?? 0,
    );
  }

  final String mode;
  final String name;

  /// Non-null for the live 3D bodies: the part is the model's (it draws
  /// nothing here; see [LivePart]).
  final Map<String, Object>? layers;

  /// The sprite's whole canvas in dp: the part's box plus margins for its
  /// shadow and for parallax when turned.
  final Size canvas;
  final List<int> yaws;
  final List<String> states;

  /// States only rendered face-on (a key held down: never mid-swap).
  final List<String> yaw0States;
  final double px;

  /// 9-slice (all sides) / 3-slice (left and right) insets in dp, for parts
  /// the app stretches (frames, the memo clip).
  final double? slice;
  final double? sliceX;

  /// The part's own outline inside [canvas] (stretched parts).
  final Size? box;

  /// Plates: how far the canvas runs past the plate's edge (its shadow).
  final double edge;

  String asset(String? state, int yaw) {
    final s = state ?? (states.isEmpty ? null : states.first);
    final st = s != null && yaw != 0 && yaw0States.contains(s) ? states.first : s;
    return '${BodyArt.root}/$mode/$name${st == null ? '' : '-$st'}-a$yaw.webp';
  }

  /// The two rendered turns either side of [deg] and how far between.
  (int, int, double) bracket(double deg) {
    final d = deg.abs().clamp(0.0, yaws.last.toDouble());
    var lo = yaws.first;
    for (final y in yaws) {
      if (y <= d) lo = y;
    }
    final i = yaws.indexOf(lo);
    final hi = i + 1 < yaws.length ? yaws[i + 1] : lo;
    final f = hi == lo ? 0.0 : (d - lo) / (hi - lo);
    return (lo, hi, f);
  }
}

/// The controls' art: the whole-body renders' moving parts (in step with
/// [wholeArtProvider], so the face and its controls arrive together).
final bodyArtProvider = Provider<BodyArt?>((ref) {
  final w = ref.watch(wholeArtProvider).value;
  return w == null ? null : BodyArt.fromWhole(w);
});

/// The art for [mode] when the photoreal bodies are switched on (setting
/// "3D controls") and bundled; null draws the classic bodies.
final photoBodyProvider = Provider.family<BodyArt?, AppMode>((ref, mode) {
  final art = ref.watch(bodyArtProvider);
  if (art == null || !art.has(mode)) return null; // (settings untouched: tests run without them)
  return ref.watch(globalSettingsProvider.select((s) => s.controls3d)) ? art : null;
});

/// Decoded at the size drawn: face-on at full sharpness, turned frames
/// (only seen in motion) at 60 %.
ImageProvider bodyImage(String asset, double widthPx) =>
    ResizeImage(AssetImage(asset), width: widthPx.round(), policy: ResizeImagePolicy.fit);

/// One part's sprite, centred on this widget and drawn at its canvas size
/// (it overflows the widget's box by its margins). Follows the body's turn
/// while swapping (see [_Frames]).
class BodySprite extends StatelessWidget {
  const BodySprite(this.part, {super.key, this.state, this.opacity = 1});

  final BodyPart part;
  final String? state;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (part.layers != null) {
      // The model's piece: moved where this sprite would be.
      return Center(
        child: LivePart(name: part.name, state: state ?? part.states.firstOrNull),
      );
    }
    return OverflowBox(
      minWidth: part.canvas.width,
      maxWidth: part.canvas.width,
      minHeight: part.canvas.height,
      maxHeight: part.canvas.height,
      child: IgnorePointer(
        child: _Frames.turned(
          context,
          part,
          state: state,
          decodeWidth: (y) => part.canvas.width * dpr * (y == 0 ? 1 : 0.6),
          opacity: opacity,
        ),
      ),
    );
  }
}

/// A stretched part (viewfinder frame, LCD bezel: 9-slice; memo clip:
/// 3-slice) drawn round this widget's box: the part's [BodyPart.box] maps
/// onto the box, its margins spill outside.
class BodySlice extends StatelessWidget {
  const BodySlice(this.part, {super.key});

  final BodyPart part;

  @override
  Widget build(BuildContext context) {
    if (part.layers != null) return const SizedBox.shrink(); // baked into the whole body
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final box = part.box ?? part.canvas;
    final mx = (part.canvas.width - box.width) / 2, my = (part.canvas.height - box.height) / 2;
    final sx = part.sliceX ?? part.slice ?? 0, sy = part.sliceX != null ? 0.0 : part.slice ?? 0;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth + 2 * mx, h = c.maxHeight + 2 * my;
        return OverflowBox(
          minWidth: w,
          maxWidth: w,
          minHeight: h,
          maxHeight: h,
          child: IgnorePointer(
            child: _Frames.turned(
              context,
              part,
              decodeWidth: (y) => part.canvas.width * dpr * (y == 0 ? 1 : 0.6),
              slice: Size(sx, sy),
            ),
          ),
        );
      },
    );
  }
}

/// The body's surface: leatherette between chrome plates (film) or one
/// brushed aluminium face (digital), cropped to the screen. [top] / [bottom]
/// are how far the plates reach down / up from the screen edges.
class BodyBackdrop extends StatelessWidget {
  const BodyBackdrop({
    super.key,
    required this.art,
    required this.mode,
    required this.top,
    required this.bottom,
  });

  final BodyArt art;
  final AppMode mode;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final panel = art.part(mode, 'panel')!;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        final k = w / panel.canvas.width; // panels are drawn to the screen's width
        Widget layer(BodyPart p, Alignment align, double height) => SizedBox(
          width: w,
          height: height,
          child: ClipRect(
            child: OverflowBox(
              alignment: align,
              maxHeight: double.infinity,
              child: SizedBox(
                width: w,
                height: p.canvas.height * k,
                child: _Frames.turned(context, p, decodeWidth: (y) => w * dpr * (y == 0 ? 1 : 0.6)),
              ),
            ),
          ),
        );

        final plateTop = art.part(mode, 'plate-top'), plateBot = art.part(mode, 'plate-bot');
        return Stack(
          children: [
            Positioned.fill(child: layer(panel, Alignment.topCenter, h)),
            if (plateTop != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: layer(plateTop, Alignment.bottomCenter, top + plateTop.edge * k),
              ),
            if (plateBot != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: layer(plateBot, Alignment.topCenter, bottom + plateBot.edge * k),
              ),
          ],
        );
      },
    );
  }
}

/// Draws one part at the body's current turn ([BodyYaw]) into this widget's
/// size, from the two rendered turns either side of it.
///
/// Each render shows the part foreshortened by its own turn (a flat panel
/// fills only cos(turn) of the canvas, centred): it's cropped to that and
/// stretched back to face-on width, and the body's own transform
/// foreshortens it again, so the edges always meet the body's. The two
/// frames are mixed in a layer as (1 - f) A + f B (additive), an exact
/// blend: an opaque part stays opaque and its shadow doesn't double up and
/// snap back at each rendered turn.
class _Frames extends StatefulWidget {
  const _Frames({
    required this.lo,
    required this.hi,
    required this.loDeg,
    required this.hiDeg,
    required this.f,
    required this.canvas,
    this.slice,
    this.opacity = 1,
  });

  factory _Frames.turned(
    BuildContext context,
    BodyPart part, {
    String? state,
    required double Function(int yaw) decodeWidth,
    Size? slice,
    double opacity = 1,
  }) {
    final yaw = BodyArt.faceOnly ? 0.0 : BodyYaw.of(context);
    final (lo, hi, f) = part.bracket(yaw * 180 / math.pi);
    return _Frames(
      lo: bodyImage(part.asset(state, lo), decodeWidth(lo)),
      hi: f > 0.02 ? bodyImage(part.asset(state, hi), decodeWidth(hi)) : null,
      loDeg: lo.toDouble(),
      hiDeg: hi.toDouble(),
      f: f,
      canvas: part.canvas,
      slice: slice,
      opacity: opacity,
    );
  }

  final ImageProvider lo;
  final ImageProvider? hi;
  final double loDeg;
  final double hiDeg;
  final double f;
  final Size canvas;

  /// 9-slice insets in dp from the canvas edges (x, y); null: plain.
  final Size? slice;
  final double opacity;

  @override
  State<_Frames> createState() => _FramesState();
}

/// One frame's image, kept until its replacement has decoded (gapless).
class _Slot {
  ImageStream? stream;
  ImageStreamListener? listener;
  ImageInfo? info;
  double deg = 0;

  void dispose() {
    if (listener != null) stream?.removeListener(listener!);
    info?.dispose();
  }
}

class _FramesState extends State<_Frames> {
  final _lo = _Slot(), _hi = _Slot();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_Frames old) {
    super.didUpdateWidget(old);
    _resolve();
  }

  void _resolve() {
    _watch(_lo, widget.lo, widget.loDeg);
    final hi = widget.hi;
    if (hi != null) _watch(_hi, hi, widget.hiDeg);
  }

  void _watch(_Slot slot, ImageProvider provider, double deg) {
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (slot.stream?.key == stream.key) return;
    if (slot.listener != null) slot.stream?.removeListener(slot.listener!);
    slot.stream = stream;
    slot.listener = ImageStreamListener((info, _) {
      if (!mounted) return info.dispose();
      setState(() {
        slot.info?.dispose();
        slot.info = info;
        slot.deg = deg;
      });
    });
    final before = slot.info;
    stream.addListener(slot.listener!);
    if (identical(slot.info, before)) BodyArt.lateFrames++; // not decoded yet
  }

  @override
  void dispose() {
    _lo.dispose();
    _hi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final mix = w.hi != null && _hi.info != null && _hi.deg == w.hiDeg && _lo.deg == w.loDeg;
    return CustomPaint(
      size: Size.infinite,
      painter: _FramesPainter(
        lo: _lo.info?.image,
        loDeg: _lo.deg,
        hi: mix ? _hi.info?.image : null,
        hiDeg: _hi.deg,
        f: mix ? w.f : 0,
        canvas: w.canvas,
        slice: w.slice,
        opacity: w.opacity,
      ),
    );
  }
}

class _FramesPainter extends CustomPainter {
  _FramesPainter({
    required this.lo,
    required this.loDeg,
    required this.hi,
    required this.hiDeg,
    required this.f,
    required this.canvas,
    required this.slice,
    required this.opacity,
  });

  final ui.Image? lo;
  final double loDeg;
  final ui.Image? hi;
  final double hiDeg;
  final double f;
  final Size canvas;
  final Size? slice;
  final double opacity;

  void _frame(Canvas c, ui.Image img, double deg, Size size, Paint paint) {
    final cos = math.cos(deg * math.pi / 180);
    final kx = img.width / canvas.width, ky = img.height / canvas.height;
    final g = canvas.width * (1 - cos) / 2; // empty canvas either side of the turned part
    final s = slice;
    if (s == null) {
      c.drawImageRect(
        img,
        Rect.fromLTRB(g * kx, 0, (canvas.width - g) * kx, img.height.toDouble()),
        Offset.zero & size,
        paint,
      );
      return;
    }
    final sx = s.width, sy = s.height;
    final xs = [g, g + sx * cos, canvas.width - g - sx * cos, canvas.width - g];
    final ys = [0.0, sy, canvas.height - sy, canvas.height];
    final dx = [0.0, sx, size.width - sx, size.width];
    final dy = [0.0, sy, size.height - sy, size.height];
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        if (xs[i + 1] <= xs[i] || ys[j + 1] <= ys[j] || dx[i + 1] <= dx[i] || dy[j + 1] <= dy[j]) continue;
        c.drawImageRect(
          img,
          Rect.fromLTRB(xs[i] * kx, ys[j] * ky, xs[i + 1] * kx, ys[j + 1] * ky),
          Rect.fromLTRB(dx[i], dy[j], dx[i + 1], dy[j + 1]),
          paint,
        );
      }
    }
  }

  @override
  void paint(Canvas c, Size size) {
    final a = lo, b = hi;
    if (a == null) return;
    Paint paint(double alpha) => Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, alpha);
    if (b == null || f <= 0.02) {
      _frame(c, a, loDeg, size, paint(opacity));
      return;
    }
    if (f >= 0.98) {
      _frame(c, b, hiDeg, size, paint(opacity));
      return;
    }
    c.saveLayer(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    _frame(c, a, loDeg, size, paint(1 - f));
    _frame(c, b, hiDeg, size, paint(f)..blendMode = BlendMode.plus);
    c.restore();
  }

  @override
  bool shouldRepaint(_FramesPainter o) =>
      o.lo != lo ||
      o.hi != hi ||
      o.f != f ||
      o.loDeg != loDeg ||
      o.hiDeg != hiDeg ||
      o.opacity != opacity ||
      o.slice != slice ||
      o.canvas != canvas;
}

/// Press feedback for the body's keys and dials. The body also listens for
/// drags (the toss), so a quick tap is only recognised as the finger lifts:
/// the key goes down on contact instead, and stays down long enough to be
/// seen ([minDown]) however short the tap. A confirmed tap clicks (sound +
/// haptic) and calls [onTap].
class PressFeedback extends StatefulWidget {
  const PressFeedback({
    super.key,
    required this.onTap,
    required this.builder,
    this.enabled = true,
    this.click = true,
  });

  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool down) builder;
  final bool enabled;

  /// Plays the key click (off for parts that make their own sound).
  final bool click;

  static const minDown = Duration(milliseconds: 110);

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool _down = false;
  DateTime _since = DateTime(0);
  Timer? _up;

  bool get _live => widget.enabled && widget.onTap != null;

  void _press() {
    if (!_live) return;
    _up?.cancel();
    _since = DateTime.now();
    if (!_down) setState(() => _down = true);
  }

  void _release() {
    if (!_down) return;
    final left = PressFeedback.minDown - DateTime.now().difference(_since);
    _up?.cancel();
    if (left <= Duration.zero) {
      setState(() => _down = false);
    } else {
      _up = Timer(left, () {
        if (mounted) setState(() => _down = false);
      });
    }
  }

  @override
  void dispose() {
    _up?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _press(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapCancel: _release,
        onTap: _live
            ? () {
                if (widget.click) {
                  Sfx.keyDown.play();
                  unawaited(Haptics.selectionClick());
                }
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.95 : 1,
          duration: const Duration(milliseconds: 70),
          curve: Curves.easeOut,
          child: widget.builder(context, _down),
        ),
      ),
    );
  }
}

/// A rendered key (rubber pill, chrome button): shows its pressed render
/// while held and fires [onTap] on release; [child] (a printed label) sits
/// on the key and sinks with it.
class PhotoKey extends StatelessWidget {
  const PhotoKey({super.key, required this.part, required this.onTap, this.child, this.enabled = true});

  final BodyPart part;
  final VoidCallback onTap;
  final Widget? child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final label = child;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: PressFeedback(
        enabled: enabled,
        onTap: onTap,
        builder: (context, down) => Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            BodySprite(part, state: down ? 'down' : 'up'),
            if (label != null) Transform.translate(offset: Offset(0, down ? 0.8 : -0.4), child: label),
          ],
        ),
      ),
    );
  }
}

/// Printed on a rendered key: light grey ink on the rubber keys, engraved
/// black on metal.
TextStyle photoLabel({required bool onMetal}) => TextStyle(
  color: onMetal ? const Color(0xFF151515) : const Color(0xFFE4E6E9),
  fontSize: 11,
  fontWeight: FontWeight.w800,
  letterSpacing: 0.6,
);

/// Screen dp per design dp for the 3D face.
class WholeScale extends InheritedWidget {
  const WholeScale({super.key, required this.scale, required super.child});

  final double scale;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WholeScale>()?.scale ?? 1;

  @override
  bool updateShouldNotify(WholeScale old) => old.scale != scale;
}
