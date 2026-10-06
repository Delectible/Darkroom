import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/pixel_font.dart';

/// Camera-body surface (pebbled leatherette for film, brushed metal for
/// digital), built for cheap phones.
///
/// Impeller re-renders every layer on every frame (there is no raster cache),
/// so a background made of thousands of vector pebbles costs thousands of
/// draws per frame — that is what made the film screen drop to ~15 fps. The
/// texture is instead rendered ONCE into a small seamless tile (a GPU image)
/// and drawn with an ImageShader: one textured rect per frame. Lighting is a
/// separate two-stop gradient.
class SurfaceTexture extends StatelessWidget {
  const SurfaceTexture({
    super.key,
    required this.leather,
    required this.base,
    required this.light,
    required this.dark,
  });

  final bool leather;
  final Color base;
  final Color light;
  final Color dark;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _TilePainter(leather: leather, base: base, light: light, dark: dark, dpr: dpr),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TilePainter extends CustomPainter {
  _TilePainter({
    required this.leather,
    required this.base,
    required this.light,
    required this.dark,
    required this.dpr,
  });

  final bool leather;
  final Color base;
  final Color light;
  final Color dark;
  final double dpr;

  static const _tileLogical = 128.0;
  static final Map<String, ui.Image> _cache = {};

  ui.Image _tile() {
    final key = '$leather-${base.toARGB32()}-${light.toARGB32()}-${dark.toARGB32()}-$dpr';
    // Bounded: two skins x a DPR change at most. Old images are left to the
    // GC rather than disposed, since the previous frame may still use them.
    if (!_cache.containsKey(key) && _cache.length >= 4) _cache.clear();
    return _cache.putIfAbsent(key, () {
      final px = (_tileLogical * dpr).round();
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      c.scale(px / _tileLogical);
      const t = _tileLogical;
      final rnd = math.Random(7);
      if (leather) {
        c.drawRect(const Rect.fromLTWH(0, 0, t, t), Paint()..color = base);
        final hi = Paint()..color = light.withValues(alpha: 0.35);
        final lo = Paint()..color = dark.withValues(alpha: 0.55);
        for (var i = 0; i < 300; i++) {
          final x = rnd.nextDouble() * t, y = rnd.nextDouble() * t;
          final r = 0.9 + rnd.nextDouble() * 1.8;
          // Draw wrapped copies so the tile is seamless.
          for (final dx in const [-t, 0.0, t]) {
            for (final dy in const [-t, 0.0, t]) {
              final o = Offset(x + dx, y + dy);
              if (o.dx < -4 || o.dy < -4 || o.dx > t + 4 || o.dy > t + 4) continue;
              c.drawCircle(o + const Offset(0.6, 0.6), r, lo);
              c.drawCircle(o, r * 0.75, hi);
            }
          }
        }
      } else {
        c.drawRect(const Rect.fromLTWH(0, 0, t, t), Paint()..color = base);
        final line = Paint()..strokeWidth = 1;
        for (var y = 0.0; y < t; y += 1.6) {
          line.color = (rnd.nextBool() ? Colors.white : Colors.black).withValues(
            alpha: 0.03 + rnd.nextDouble() * 0.06,
          );
          c.drawLine(Offset(0, y), Offset(t, y), line);
        }
      }
      return recorder.endRecording().toImageSync(px, px);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final tile = _tile();
    final m = Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.ImageShader(tile, TileMode.repeated, TileMode.repeated, m.storage)
        ..filterQuality = FilterQuality.low,
    );
    // Lighting.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: leather
              ? [Colors.white.withValues(alpha: 0.06), Colors.black.withValues(alpha: 0.25)]
              : [
                  Colors.white.withValues(alpha: 0.35),
                  Colors.transparent,
                  Colors.white.withValues(alpha: 0.2),
                  Colors.black.withValues(alpha: 0.18),
                ],
          stops: leather ? null : const [0, 0.45, 0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_TilePainter old) =>
      old.leather != leather || old.base != base || old.light != light || old.dark != dark || old.dpr != dpr;
}

/// Renders text with the dot-matrix [PixelFont] (LCD read-outs, timestamps).
class PixelText extends StatelessWidget {
  const PixelText(this.text, {super.key, this.dot = 2, this.color = Colors.white, this.glow, this.shadow});

  final String text;
  final double dot;
  final Color color;
  final Color? glow;
  final Color? shadow;

  @override
  Widget build(BuildContext context) {
    final w = PixelFont.measureDots(text) * dot;
    final h = PixelFont.glyphHeight * dot;
    return CustomPaint(
      size: Size(w + dot, h + dot),
      painter: _PixelTextPainter(text, dot, color, glow, shadow),
    );
  }
}

class _PixelTextPainter extends CustomPainter {
  _PixelTextPainter(this.text, this.dot, this.color, this.glow, this.shadow);

  final String text;
  final double dot;
  final Color color;
  final Color? glow;
  final Color? shadow;

  @override
  void paint(Canvas canvas, Size size) {
    void layer(Color c, Offset o, {double grow = 0}) {
      final paint = Paint()..color = c;
      PixelFont.forEachDot(text, (x, y) {
        canvas.drawRect(
          Rect.fromLTWH(x * dot + o.dx - grow, y * dot + o.dy - grow, dot + 2 * grow, dot + 2 * grow),
          paint,
        );
      });
    }

    if (glow != null) layer(glow!.withValues(alpha: 0.25), Offset.zero, grow: dot * 0.5);
    if (shadow != null) layer(shadow!, Offset(dot * 0.5, dot * 0.5));
    layer(color, Offset.zero);
  }

  @override
  bool shouldRepaint(_PixelTextPainter old) => old.text != text || old.dot != dot || old.color != color;
}
