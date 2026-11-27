import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Soft drop shadows drawn from a blurred picture made once, instead of a
/// blur worked out again on every frame. Impeller keeps no copy of what it
/// drew last frame, so a board of prints each with a blurred shadow cost
/// the GPU most of its frame while scrolling (2.4.9 Performance Report).
/// A shadow is a rounded rectangle blurred once into a small nine-patch,
/// then stretched under the shape: it looks the same as the live blur.
class BakedShadow {
  BakedShadow._();

  static final _cache = <(int, int, int), (ui.Image, double, double)>{};

  /// Paints a shadow for [rect] (already offset and spread), blurred by
  /// [sigma] (a MaskFilter's sigma) with corners of [radius].
  static void paint(
    Canvas canvas,
    Rect rect, {
    required double sigma,
    required Color color,
    double radius = 0,
  }) {
    if (rect.isEmpty || color.a == 0) return;
    final s = (sigma * 2).round().clamp(1, 400), r = (radius * 2).round().clamp(0, 400);
    final key = (s, r, color.toARGB32());
    final (image, pad, core) = _cache.putIfAbsent(key, () => _make(s / 2, r / 2, color));
    final rr = r / 2;
    // the stretchable middle: the flat part of the blurred rounded rect
    final centre = Rect.fromLTWH(pad + rr, pad + rr, math.max(1, core - 2 * rr), math.max(1, core - 2 * rr));
    final dst = rect.inflate(pad);
    if (dst.width < image.width || dst.height < image.height) {
      // too small for the nine-patch: scale the whole picture
      canvas.drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.low,
      );
      return;
    }
    canvas.drawImageNine(image, centre, dst, Paint()..filterQuality = FilterQuality.low);
  }

  static (ui.Image, double, double) _make(double sigma, double radius, Color color) {
    final pad = (sigma * 3).ceilToDouble();
    final core = (radius * 2 + 4).ceilToDouble();
    final side = (pad * 2 + core).toInt();
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(pad, pad, core, core), Radius.circular(radius)),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
    );
    return (rec.endRecording().toImageSync(side, side), pad, core);
  }

  /// A [BoxShadow]'s blur as a MaskFilter sigma (Flutter's own rule).
  static double sigmaOf(BoxShadow s) => s.blurRadius > 0 ? s.blurRadius * 0.57735 + 0.5 : 0;

  /// Paints [shadows] for a box of [size] with corners of [radius].
  static void paintBox(Canvas canvas, Size size, List<BoxShadow> shadows, {double radius = 0}) {
    for (final s in shadows) {
      final rect = (s.offset & size).inflate(s.spreadRadius);
      paint(canvas, rect, sigma: sigmaOf(s), color: s.color, radius: radius);
    }
  }
}

/// A box's [shadows] painted under [child] from [BakedShadow]s (for boxes
/// that appear many times on screen, like prints on the board).
class BakedBoxShadow extends StatelessWidget {
  const BakedBoxShadow({super.key, required this.shadows, this.radius = 0, required this.child});

  final List<BoxShadow> shadows;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      shadows.isEmpty ? child : CustomPaint(painter: _BoxShadowPainter(shadows, radius), child: child);
}

class _BoxShadowPainter extends CustomPainter {
  _BoxShadowPainter(this.shadows, this.radius);
  final List<BoxShadow> shadows;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) => BakedShadow.paintBox(canvas, size, shadows, radius: radius);

  @override
  bool shouldRepaint(_BoxShadowPainter old) => old.radius != radius || !identical(old.shadows, shadows);
}
