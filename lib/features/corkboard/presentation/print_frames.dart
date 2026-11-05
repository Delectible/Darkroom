import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers.dart';
import '../../camera/application/camera_ui_state.dart';

/// How a (non-instant) print is finished round its edges.
enum PrintFrame {
  /// The lab's white border.
  classic('Classic'),

  /// Printed to the edge.
  borderless('Borderless'),

  /// The scalloped edge of an old snapshot.
  deckle('Deckle'),

  /// Printed through a filed-out negative carrier: the film's rough black
  /// edge round the picture, the frame number in it.
  darkroom('Darkroom');

  const PrintFrame(this.label);
  final String label;
}

/// Each print's frame (by print id; classic unless set), kept in prefs.
final printFramesProvider = NotifierProvider<PrintFrames, Map<String, PrintFrame>>(PrintFrames.new);

class PrintFrames extends Notifier<Map<String, PrintFrame>> {
  @override
  Map<String, PrintFrame> build() {
    final raw = _prefs?.getString(PrefKeys.printFrames);
    if (raw == null) return const {};
    try {
      final m = (jsonDecode(raw) as Map).cast<String, String>();
      return {for (final e in m.entries) e.key: ?PrintFrame.values.asNameMap()[e.value]};
    } catch (_) {
      return const {};
    }
  }

  PrintFrame of(String id) => state[id] ?? PrintFrame.classic;

  /// (None in tests: kept in memory only.)
  SharedPreferencesWithCache? get _prefs {
    try {
      return ref.read(sharedPrefsProvider);
    } catch (_) {
      return null;
    }
  }

  void set(String id, PrintFrame frame) {
    final next = {...state}..remove(id);
    if (frame != PrintFrame.classic) next[id] = frame;
    state = next;
    _prefs?.setString(PrefKeys.printFrames, jsonEncode({for (final e in next.entries) e.key: e.value.name}));
  }
}

/// [photo] finished in [frame], filling the [aspect] box it's given (the
/// photo's own shape). [number]: the frame number for the darkroom edge.
class FramedPrint extends StatelessWidget {
  const FramedPrint({
    super.key,
    required this.frame,
    required this.photo,
    this.number,
    this.seed = 0,
    this.shadow = true,
  });

  final PrintFrame frame;
  final Widget photo;
  final String? number;

  /// Keeps each print's rough edge its own.
  final int seed;

  /// The print's shadow (off for small previews).
  final bool shadow;

  static const paper = Color(0xFFFBF8F1);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final s = math.min(c.maxWidth, c.maxHeight);
      final shadows = shadow
          ? const [BoxShadow(color: Colors.black87, blurRadius: 24, offset: Offset(0, 12))]
          : const <BoxShadow>[];
      switch (frame) {
        case PrintFrame.classic:
          return DecoratedBox(
            decoration: BoxDecoration(color: paper, boxShadow: shadows),
            child: Padding(padding: EdgeInsets.all(s * 0.035), child: photo),
          );
        case PrintFrame.borderless:
          return DecoratedBox(
            decoration: BoxDecoration(color: paper, boxShadow: shadows),
            child: photo,
          );
        case PrintFrame.deckle:
          return DecoratedBox(
            // (the shadow of the rectangle: the scallops are too small for
            // their own to show)
            decoration: BoxDecoration(boxShadow: shadows),
            child: ClipPath(
              clipper: _Deckle(s * 0.018),
              child: ColoredBox(
                color: const Color(0xFFF4EEDF),
                child: Padding(padding: EdgeInsets.all(s * 0.075), child: photo),
              ),
            ),
          );
        case PrintFrame.darkroom:
          final border = s * 0.07;
          return DecoratedBox(
            decoration: BoxDecoration(color: paper, boxShadow: shadows),
            child: Padding(
              padding: EdgeInsets.all(s * 0.03),
              child: ColoredBox(
                color: const Color(0xFF0E0D0C),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(border),
                      child: ClipPath(clipper: _Filed(s * 0.006, seed), child: photo),
                    ),
                    if (number != null && s > 120)
                      Positioned(
                        left: border,
                        bottom: border * 0.18,
                        child: Text(
                          '▸ $number',
                          style: TextStyle(
                            color: const Color(0xB3D99A3E),
                            fontSize: border * 0.6,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
      }
    },
  );
}

/// A scalloped edge all round: small arcs [r] wide.
class _Deckle extends CustomClipper<Path> {
  const _Deckle(this.r);
  final double r;

  @override
  Path getClip(Size size) {
    final p = Path();
    final w = size.width, h = size.height;
    final nx = math.max(2, (w / (r * 2.2)).round()), ny = math.max(2, (h / (r * 2.2)).round());
    final dx = w / nx, dy = h / ny;
    p.moveTo(0, 0);
    for (var i = 0; i < nx; i++) {
      p.quadraticBezierTo(dx * (i + 0.5), r * 1.1, dx * (i + 1), 0);
    }
    for (var i = 0; i < ny; i++) {
      p.quadraticBezierTo(w - r * 1.1, dy * (i + 0.5), w, dy * (i + 1));
    }
    for (var i = nx; i > 0; i--) {
      p.quadraticBezierTo(dx * (i - 0.5), h - r * 1.1, dx * (i - 1), h);
    }
    for (var i = ny; i > 0; i--) {
      p.quadraticBezierTo(r * 1.1, dy * (i - 0.5), 0, dy * (i - 1));
    }
    return p..close();
  }

  @override
  bool shouldReclip(_Deckle old) => old.r != r;
}

/// The picture's edge as a filed negative carrier leaves it: slightly
/// rough, bulging a hair here and there ([j]: how far).
class _Filed extends CustomClipper<Path> {
  const _Filed(this.j, this.seed);
  final double j;
  final int seed;

  @override
  Path getClip(Size size) {
    final rnd = math.Random(seed);
    final w = size.width, h = size.height;
    double n() => (rnd.nextDouble() - 0.5) * 2 * j;
    final p = Path()..moveTo(n().abs(), n().abs());
    const steps = 24;
    for (var i = 1; i <= steps; i++) {
      p.lineTo(w * i / steps, n().abs());
    }
    for (var i = 1; i <= steps; i++) {
      p.lineTo(w - n().abs(), h * i / steps);
    }
    for (var i = steps - 1; i >= 0; i--) {
      p.lineTo(w * i / steps, h - n().abs());
    }
    for (var i = steps - 1; i > 0; i--) {
      p.lineTo(n().abs(), h * i / steps);
    }
    return p..close();
  }

  @override
  bool shouldReclip(_Filed old) => old.j != j || old.seed != seed;
}

/// The frames to choose from for one print: a small preview of it in each,
/// the one on it marked. Tapping one puts it on at once.
class FramePicker extends StatelessWidget {
  const FramePicker({
    super.key,
    required this.current,
    required this.preview,
    required this.aspect,
    required this.onPick,
  });

  final PrintFrame current;
  final Widget preview;
  final double aspect;
  final ValueChanged<PrintFrame> onPick;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in PrintFrame.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Semantics(
                button: true,
                selected: f == current,
                label: '${f.label} frame',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(f),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 64,
                        height: 64,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: f == current ? const Color(0x26FFFFFF) : Colors.transparent,
                          border: Border.all(
                            color: f == current ? const Color(0xCCF2C46D) : const Color(0x1FFFFFFF),
                            width: f == current ? 1.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: aspect,
                            child: FramedPrint(frame: f, photo: preview, number: '07', shadow: false),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        f.label,
                        style: TextStyle(
                          color: f == current ? const Color(0xFFF2C46D) : Colors.white70,
                          fontSize: 12,
                          fontWeight: f == current ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
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
