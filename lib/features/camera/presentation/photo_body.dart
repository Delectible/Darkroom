import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cameras/domain/camera_spec.dart';
import '../../settings/application/settings_controllers.dart';
import 'body_swap.dart' show BodyYaw;

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
  BodyArt._(this.px, this._parts);

  static const root = 'assets/body';

  /// Performance mode: parts stay face-on while the body turns (no turned
  /// frames decoded or drawn; the swap moves the body as one picture).
  static bool faceOnly = false;

  /// Pixels per dp the sprites were saved at.
  final double px;
  final Map<String, Map<String, BodyPart>> _parts;

  BodyPart? part(AppMode mode, String name) => _parts[mode.name]?[name];

  bool has(AppMode mode) => _parts[mode.name]?.isNotEmpty ?? false;

  /// Decodes every sprite ahead of time (face-on first, then the turned
  /// frames unless [faceOnly]), so nothing pops in or janks mid-swap.
  Future<void> precache(BuildContext context) async {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    // Big enough for every frame of both bodies (default is 100 MB).
    PaintingBinding.instance.imageCache.maximumSizeBytes = 260 << 20;
    final face = <ImageProvider>[], turned = <ImageProvider>[];
    for (final parts in _parts.values) {
      for (final p in parts.values) {
        final panel = p.name == 'panel' || p.name.startsWith('plate');
        final w = panel ? width : p.canvas.width;
        for (final st in p.states.isEmpty ? <String?>[null] : p.states) {
          face.add(bodyImage(p.asset(st, 0), w * dpr));
        }
        for (final y in p.yaws.where((y) => y != 0)) {
          turned.add(bodyImage(p.asset(null, y), w * dpr * 0.6));
        }
      }
    }
    for (final i in face) {
      if (!context.mounted) return;
      await precacheImage(i, context);
    }
    if (faceOnly) return;
    for (final i in turned) {
      if (!context.mounted) return;
      await precacheImage(i, context);
    }
  }

  static Future<BodyArt?> load() async {
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
  });

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

final bodyArtProvider = FutureProvider<BodyArt?>((ref) => BodyArt.load());

/// The art for [mode] when the photoreal bodies are switched on (setting
/// "3D controls") and bundled; null draws the classic bodies.
final photoBodyProvider = Provider.family<BodyArt?, AppMode>((ref, mode) {
  final art = ref.watch(bodyArtProvider).value;
  if (art == null || !art.has(mode)) return null; // (settings untouched: tests run without them)
  return ref.watch(globalSettingsProvider.select((s) => s.controls3d)) ? art : null;
});

/// Decoded at the size drawn: face-on at full sharpness, turned frames
/// (only seen in motion) at 60 %.
ImageProvider bodyImage(String asset, double widthPx) =>
    ResizeImage(AssetImage(asset), width: widthPx.round(), policy: ResizeImagePolicy.fit);

/// One part's sprite, centred on this widget and drawn at its canvas size
/// (it overflows the widget's box by its margins). Follows the body's turn
/// while swapping, cross-fading between the rendered turns and stretched
/// back by 1 / cos(turn) (the body's own transform foreshortens it again).
class BodySprite extends StatelessWidget {
  const BodySprite(this.part, {super.key, this.state, this.opacity = 1});

  final BodyPart part;
  final String? state;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final yaw = BodyArt.faceOnly ? 0.0 : BodyYaw.of(context);
    final deg = yaw * 180 / math.pi;
    final (lo, hi, f) = part.bracket(deg);
    // Alpha goes into the image paint (an Opacity would cost a layer each).
    Widget frame(int y, double o) => Image(
      image: bodyImage(part.asset(state, y), part.canvas.width * dpr * (y == 0 ? 1 : 0.6)),
      width: part.canvas.width,
      height: part.canvas.height,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      color: o < 1 ? Color.fromRGBO(255, 255, 255, o) : null,
      colorBlendMode: BlendMode.modulate,
    );
    Widget img = Stack(children: [frame(lo, opacity), if (f > 0.02) frame(hi, opacity * f)]);
    if (yaw != 0) {
      img = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(1 / math.cos(yaw).clamp(0.5, 1.0), 1, 1),
        child: img,
      );
    }
    return OverflowBox(
      minWidth: part.canvas.width,
      maxWidth: part.canvas.width,
      minHeight: part.canvas.height,
      maxHeight: part.canvas.height,
      child: IgnorePointer(child: img),
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
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final yaw = BodyArt.faceOnly ? 0.0 : BodyYaw.of(context);
    final (lo, hi, f) = part.bracket(yaw * 180 / math.pi);
    final box = part.box ?? part.canvas;
    final mx = (part.canvas.width - box.width) / 2, my = (part.canvas.height - box.height) / 2;
    final sx = part.sliceX ?? part.slice ?? 0, sy = part.sliceX != null ? 0.0 : part.slice ?? 0;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth + 2 * mx, h = c.maxHeight + 2 * my;
        Widget frame(int y, double o) {
          final scale = y == 0 ? 1.0 : 0.6;
          final k = dpr * scale; // decoded px per dp
          return Image(
            image: bodyImage(part.asset(null, y), part.canvas.width * k),
            width: w,
            height: h,
            centerSlice: Rect.fromLTRB(
              sx * k,
              sy * k,
              (part.canvas.width - sx) * k,
              (part.canvas.height - sy) * k,
            ),
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            color: o < 1 ? Color.fromRGBO(255, 255, 255, o) : null,
            colorBlendMode: BlendMode.modulate,
          );
        }

        return OverflowBox(
          minWidth: w,
          maxWidth: w,
          minHeight: h,
          maxHeight: h,
          child: IgnorePointer(child: Stack(children: [frame(lo, 1), if (f > 0.02) frame(hi, f)])),
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
    final yaw = BodyArt.faceOnly ? 0.0 : BodyYaw.of(context);
    final deg = yaw * 180 / math.pi;
    final panel = art.part(mode, 'panel')!;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        final k = w / panel.canvas.width; // panels are drawn to the screen's width
        Widget layer(BodyPart p, Alignment align, double height) {
          final (lo, hi, f) = p.bracket(deg);
          Widget img(int y, double o) => Image(
            image: bodyImage(p.asset(null, y), w * dpr * (y == 0 ? 1 : 0.6)),
            width: w,
            height: p.canvas.height * k,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            color: o < 1 ? Color.fromRGBO(255, 255, 255, o) : null,
            colorBlendMode: BlendMode.modulate,
          );
          return SizedBox(
            width: w,
            height: height,
            child: ClipRect(
              child: OverflowBox(
                alignment: align,
                maxHeight: double.infinity,
                child: Stack(children: [img(lo, 1), if (f > 0.02) img(hi, f)]),
              ),
            ),
          );
        }

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

/// A rendered key (rubber pill, chrome button): shows its pressed render
/// while held and fires [onTap] on release; [child] (a printed label) sits
/// on the key and sinks with it.
class PhotoKey extends StatefulWidget {
  const PhotoKey({super.key, required this.part, required this.onTap, this.child, this.enabled = true});

  final BodyPart part;
  final VoidCallback onTap;
  final Widget? child;
  final bool enabled;

  @override
  State<PhotoKey> createState() => _PhotoKeyState();
}

class _PhotoKeyState extends State<PhotoKey> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _down = false);
              widget.onTap();
            }
          : null,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.55,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            BodySprite(widget.part, state: _down ? 'down' : 'up'),
            if (label != null) Transform.translate(offset: Offset(0, _down ? 0.6 : -0.4), child: label),
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
