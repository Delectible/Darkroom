import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/sfx.dart';
import '../../../../core/diagnostics/perf_recorder.dart';
import '../../../cameras/domain/camera_spec.dart';
import '../../application/camera_ui_state.dart';
import '../../application/capture_controller.dart';
import '../body_swap.dart' show BodyYaw;
import '../photo_body.dart';
import '../../../../core/device/haptics.dart';
import '../../../settings/application/settings_controllers.dart';

/// Bumped every time the shutter fires (on-screen button or volume key), so
/// the button can play its stroke and sound either way.
class ShutterPulse extends Notifier<int> {
  @override
  int build() => 0;

  void fire() => state++;
}

final shutterPulseProvider = NotifierProvider<ShutterPulse, int>(ShutterPulse.new);

/// Fires the shutter: the button's stroke and sound, then the capture.
void pressShutter(WidgetRef ref) {
  PerfRecorder.mark('shutter');
  ref.read(shutterPulseProvider.notifier).fire();
  unawaited(ref.read(captureControllerProvider.notifier).shutter());
}

enum _Kind { digital, film, run }

/// The body's release: a compact's square shutter key (digital), a chrome
/// release in the hub of a film-advance lever that swings on every frame
/// (film), or a red cine RUN button in a lock collar (Super 8). Switching
/// bodies swaps them with a little pop.
class ShutterButton extends ConsumerStatefulWidget {
  const ShutterButton({super.key});

  @override
  ConsumerState<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends ConsumerState<ShutterButton> with SingleTickerProviderStateMixin {
  bool _down = false;

  /// One stroke of the mechanism (lever swing, key travel), 0..1.
  late final AnimationController _stroke = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void initState() {
    super.initState();
    for (final s in [Sfx.shutterDigital, Sfx.shutterFilm, Sfx.shutterRun]) {
      unawaited(s.preload());
    }
  }

  /// Sprite sets already decoded (per kind).
  final _cached = <String>{};

  /// Every frame of the body's shutter decoded up front: presses and swaps
  /// never wait on one.
  void _precache(String kind, double span) {
    if (!_cached.add(kind)) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    for (final name in _SpriteShutter.framesOf(kind)) {
      unawaited(precacheImage(_SpriteShutter.provider(name, span, dpr), context));
    }
  }

  @override
  void dispose() {
    _stroke.dispose();
    super.dispose();
  }

  _Kind _kind(CameraSpec spec) {
    if (spec.mode == AppMode.film) return spec.recordsVideo ? _Kind.run : _Kind.film;
    return _Kind.digital;
  }

  void _fired() {
    final kind = _kind(ref.read(activeSpecProvider));
    switch (kind) {
      case _Kind.digital:
        Sfx.shutterDigital.play();
        unawaited(Haptics.lightImpact());
      case _Kind.film:
        Sfx.shutterFilm.play();
        unawaited(Haptics.mediumImpact());
      case _Kind.run:
        Sfx.shutterRun.play();
        unawaited(Haptics.mediumImpact());
    }
    _stroke.duration = Duration(milliseconds: kind == _Kind.film ? 650 : 220);
    unawaited(_stroke.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(shutterPulseProvider, (_, _) => _fired());
    final spec = ref.watch(activeSpecProvider);
    final recording = ref.watch(captureControllerProvider).isRecording;
    final kind = _kind(spec);
    final video = spec.recordsVideo;
    final turn = ref.watch(globalSettingsProvider.select((s) => s.controls3d));
    final art = ref.watch(photoBodyProvider(spec.mode));
    switch (kind) {
      case _Kind.digital:
        _precache(video ? 'digitalrec' : 'digital', 96);
      case _Kind.film:
        _precache('film', 138);
      case _Kind.run:
        _precache('run', 108);
    }

    final Widget face = AnimatedBuilder(
      key: ValueKey(kind),
      animation: _stroke,
      builder: (context, _) {
        final t = _stroke.isAnimating ? _stroke.value : 0.0;
        return switch (kind) {
          _Kind.digital => _SpriteShutter(
            kind: video ? 'digitalrec' : 'digital',
            box: const Size(92, 78),
            art: art,
            turns: turn,
            span: 96,
            pressed: _down || (t > 0 && t < 0.6),
            lamp: recording ? const _Lamp(Offset.zero, 0.09, Color(0xFFFF3B30)) : null,
          ),
          _Kind.film => _SpriteShutter(
            kind: 'film',
            box: const Size(108, 86),
            art: art,
            turns: turn,
            span: 138,
            hub: const Offset(0.6, 0.52),
            pressed: _down,
            lever: _leverAngle(t),
          ),
          _Kind.run => _SpriteShutter(
            kind: 'run',
            box: const Size(86, 86),
            art: art,
            turns: turn,
            span: 108,
            pressed: _down || recording,
            lamp: recording ? const _Lamp(Offset(0.36, -0.36), 0.05, Color(0xFFFF453A)) : null,
          ),
        };
      },
    );

    return Semantics(
      button: true,
      label: video ? (recording ? 'Stop recording' : 'Start recording') : 'Take photo',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) {
          setState(() => _down = false);
          pressShutter(ref);
        },
        child: SizedBox(
          width: 104,
          height: 86,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(a), child: child),
              ),
              child: face,
            ),
          ),
        ),
      ),
    );
  }
}

/// The advance lever's turn (radians, clockwise from parked) during a
/// stroke [t]: swings out, then springs home.
double _leverAngle(double t) {
  final swing = t <= 0
      ? 0.0
      : t < 0.45
      ? Curves.easeOut.transform(t / 0.45)
      : 1 - Curves.easeInOutBack.transform(((t - 0.45) / 0.55).clamp(0.0, 1.0));
  return 0.18 + swing * 0.95;
}

/// A glowing lamp over the sprite: [at] relative to the hub in sprite
/// spans, [radius] in spans.
class _Lamp {
  const _Lamp(this.at, this.radius, this.color);

  final Offset at;
  final double radius;
  final Color color;
}

/// A shutter drawn from path-traced turntable frames
/// (tool/render/items/shutter.js): the whole button seen with the body
/// turned -48..48 degrees in 12 degree steps. While the body tips during a
/// swap the frame for its angle is shown (neighbours cross-fade), so the
/// button turns as a solid object. The frames already show the button
/// foreshortened, and the body's transform squeezes it again, so the
/// sprite is stretched back by 1/cos(yaw).
///
/// Film's advance-lever stroke (the body is still then) uses the separate
/// base / lever / cap layers, so the lever can swing.
class _SpriteShutter extends StatelessWidget {
  const _SpriteShutter({
    required this.kind,
    required this.box,
    required this.span,
    required this.pressed,
    this.hub = const Offset(0.5, 0.5),
    this.turns = true,
    this.art,
    this.lever,
    this.lamp,
  });

  /// film | run | digital | digitalrec
  final String kind;

  /// Layout size of the button.
  final Size box;

  /// Size of the (square) sprites on screen.
  final double span;

  /// Where the sprites' centre sits in [box] (fractions).
  final Offset hub;
  final bool pressed;

  /// Follow the body's yaw (setting "3D controls"); false keeps it face-on.
  final bool turns;

  /// The photoreal body's art: its own renders of the shutter, in the
  /// body's light (null: the turntable frames in assets/shutters).
  final BodyArt? art;

  /// Film: the lever's turn from parked, radians clockwise; null or parked
  /// when it isn't moving.
  final double? lever;
  final _Lamp? lamp;

  static const step = 12, maxAngle = 48;

  /// Turntable frames in use (false: draw the buttons flat from base / lever
  /// / cap layers; only film's layers are still shipped, for its stroke).
  static const turntable = true;

  static String _base(String kind) => kind == 'digitalrec' ? 'digital-base' : '$kind-base';

  /// Parked lever (matches the renders).
  static const leverRest = 0.18;

  static String asset(String name) => 'assets/shutters/shutter_$name.webp';

  /// Every picture [kind] can show.
  static List<String> framesOf(String kind) => [
    if (turntable) ...[
      for (var a = -maxAngle; a <= maxAngle; a += step) '$kind-all-a$a',
      '$kind-all-down-a0',
    ],
    if (!turntable || kind == 'film') ...[_base(kind), '$kind-cap', '$kind-cap-down'],
    if (kind == 'film') 'film-lever',
  ];

  /// Decoded at the size it's drawn (crisp, and a fraction of the memory).
  static ImageProvider provider(String name, double span, double dpr) =>
      ResizeImage(AssetImage(asset(name)), width: (span * dpr).round(), policy: ResizeImagePolicy.fit);

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final c = Offset(box.width * hub.dx, box.height * hub.dy);
    final yaw = turns ? BodyYaw.of(context) : 0.0;
    Widget sprite(String name, {double opacity = 1, double angle = 0, bool sunk = false}) {
      Widget img = Image(
        image: provider(name, span, dpr),
        width: span,
        height: span,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      );
      if (sunk) {
        // Pressed in: a touch smaller (further away) and in its own shade.
        img = Transform.scale(
          scale: 0.97,
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              0.86, 0, 0, 0, 0, //
              0, 0.86, 0, 0, 0, //
              0, 0, 0.86, 0, 0, //
              0, 0, 0, 1, 0,
            ]),
            child: img,
          ),
        );
      }
      if (angle != 0) img = Transform.rotate(angle: angle, child: img);
      if (opacity < 1) img = Opacity(opacity: opacity, child: img);
      return Positioned(left: c.dx - span / 2, top: c.dy - span / 2, width: span, height: span, child: img);
    }

    final List<Widget> layers;
    final stroke = lever != null && (lever! - leverRest).abs() > 1e-3;
    final mode = kind == 'film' || kind == 'run' ? AppMode.film : AppMode.digital;
    final art = this.art;
    if (art != null) {
      BodyPart part(String n) => art.part(mode, n)!;
      Widget at(Widget w, BodyPart p) => Positioned(
        left: c.dx - p.canvas.width / 2,
        top: c.dy - p.canvas.height / 2,
        width: p.canvas.width,
        height: p.canvas.height,
        child: w,
      );
      final st = pressed ? 'down' : 'up';
      final name = switch (kind) {
        'film' => 'shutter',
        'run' => 'run',
        'digitalrec' => 'rec',
        _ => 'shutter',
      };
      layers = stroke
          ? [
              // The lever swings under the release's collar.
              at(
                Transform.rotate(angle: lever! - leverRest, child: BodySprite(part('lever'))),
                part('lever'),
              ),
              at(BodySprite(part('release'), state: st), part('release')),
            ]
          : [at(BodySprite(part(name), state: st), part(name))];
    } else if (stroke || !turntable) {
      layers = [
        sprite(_base(kind)),
        if (lever != null) sprite('film-lever', angle: lever! - leverRest),
        sprite(pressed ? '$kind-cap-down' : '$kind-cap', sunk: pressed),
      ];
    } else if (pressed || yaw == 0) {
      layers = [sprite(pressed ? '$kind-all-down-a0' : '$kind-all-a0', sunk: pressed)];
    } else {
      final deg = (yaw * 180 / math.pi).clamp(-maxAngle.toDouble(), maxAngle.toDouble());
      final lo = ((deg / step).floor() * step).clamp(-maxAngle, maxAngle - step);
      final f = ((deg - lo) / step).clamp(0.0, 1.0);
      final turned = [sprite('$kind-all-a$lo'), if (f > 0.02) sprite('$kind-all-a${lo + step}', opacity: f)];
      layers = [
        Positioned.fill(
          child: Transform(
            alignment: Alignment(hub.dx * 2 - 1, hub.dy * 2 - 1),
            transform: Matrix4.diagonal3Values(1 / math.cos(yaw).clamp(0.5, 1.0), 1, 1),
            child: Stack(clipBehavior: Clip.none, children: turned),
          ),
        ),
      ];
    }
    final l = lamp;
    return SizedBox.fromSize(
      size: box,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ...layers,
          if (l != null)
            Positioned(
              left: c.dx + l.at.dx * span - l.radius * span,
              top: c.dy + l.at.dy * span - l.radius * span,
              width: l.radius * 2 * span,
              height: l.radius * 2 * span,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: l.color.withValues(alpha: 0.85),
                    boxShadow: [
                      BoxShadow(color: l.color.withValues(alpha: 0.7), blurRadius: 10, spreadRadius: 2),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
