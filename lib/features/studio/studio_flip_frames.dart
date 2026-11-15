import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'studio_render.dart';

/// How a flip book goes from one photo to the next.
enum FlipStyle {
  /// A little bound booklet, each page flicked over from the spiral.
  flip('Page flip'),

  /// Snap cuts: the print flashes white as it changes, the camera shakes.
  shutter('Shutter'),

  /// Each print dropped onto a growing pile, landing a little crooked.
  pile('Pile');

  const FlipStyle(this.label);
  final String label;

  static FlipStyle named(String? name) => values.asNameMap()[name] ?? FlipStyle.shutter;
}

/// One flip book's moving picture, the same in the app as in the video: its
/// [photos] at [pageMs] each, in [style], on [paper]. [paint] draws the
/// moment [t] ms in; [keyframes] lists the moments the video needs.
class FlipFrames {
  FlipFrames({required this.photos, required this.paper, required this.style, required this.pageMs});

  final List<ui.Image> photos;
  final StudioPaper paper;
  final FlipStyle style;
  final int pageMs;

  int get length => photos.length;
  int get totalMs => length * pageMs;

  static const _shakeMs = 120, _flashMs = 34;

  /// How long a page's change takes (the flick, the drop).
  int get changeMs => math.min(pageMs * 0.55, style == FlipStyle.pile ? 280.0 : 240.0).round();

  /// The video's frames: each moment and how long it holds. Changes are
  /// drawn at 30 frames a second, the still parts once.
  List<({double at, double hold})> keyframes() {
    final out = <({double at, double hold})>[];
    for (var page = 0; page < length; page++) {
      final start = page * pageMs.toDouble();
      final marks = <double>[0];
      switch (style) {
        case FlipStyle.shutter:
          if (page > 0) marks.add(_flashMs.toDouble());
          for (var s = _shakeMs.toDouble(); s < pageMs; s += _shakeMs) {
            marks.add(s);
          }
        case FlipStyle.flip || FlipStyle.pile:
          if (page > 0) {
            for (var s = 1000 / 30; s < changeMs; s += 1000 / 30) {
              marks.add(s);
            }
            marks.add(changeMs.toDouble());
          }
      }
      marks.sort();
      for (var i = 0; i < marks.length; i++) {
        final end = i + 1 < marks.length ? marks[i + 1] : pageMs.toDouble();
        if (end - marks[i] < 1) continue;
        out.add((at: start + marks[i], hold: end - marks[i]));
      }
    }
    return out;
  }

  /// The moment [t] ms in (looping).
  void paint(Canvas c, Size size, double t) {
    if (photos.isEmpty) return;
    final looped = t % totalMs;
    final page = (looped ~/ pageMs).clamp(0, length - 1);
    final into = looped - page * pageMs;
    switch (style) {
      case FlipStyle.shutter:
        _shutter(c, size, page, into);
      case FlipStyle.flip:
        _flip(c, size, page, into);
      case FlipStyle.pile:
        _pile(c, size, page, into);
    }
  }

  // ---- the print on its card ----

  /// The card [photo] sits on, at its size for a frame [size] wide.
  Size _cardSize(ui.Image photo, Size size, {double fill = 0.852}) {
    final aspect = photo.width / photo.height;
    var pw = size.width * fill, ph = pw / aspect;
    if (ph > size.height * 0.83) {
      ph = size.height * 0.83;
      pw = ph * aspect;
    }
    final border = size.width * 0.037;
    return Size(pw + border, ph + border);
  }

  void _card(
    Canvas c,
    Size size,
    ui.Image photo,
    Offset centre, {
    double turn = 0,
    double scale = 1,
    double lift = 0,
    bool flash = false,
    double fill = 0.852,
  }) {
    final card = _cardSize(photo, size, fill: fill);
    final u = size.width / 1080;
    c.save();
    c.translate(centre.dx, centre.dy);
    c.rotate(turn);
    c.scale(scale);
    final r = Rect.fromCenter(center: Offset.zero, width: card.width, height: card.height);
    c.drawRect(
      r.shift(Offset(5 * u + 18 * u * lift, 9 * u + 30 * u * lift)),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, 0.33 - 0.1 * lift)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 9 * u + 22 * u * lift),
    );
    c.drawRect(r, Paint()..color = const Color(0xFFF7F4EE));
    if (!flash) {
      final border = size.width * 0.037;
      drawCover(c, photo, r.deflate(border / 2), paint: Paint()..filterQuality = FilterQuality.medium);
    }
    c.restore();
  }

  // ---- shutter: snap cuts, a white flash, a handheld shake ----

  void _shutter(Canvas c, Size size, int page, double into) {
    paintPaper(c, Offset.zero & size, paper);
    final u = size.width / 1080;
    final step = into ~/ _shakeMs;
    final rnd = math.Random(page * 977 + step * 31 + photos[page].width);
    final at =
        size.center(Offset.zero) +
        Offset((rnd.nextDouble() - 0.5) * 14 * u, (rnd.nextDouble() - 0.5) * 14 * u);
    _card(
      c,
      size,
      photos[page],
      at,
      turn: (rnd.nextDouble() - 0.5) * 0.025,
      flash: page > 0 && into < _flashMs,
    );
  }

  // ---- pile: each print dropped onto the last ----

  double _pileTurn(int i) => (math.Random(i * 7919 + 13).nextDouble() - 0.5) * 0.22;

  Offset _pileShift(int i, Size size) {
    final r = math.Random(i * 104729 + 7);
    return Offset((r.nextDouble() - 0.5) * size.width * 0.06, (r.nextDouble() - 0.5) * size.height * 0.05);
  }

  void _pile(Canvas c, Size size, int page, double into) {
    paintPaper(c, Offset.zero & size, paper);
    final centre = size.center(Offset.zero);
    // the ones beneath (the last few)
    for (var i = math.max(0, page - 4); i < page; i++) {
      _card(c, size, photos[i], centre + _pileShift(i, size), turn: _pileTurn(i), fill: 0.7);
    }
    final e = page == 0 ? 1.0 : Curves.easeOutBack.transform((into / changeMs).clamp(0.0, 1.0));
    final fall = Curves.easeIn.transform((into / changeMs).clamp(0.0, 1.0));
    _card(
      c,
      size,
      photos[page],
      centre + _pileShift(page, size) + Offset(0, -size.height * 0.08 * (1 - (page == 0 ? 1 : fall))),
      turn: _pileTurn(page) * (0.4 + 0.6 * e),
      scale: 1 + 0.12 * (1 - (page == 0 ? 1 : fall)),
      lift: page == 0 ? 0 : 1 - fall,
      fill: 0.7,
    );
  }

  // ---- page flip: a spiral-bound booklet, the top page flicked over ----

  Rect _bookletPage(Size size) =>
      Rect.fromLTRB(size.width * 0.16, size.height * 0.08, size.width * 0.92, size.height * 0.9);

  void _bookPage(Canvas c, Rect r, ui.Image photo, {double shade = 0}) {
    c.drawRect(r, Paint()..color = const Color(0xFFFBF8F1));
    final inset = r.deflate(r.width * 0.07);
    // the photo, its own shape, in the middle of the page
    final aspect = photo.width / photo.height;
    var w = inset.width, h = w / aspect;
    if (h > inset.height) {
      h = inset.height;
      w = h * aspect;
    }
    final pr = Rect.fromCenter(center: inset.center, width: w, height: h);
    drawCover(c, photo, pr, paint: Paint()..filterQuality = FilterQuality.medium);
    if (shade > 0) c.drawRect(r, Paint()..color = Color.fromRGBO(0, 0, 0, shade));
  }

  void _flip(Canvas c, Size size, int page, double into) {
    paintPaper(c, Offset.zero & size, paper);
    final r = _bookletPage(size);
    final u = size.width / 1080;
    // the booklet's shadow and the edges of the pages below
    c.drawRect(
      r.shift(Offset(10 * u, 16 * u)),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 * u),
    );
    for (var k = 4; k >= 1; k--) {
      c.drawRect(
        r.shift(Offset(3.0 * k * u, 4.0 * k * u)),
        Paint()..color = Color.lerp(const Color(0xFFF1ECE1), const Color(0xFFCFC6B4), k / 4)!,
      );
    }
    // the page beneath, then the one flicking over
    _bookPage(c, r, photos[page]);
    final turning = page > 0 && into < changeMs;
    if (turning) {
      final e = Curves.easeIn.transform(into / changeMs);
      final angle = e * math.pi * 0.62;
      c.save();
      c.translate(r.left, r.center.dy);
      // (as the app's own 3D turns: a little perspective, about the spiral)
      c.transform(
        (Matrix4.identity()
              ..setEntry(3, 2, 0.0011 / u)
              ..rotateY(-angle))
            .storage,
      );
      _bookPage(c, Rect.fromLTWH(0, -r.height / 2, r.width, r.height), photos[page - 1], shade: 0.35 * e);
      c.restore();
      // the turning page's shadow on the one beneath
      c.drawRect(
        Rect.fromLTWH(r.left, r.top, r.width * 0.25 * (1 - e), r.height),
        Paint()
          ..shader = ui.Gradient.linear(r.topLeft, Offset(r.left + r.width * 0.25, r.top), [
            Color.fromRGBO(0, 0, 0, 0.25 * (1 - e)),
            const Color(0x00000000),
          ]),
      );
    }
    _spiral(c, size, r);
  }

  /// Wire coils down the booklet's left edge, through punched holes.
  void _spiral(Canvas c, Size size, Rect r) {
    final u = size.width / 1080;
    const coils = 11;
    final gap = r.height / coils;
    final hole = Paint()..color = const Color(0xFF3A3530);
    for (var i = 0; i < coils; i++) {
      final y = r.top + gap * (i + 0.5);
      // the punched hole in the page
      c.drawCircle(Offset(r.left + 26 * u, y), 9 * u, hole);
      // the wire: round the edge from the hole, dark behind, bright in front
      final coil = Rect.fromCenter(center: Offset(r.left + 2 * u, y), width: 64 * u, height: gap * 0.72);
      c.drawArc(
        coil,
        -math.pi * 0.5,
        -math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9 * u
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF2B2B2E),
      );
      c.drawArc(
        coil,
        -math.pi * 0.5,
        -math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5 * u
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(
            coil.topLeft,
            coil.bottomLeft,
            const [Color(0xFF9A9AA2), Color(0xFFF2F2F5), Color(0xFF6E6E76)],
            const [0, 0.4, 1],
          ),
      );
    }
  }
}
