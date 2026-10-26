import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The room the reels are shown in: a dark wood-panelled wall, the picture
/// on a matte screen (thin black border) lit by the projector behind you
/// (a faint beam of haze, its light warming the wall round the screen),
/// and below it a walnut hi-fi console with a lamp and a plant, the lamp
/// glowing. Art from `tool/room/make_room.py`.
class ProjectorRoom extends StatelessWidget {
  const ProjectorRoom({
    super.key,
    required this.aspect,
    required this.picture,
    required this.run,
    this.placeholder,
  });

  /// The reel's width / height; null while it threads (shows [placeholder]).
  final double? aspect;
  final Widget picture;
  final Widget? placeholder;

  /// The projector's lamp flickers with the film (lights the wall too).
  final Animation<double> run;

  static const wallAsset = 'assets/corkboard/room_wall.webp';
  static const consoleAsset = 'assets/corkboard/room_console.webp';

  /// room_console.webp: size, where its top board is and where the lamp
  /// shade's centre is (fractions of the image; make_room.py LAMP).
  static const _consoleAspect = 1260 / 640;
  static const _surface = 362 / 640;
  static const _lamp = Offset(0.105, 0.26);

  /// Where the screen goes in a [size] room for a reel of [aspect], and the
  /// console's box. Shared with the tests.
  static ({Rect screen, Rect console}) layout(Size size, double aspect) {
    final land = size.width > size.height;
    final floor = size.height - (land ? 4.0 : 8.0);
    // The console: most of the width when upright, a smaller piece of
    // furniture under a wide screen when turned.
    final cw = land ? math.min(size.width * 0.62, size.height * 0.34 * _consoleAspect) : size.width * 0.92;
    final ch = cw / _consoleAspect;
    final console = Rect.fromLTWH((size.width - cw) / 2, floor - ch, cw, ch);
    final surface = console.top + ch * _surface;
    final above = surface - console.top;
    const pad = 14.0, top = 12.0;

    Rect fit(double bottom) {
      final aw = size.width - 2 * pad, ah = bottom - top;
      var w = aw, h = w / aspect;
      if (h > ah) {
        h = ah;
        w = h * aspect;
      }
      return Rect.fromLTWH((size.width - w) / 2, top + (ah - h) / 2, w, h);
    }

    // Clear of the lamp and the plant unless that leaves a small screen;
    // then the furniture stands in front of its lower edge.
    final clear = fit(surface - above * 0.92);
    final tight = fit(surface - 10);
    return (screen: clear.width >= tight.width * 0.6 ? clear : tight, console: console);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final l = layout(size, aspect ?? 4 / 3);
        final screen = l.screen, console = l.console;
        final lamp = Offset(console.left + console.width * _lamp.dx, console.top + console.height * _lamp.dy);
        return Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: Image.asset(
                  wallAsset,
                  repeat: ImageRepeat.repeat,
                  scale: 3,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: run,
                  builder: (context, _) => CustomPaint(
                    painter: _RoomLight(
                      screen: screen,
                      lamp: lamp,
                      lampRadius: console.width * 0.3,
                      floor: console.bottom,
                      on: aspect != null,
                      flicker: run.isAnimating ? _flicker(run.value) : 0,
                    ),
                  ),
                ),
              ),
            ),
            if (aspect != null) ...[
              Positioned.fromRect(
                rect: screen.inflate(4),
                child: const ColoredBox(color: Color(0xFF0C0A09)),
              ),
              Positioned.fromRect(rect: screen, child: picture),
            ] else
              Positioned.fromRect(
                rect: screen,
                child: Center(child: placeholder),
              ),
            Positioned.fromRect(
              rect: console,
              child: Image.asset(consoleAsset, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
            ),
          ],
        );
      },
    );
  }

  /// The projector lamp's flicker (0..~0.07), stepped 18 times a second.
  static double _flicker(double phase) {
    final frame = (phase * 18).floor();
    return 0.02 + math.Random(frame * 7919).nextDouble() * 0.05;
  }
}

/// The light in the room: dark everywhere but round the screen (its light
/// warms the wall and fades out), a soft beam of haze down to it from the
/// projector behind you, the lamp's pool of light, a darker floor.
class _RoomLight extends CustomPainter {
  _RoomLight({
    required this.screen,
    required this.lamp,
    required this.lampRadius,
    required this.floor,
    required this.on,
    required this.flicker,
  });

  final Rect screen;
  final Offset lamp;
  final double lampRadius;
  final double floor;
  final bool on;
  final double flicker;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    final glow = on ? 1 - flicker * 2.5 : 0.25;
    // Darkness falling off away from the screen.
    final reach = math.max(screen.width, screen.height) * 0.62 + 120;
    canvas.drawRect(
      all,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.fromRGBO(255, 180, 110, 0.20 * glow),
            Color.fromRGBO(120, 70, 30, 0.05 * glow),
            const Color(0xC8060403),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCenter(center: screen.center, width: reach * 2, height: reach * 2)),
    );
    // The beam: haze from the projector (top centre) widening onto the
    // screen's top edge, a few soft layers.
    if (on) {
      for (final (spread, alpha) in [(0.0, 0.05), (18.0, 0.035), (40.0, 0.02)]) {
        final path = Path()
          ..moveTo(size.width / 2 - 18 - spread * 0.3, 0)
          ..lineTo(size.width / 2 + 18 + spread * 0.3, 0)
          ..lineTo(screen.right + spread, screen.top)
          ..lineTo(screen.left - spread, screen.top)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromRGBO(255, 220, 170, alpha * glow * 0.4),
                Color.fromRGBO(255, 210, 150, alpha * glow),
              ],
            ).createShader(Rect.fromLTRB(0, 0, size.width, screen.top)),
        );
      }
    }
    // The lamp's warm pool on the wall and the console top.
    canvas.drawCircle(
      lamp,
      lampRadius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x50FFB060), Color(0x18FF9A40), Color(0x00FF9A40)],
          stops: [0, 0.4, 1],
        ).createShader(Rect.fromCircle(center: lamp, radius: lampRadius)),
    );
    // The floor.
    canvas.drawRect(
      Rect.fromLTRB(0, floor - 2, size.width, size.height),
      Paint()..color = const Color(0xFF0A0706),
    );
  }

  @override
  bool shouldRepaint(_RoomLight old) =>
      old.screen != screen ||
      old.lamp != lamp ||
      old.flicker != flicker ||
      old.on != on ||
      old.floor != floor;
}
