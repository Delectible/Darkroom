import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/sfx.dart';
import '../../../cameras/domain/camera_spec.dart';
import '../../application/camera_ui_state.dart';
import '../../application/capture_controller.dart';
import '../body_swap.dart' show BodyYaw;
import '../../../../core/device/haptics.dart';

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

  bool _cached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Every layer decoded up front: presses and body swaps never wait on one.
    if (_cached) return;
    _cached = true;
    for (final name in _SpriteShutter.all) {
      unawaited(precacheImage(AssetImage(_SpriteShutter.asset(name)), context));
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

    final Widget face = AnimatedBuilder(
      key: ValueKey(kind),
      animation: _stroke,
      builder: (context, _) {
        final t = _stroke.isAnimating ? _stroke.value : 0.0;
        return switch (kind) {
          _Kind.digital => _SpriteShutter(
            box: const Size(92, 78),
            span: 96,
            base: 'digital-base',
            cap: video ? 'digitalrec-cap' : 'digital-cap',
            pressed: _down || (t > 0 && t < 0.6),
            capHeight: 10,
            lamp: recording ? const _Lamp(Offset.zero, 0.09, Color(0xFFFF3B30)) : null,
          ),
          _Kind.film => _SpriteShutter(
            box: const Size(108, 86),
            span: 138,
            hub: const Offset(0.6, 0.52),
            base: 'film-base',
            cap: 'film-cap',
            pressed: _down,
            capHeight: 12,
            lever: _leverAngle(t),
          ),
          _Kind.run => _SpriteShutter(
            box: const Size(86, 86),
            span: 108,
            base: 'run-base',
            cap: 'run-cap',
            pressed: _down || recording,
            capHeight: 13,
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

/// A shutter drawn from path-traced layers (tool/render/items/shutter.js):
/// the fixed base, the button cap (pressed or not) and, for film, the
/// advance lever. While the body tips during a swap the cap and lever slide
/// a little against the base (BodyYaw), so the button reads as solid rather
/// than printed on.
class _SpriteShutter extends StatelessWidget {
  const _SpriteShutter({
    required this.box,
    required this.span,
    required this.base,
    required this.cap,
    required this.pressed,
    required this.capHeight,
    this.hub = const Offset(0.5, 0.5),
    this.lever,
    this.lamp,
  });

  /// Layout size of the button.
  final Size box;

  /// Size of the (square) sprites on screen.
  final double span;

  /// Where the sprites' centre sits in [box] (fractions).
  final Offset hub;
  final String base;
  final String cap;
  final bool pressed;

  /// How far the cap stands off the body, in logical px (for the parallax).
  final double capHeight;

  /// Film: the lever's turn from parked, radians clockwise.
  final double? lever;
  final _Lamp? lamp;

  static String asset(String name) => 'assets/shutters/shutter_$name.webp';

  /// Every layer, for precaching.
  static const all = [
    'digital-base', 'digital-cap', 'digital-cap-down', 'digitalrec-cap', 'digitalrec-cap-down', //
    'film-base', 'film-cap', 'film-cap-down', 'film-lever', 'run-base', 'run-cap', 'run-cap-down',
  ];

  @override
  Widget build(BuildContext context) {
    final shift = BodyYaw.parallax(context, pressed ? capHeight * 0.6 : capHeight);
    final c = Offset(box.width * hub.dx, box.height * hub.dy);
    Widget layer(String name, {double dx = 0, double angle = 0, bool sunk = false}) {
      Widget img = Image.asset(asset(name), filterQuality: FilterQuality.medium, gaplessPlayback: true);
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
      return Positioned(
        left: c.dx - span / 2 + dx,
        top: c.dy - span / 2,
        width: span,
        height: span,
        child: Transform.rotate(angle: angle, child: img),
      );
    }

    final l = lamp;
    return SizedBox.fromSize(
      size: box,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          layer(base),
          if (lever != null) layer('film-lever', dx: shift * 0.6, angle: lever!),
          layer(pressed ? '$cap-down' : cap, dx: shift, sunk: pressed),
          if (l != null)
            Positioned(
              left: c.dx + l.at.dx * span - l.radius * span + shift,
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
