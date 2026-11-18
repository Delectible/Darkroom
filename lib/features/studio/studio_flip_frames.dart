import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'studio_flip_stapled.dart';
import 'studio_render.dart';

export 'studio_flip_stapled.dart' show FlipCue, StapledFlip, clearStapledTextures;

/// How a flip book goes from one photo to the next.
enum FlipStyle {
  /// A booklet stapled down its left edge: each page's corner curls up and
  /// it turns over the staples onto a pile on the left; after the last
  /// photo the pile riffles back (studio_flip_stapled.dart).
  stapled('Stapled'),

  /// A pad on the table, bound along its top: each page lifts towards you, bends,
  /// and goes over the top onto the pages already turned.
  flip('Page flip'),

  /// Snap cuts: the print flashes white as it changes, the camera shakes.
  shutter('Shutter'),

  /// Each print dropped onto a growing pile, landing a little crooked;
  /// at the end the pile's swept off the table, ready to start again.
  pile('Pile');

  const FlipStyle(this.label);
  final String label;

  static FlipStyle named(String? name) => values.asNameMap()[name] ?? FlipStyle.shutter;

  /// What a new flip book starts with.
  static const standard = FlipStyle.stapled;

  /// The styles the maker offers (the page flip is kept for books made in it).
  static const offered = [stapled, shutter, pile];
}

/// One flip book's moving picture, the same in the app as in the video: its
/// [photos] at [pageMs] each, in [style], on [paper]. [paint] draws the
/// moment [t] ms in; [keyframes] lists the moments the video needs.
class FlipFrames {
  FlipFrames({
    required this.photos,
    required this.paper,
    required this.style,
    required this.pageMs,
    this.crops,
  });

  /// The photos' framing (stapled pages; the maker's preview).
  final List<PhotoCrop>? crops;

  final List<ui.Image> photos;
  final StudioPaper paper;
  final FlipStyle style;
  final int pageMs;

  int get length => photos.length;
  int get totalMs => style == FlipStyle.stapled
      ? _stapled.totalMs.round()
      : length * pageMs + (style == FlipStyle.pile ? clearMs + bareMs : 0);

  late final StapledFlip _stapled = StapledFlip(
    photos: photos,
    pageMs: pageMs,
    flipMs: math.min(pageMs * 0.6, 400.0).round(),
    crops: crops,
  );

  /// Whether [style]'s videos have page sounds.
  static bool hasSound(FlipStyle style) => style == FlipStyle.stapled;

  /// The sounds and when they come (ms into the loop); only the stapled
  /// style has them.
  List<(double, FlipCue)> cues() => style == FlipStyle.stapled ? _stapled.cues() : const [];

  static const _shakeMs = 120, _flashMs = 34;

  /// How long a page's change takes (the flip, the drop).
  int get changeMs => math.min(pageMs * 0.6, style == FlipStyle.pile ? 280.0 : 420.0).round();

  /// After the pile's last print has had its time: the prints swept off
  /// the table, then the table bare for a moment before it starts again.
  static const clearMs = 620, bareMs = 260;

  /// The video's frames: each moment and how long it holds. Changes are
  /// drawn at 30 frames a second, the still parts once.
  List<({double at, double hold})> keyframes() {
    final out = <({double at, double hold})>[];
    if (style == FlipStyle.stapled) {
      // still between the turns; 30 a second while anything moves
      final total = totalMs.toDouble();
      final marks = <double>{0};
      for (final (from, to) in _stapled.motion()) {
        for (var s = from; s < to; s += 1000 / 30) {
          marks.add(s);
        }
        marks.add(to);
      }
      final sorted = marks.where((m) => m < total).toList()..sort();
      for (var i = 0; i < sorted.length; i++) {
        final end = i + 1 < sorted.length ? sorted[i + 1] : total;
        if (end - sorted[i] >= 1) out.add((at: sorted[i], hold: end - sorted[i]));
      }
      return out;
    }
    for (var page = 0; page < length; page++) {
      final start = page * pageMs.toDouble();
      final marks = <double>[0];
      switch (style) {
        case FlipStyle.shutter:
          if (page > 0) marks.add(_flashMs.toDouble());
          for (var s = _shakeMs.toDouble(); s < pageMs; s += _shakeMs) {
            marks.add(s);
          }
        case FlipStyle.flip || FlipStyle.pile || FlipStyle.stapled:
          // (the first page too: it loops round from the last)
          for (var s = 1000 / 30; s < changeMs; s += 1000 / 30) {
            marks.add(s);
          }
          marks.add(changeMs.toDouble());
          if (style == FlipStyle.pile && page == length - 1) {
            for (var s = pageMs.toDouble(); s < pageMs + clearMs; s += 1000 / 30) {
              marks.add(s);
            }
            marks.add(pageMs + clearMs.toDouble());
          }
      }
      // (the pile's last page runs on: the sweep and the bare table)
      final ends = page == length - 1 ? totalMs - start : pageMs.toDouble();
      marks.sort();
      for (var i = 0; i < marks.length; i++) {
        final end = i + 1 < marks.length ? marks[i + 1] : ends;
        if (end - marks[i] < 1) continue;
        out.add((at: start + marks[i], hold: end - marks[i]));
      }
    }
    return out;
  }

  /// The moment [t] ms in (looping).
  void paint(Canvas c, Size size, double t) {
    if (photos.isEmpty) return;
    if (style == FlipStyle.stapled) {
      _stapled.paint(c, size, t, (c, r) => paintPaper(c, r, paper));
      return;
    }
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
      case FlipStyle.stapled:
        break; // (above)
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

  /// The whole pile lying still, no table under it (the book shows shutter
  /// and pile flip books this way): [photos] are the top few, last on top;
  /// [first] is the index of photos[0] in the book (keeps each one's lie).
  void paintPile(Canvas c, Size size, {int first = 0}) {
    final centre = size.center(Offset.zero);
    for (var i = 0; i < length; i++) {
      final k = first + i;
      _card(c, size, photos[i], centre + _pileShift(k, size), turn: _pileTurn(k), fill: 0.78);
    }
  }

  double _pileTurn(int i) => (math.Random(i * 7919 + 13).nextDouble() - 0.5) * 0.22;

  Offset _pileShift(int i, Size size) {
    final r = math.Random(i * 104729 + 7);
    return Offset((r.nextDouble() - 0.5) * size.width * 0.06, (r.nextDouble() - 0.5) * size.height * 0.05);
  }

  void _pile(Canvas c, Size size, int page, double into) {
    paintPaper(c, Offset.zero & size, paper);
    final centre = size.center(Offset.zero);
    // at the very end the pile's swept off to the left, top print first,
    // leaving the bare table the first print drops onto again
    final sweep = page == length - 1 ? ((into - pageMs) / clearMs).clamp(0.0, 1.0) : 0.0;
    if (sweep >= 1) return;
    Offset swept(int fromTop) {
      if (sweep <= 0) return Offset.zero;
      final local = Curves.easeIn.transform(((sweep - fromTop * 0.1) / 0.6).clamp(0.0, 1.0));
      return Offset(-size.width * 1.25 * local, -size.height * 0.05 * local);
    }

    double spun(int fromTop) =>
        sweep <= 0 ? 0 : -0.45 * Curves.easeIn.transform(((sweep - fromTop * 0.1) / 0.6).clamp(0.0, 1.0));

    // the ones beneath (the last few)
    for (var i = math.max(0, page - 4); i < page; i++) {
      _card(
        c,
        size,
        photos[i],
        centre + _pileShift(i, size) + swept(page - i),
        turn: _pileTurn(i) + spun(page - i),
        fill: 0.7,
      );
    }
    // the print landing: held up big, dropped, a touch of turn as it lands
    final q = (into / changeMs).clamp(0.0, 1.0);
    final e = Curves.easeOutBack.transform(q);
    final fall = Curves.easeIn.transform(q);
    _card(
      c,
      size,
      photos[page],
      centre + _pileShift(page, size) + Offset(0, -size.height * 0.08 * (1 - fall)) + swept(0),
      turn: _pileTurn(page) * (0.4 + 0.6 * e) + spun(0),
      scale: 1 + 0.12 * (1 - fall),
      lift: 1 - fall,
      fill: 0.7,
    );
  }

  // ---- page flip: a pad, each page lifted and turned over ----

  /// The pad's top page: bound along its top edge, room above it for the
  /// pages already turned.
  Rect _padPage(Size size) =>
      Rect.fromLTRB(size.width * 0.1, size.height * 0.13, size.width * 0.9, size.height * 0.93);

  /// A page's face: paper, its photo in the middle. [r] is the whole page;
  /// drawn where the canvas is clipped to.
  void _padFace(Canvas c, Rect r, ui.Image photo) {
    c.drawRect(r, Paint()..color = const Color(0xFFFBF8F1));
    final inset = Rect.fromLTRB(
      r.left + r.width * 0.07,
      r.top + r.height * 0.1,
      r.right - r.width * 0.07,
      r.bottom - r.height * 0.06,
    );
    final aspect = photo.width / photo.height;
    var w = inset.width, h = w / aspect;
    if (h > inset.height) {
      h = inset.height;
      w = h * aspect;
    }
    drawCover(
      c,
      photo,
      Rect.fromCenter(center: inset.center, width: w, height: h),
      paint: Paint()..filterQuality = FilterQuality.medium,
    );
  }

  void _flip(Canvas c, Size size, int page, double into) {
    paintPaper(c, Offset.zero & size, paper);
    final r = _padPage(size);
    final u = size.width / 1080;
    // the pages already turned lie above the binding, their backs up
    final turned = Rect.fromLTRB(r.left + 4 * u, r.top - r.height, r.right - 4 * u, r.top);
    c.drawRect(
      turned.shift(Offset(6 * u, 8 * u)),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 * u),
    );
    c.drawRect(turned, Paint()..color = const Color(0xFFEDE7DA));
    // the pad: its shadow on the table, the edges of the pages below
    c.drawRect(
      r.shift(Offset(10 * u, 18 * u)),
      Paint()
        ..color = const Color(0x59000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 20 * u),
    );
    for (var k = 5; k >= 1; k--) {
      c.drawRect(
        Rect.fromLTRB(r.left, r.top, r.right + 2.2 * k * u, r.bottom + 3.2 * k * u),
        Paint()..color = k.isOdd ? const Color(0xFFE9E3D6) : const Color(0xFFCFC6B4),
      );
    }
    // the page beneath
    c.save();
    c.clipRect(r);
    _padFace(c, r, photos[page]);
    c.restore();
    final q = (into / changeMs).clamp(0.0, 1.0);
    if (q < 1 && length > 1) {
      _turningPage(c, size, r, photos[(page - 1 + length) % length], q);
    }
  }

  /// The page going over: lifted from its foot towards you, bowed (the
  /// bound end leads, the foot follows), over the top and down flat on the
  /// turned pages. Drawn in strips, each tilted a little more than the last.
  void _turningPage(Canvas c, Size size, Rect r, ui.Image photo, double q) {
    final e = Curves.easeInOutSine.transform(q);
    final base = e * math.pi;
    final bow = 0.85 * math.sin(math.pi * e); // how bent it is, mid-turn
    const strips = 14;
    final seg = r.height / strips;
    // (the eye two and a half page-lengths above the pad)
    final persp = 0.4 / r.height;

    // its shadow on the page beneath: under the lifted part, darkest at the binding
    final reach = r.height * math.max(0.0, math.cos(base)).clamp(0.0, 1.0);
    if (reach > 1) {
      c.drawRect(
        Rect.fromLTWH(r.left, r.top, r.width, reach),
        Paint()
          ..shader = ui.Gradient.linear(r.topLeft, Offset(r.left, r.top + reach), [
            Color.fromRGBO(0, 0, 0, 0.34 * math.sin(base).clamp(0.0, 1.0) + 0.06),
            const Color(0x00000000),
          ]),
      );
    }

    // the strips' places: each starts where the last ended
    var y = 0.0, z = 0.0;
    final placed = <(double, double, double)>[];
    for (var i = 0; i < strips; i++) {
      final along = (i + 0.5) / strips;
      final angle = (base + bow * (0.5 - along) * 1.6).clamp(0.0, math.pi);
      placed.add((y, z, angle));
      y += seg * math.cos(angle);
      z -= seg * math.sin(angle);
    }
    // far strips first (those furthest from the eye), so near ones cover them
    final order = [for (var i = 0; i < strips; i++) i]..sort((a, b) => placed[b].$2.compareTo(placed[a].$2));
    final hinge = Offset(r.center.dx, r.top);
    final face = Rect.fromLTWH(-r.width / 2, 0, r.width, r.height);
    for (final i in order) {
      final (py, pz, angle) = placed[i];
      final m = Matrix4.translationValues(hinge.dx, hinge.dy, 0)
        ..multiply(Matrix4.identity()..setEntry(3, 2, persp))
        ..multiply(Matrix4.translationValues(0, py, pz))
        ..multiply(Matrix4.rotationX(-angle))
        ..multiply(Matrix4.translationValues(0, -i * seg, 0));
      c.save();
      c.transform(m.storage);
      // (a hair over, so no seams show between strips)
      c.clipRect(Rect.fromLTWH(face.left, i * seg - 0.6, face.width, seg + 1.2));
      final front = math.cos(angle) > 0;
      if (front) {
        _padFace(c, face, photo);
      } else {
        c.drawRect(face, Paint()..color = const Color(0xFFEDE7DA));
      }
      // light: brightest facing up, darker as it stands on edge
      final shade = (front ? 0.24 : 0.18) * math.sin(angle).abs();
      c.drawRect(face, Paint()..color = Color.fromRGBO(0, 0, 0, shade));
      c.restore();
    }
  }
}
