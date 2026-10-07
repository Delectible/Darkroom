import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/sfx.dart';
import '../../../cameras/domain/camera_spec.dart';
import '../../application/camera_ui_state.dart';
import '../../application/capture_controller.dart';

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
        unawaited(HapticFeedback.lightImpact());
      case _Kind.film:
        Sfx.shutterFilm.play();
        unawaited(HapticFeedback.mediumImpact());
      case _Kind.run:
        Sfx.shutterRun.play();
        unawaited(HapticFeedback.mediumImpact());
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
          _Kind.digital => CustomPaint(
            size: const Size(92, 78),
            painter: _DigitalKeyPainter(
              pressed: _down || (t > 0 && t < 0.6),
              rec: video,
              recording: recording,
            ),
          ),
          _Kind.film => CustomPaint(
            size: const Size(104, 84),
            // Chrome, whatever the body's trim.
            painter: _FilmReleasePainter(
              pressed: _down,
              stroke: t,
              metal: const Color(0xFFC4C8CD),
              metalDark: const Color(0xFF5F646A),
            ),
          ),
          _Kind.run => CustomPaint(
            size: const Size(86, 86),
            painter: _RunButtonPainter(pressed: _down || recording, recording: recording),
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

Paint _shadow(double blur, [double alpha = 0.45]) => Paint()
  ..color = Colors.black.withValues(alpha: alpha)
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

/// A compact camera's shutter key: brushed-silver bezel, a squared key with
/// a soft dome that sinks when pressed. Camcorders get a red record dot.
class _DigitalKeyPainter extends CustomPainter {
  _DigitalKeyPainter({required this.pressed, required this.rec, required this.recording});

  final bool pressed;
  final bool rec;
  final bool recording;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18));
    canvas.drawRRect(outer.shift(const Offset(0, 3)), _shadow(5));
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF2F4F6), Color(0xFFB7BCC2), Color(0xFF8D9399)],
        ).createShader(outer.outerRect),
    );
    canvas.drawRRect(
      outer.deflate(0.5),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke,
    );
    // The well the key sits in.
    final well = outer.deflate(6);
    canvas.drawRRect(well, Paint()..color = const Color(0xFF2B2E33));
    // The key: travels 2.5 px and darkens a touch when pressed.
    final travel = pressed ? 2.5 : 0.0;
    final key = RRect.fromRectAndRadius(
      well.outerRect.deflate(3).shift(Offset(0, travel)),
      const Radius.circular(12),
    );
    if (!pressed) canvas.drawRRect(key.shift(const Offset(0, 2.5)), Paint()..color = const Color(0xFF15171A));
    canvas.drawRRect(
      key,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: pressed
              ? const [Color(0xFFC9CED3), Color(0xFF9DA3A9)]
              : const [Color(0xFFF7F8FA), Color(0xFFC3C8CE)],
        ).createShader(key.outerRect),
    );
    // Soft dome highlight.
    final glint = RRect.fromRectAndRadius(
      Rect.fromLTWH(key.left + 8, key.top + 4, key.width - 16, key.height * 0.32),
      const Radius.circular(8),
    );
    canvas.drawRRect(glint, Paint()..color = Colors.white.withValues(alpha: pressed ? 0.25 : 0.55));
    if (rec) {
      final c = key.center;
      if (recording) canvas.drawCircle(c, 15, _shadow(6, 0.0)..color = const Color(0xAAFF2A1E));
      canvas.drawCircle(c, 9, Paint()..color = recording ? const Color(0xFFFF3B2E) : const Color(0xFFC0281E));
      canvas.drawCircle(c + const Offset(-2.5, -2.5), 2.5, Paint()..color = Colors.white54);
    }
  }

  @override
  bool shouldRepaint(_DigitalKeyPainter old) =>
      old.pressed != pressed || old.rec != rec || old.recording != recording;
}

/// A chrome shutter release in the hub of the film-advance lever. Each
/// frame the lever swings out (winding on) and springs home.
class _FilmReleasePainter extends CustomPainter {
  _FilmReleasePainter({
    required this.pressed,
    required this.stroke,
    required this.metal,
    required this.metalDark,
  });

  final bool pressed;
  final double stroke;
  final Color metal;
  final Color metalDark;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.6, size.height * 0.52);
    // The lever: parked pointing left along the body; swings up and out.
    final swing = stroke <= 0
        ? 0.0
        : stroke < 0.45
        ? Curves.easeOut.transform(stroke / 0.45)
        : 1 - Curves.easeInOutBack.transform(((stroke - 0.45) / 0.55).clamp(0.0, 1.0));
    final angle = math.pi + 0.18 + swing * 0.95;
    final dir = Offset.fromDirection(angle);
    final normal = Offset(-dir.dy, dir.dx);
    const len = 50.0;
    final tip = c + dir * len;
    final arm = Path()
      ..moveTo((c + normal * 8).dx, (c + normal * 8).dy)
      ..lineTo((tip + normal * 4).dx, (tip + normal * 4).dy)
      ..lineTo((tip - normal * 4).dx, (tip - normal * 4).dy)
      ..lineTo((c - normal * 8).dx, (c - normal * 8).dy)
      ..close();
    canvas.drawPath(arm.shift(const Offset(0, 3)), _shadow(3));
    canvas.drawPath(
      arm,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(metal, Colors.white, 0.6)!, metal, metalDark],
        ).createShader(Rect.fromCircle(center: c, radius: len)),
    );
    // Plastic thumb pad on the lever's tip.
    canvas.drawCircle(tip, 7, Paint()..color = const Color(0xFF15120F));
    canvas.drawCircle(tip + const Offset(-1.5, -1.5), 2.5, Paint()..color = Colors.white24);
    // Knurled collar round the hub.
    canvas.drawCircle(c.translate(0, 3), 25, _shadow(4));
    canvas.drawCircle(
      c,
      25,
      Paint()
        ..shader = SweepGradient(
          colors: [metal, metalDark, metal, metalDark, metal],
        ).createShader(Rect.fromCircle(center: c, radius: 25)),
    );
    final knurl = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (var i = 0; i < 60; i++) {
      final d = Offset.fromDirection(i * math.pi * 2 / 60);
      canvas.drawLine(c + d * 21.5, c + d * 25, knurl);
    }
    // The release: a machined chrome dome with a cable-release socket.
    final dome = pressed ? 15.0 : 16.5;
    canvas.drawCircle(c, dome + 1.5, Paint()..color = const Color(0xFF26231F));
    canvas.drawCircle(
      c + (pressed ? const Offset(0, 0.8) : Offset.zero),
      dome,
      Paint()
        ..shader = RadialGradient(
          center: pressed ? Alignment.center : const Alignment(-0.4, -0.5),
          colors: const [Color(0xFFFFFFFF), Color(0xFFC9CCD0), Color(0xFF6E7277)],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: c, radius: dome)),
    );
    final rings = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    for (var r = 5.0; r < dome; r += 2.6) {
      canvas.drawCircle(c, r, rings);
    }
    canvas.drawCircle(c, 3.2, Paint()..color = const Color(0xFF1A1714));
    canvas.drawCircle(c, 1.4, Paint()..color = const Color(0xFF5A5650));
  }

  @override
  bool shouldRepaint(_FilmReleasePainter old) =>
      old.pressed != pressed || old.stroke != stroke || old.metal != metal;
}

/// Super 8: a chunky red RUN button in a black lock collar. It latches in
/// while the camera runs, with the run lamp lit.
class _RunButtonPainter extends CustomPainter {
  _RunButtonPainter({required this.pressed, required this.recording});

  final bool pressed;
  final bool recording;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(22));
    canvas.drawRRect(outer.shift(const Offset(0, 3)), _shadow(5));
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A3A3C), Color(0xFF111112)],
        ).createShader(outer.outerRect),
    );
    // Ribbed grip round the collar.
    final rib = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1.2;
    for (var x = outer.left + 10; x < outer.right - 10; x += 4) {
      canvas.drawLine(Offset(x, outer.top + 2), Offset(x, outer.top + 7), rib);
      canvas.drawLine(Offset(x, outer.bottom - 7), Offset(x, outer.bottom - 2), rib);
    }
    // The run lamp.
    final lamp = Offset(outer.right - 13, outer.top + 13);
    if (recording) canvas.drawCircle(lamp, 7, _shadow(4, 0)..color = const Color(0xCCFF2A1E));
    canvas.drawCircle(
      lamp,
      3.4,
      Paint()..color = recording ? const Color(0xFFFF3B2E) : const Color(0xFF4A1512),
    );
    // The button: travels in and stays in while running.
    final travel = pressed ? 2.5 : 0.0;
    final key = RRect.fromRectAndRadius(
      outer.outerRect.deflate(15).shift(Offset(0, travel)),
      const Radius.circular(14),
    );
    if (!pressed) canvas.drawRRect(key.shift(const Offset(0, 3)), Paint()..color = const Color(0xFF5A0E0A));
    canvas.drawRRect(
      key,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.5),
          radius: 1.1,
          colors: pressed
              ? const [Color(0xFFD8392B), Color(0xFF8E1A12)]
              : const [Color(0xFFFF6A57), Color(0xFFC4241A), Color(0xFF8E1A12)],
        ).createShader(key.outerRect),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: 'RUN',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, key.center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_RunButtonPainter old) => old.pressed != pressed || old.recording != recording;
}
