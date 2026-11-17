import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart';

import 'studio_render.dart';

/// What a stapled flip book sounds like, and when (ms from the loop's start).
enum FlipCue {
  /// A page turning over.
  turn,

  /// The riffle back beginning (the app plays one riffle sound).
  riffle,

  /// One page of the riffle back lifting (the video gives each its own).
  back,
}

/// The stapled flip book (FlipStyle.stapled): a booklet stapled down its
/// left edge. Each page's free corner curls up first, then the page turns
/// over the staples (the spine never moves) and lies face down on the
/// left, over the staples; after the last photo the pile riffles back, the
/// top page first, each landing on the one before. The frame shows half of
/// the left pile. The stacks' edges grow and shrink by a few pixels: the
/// right loses a page as it lifts, the left gains it as it lands.
class StapledFlip {
  StapledFlip({required this.photos, required this.pageMs, required this.flipMs});

  final List<ui.Image> photos;
  final int pageMs;

  /// How long a page takes to turn (the end of its time).
  final int flipMs;

  static const flightMs = 340.0, restMs = 350.0;

  int get length => photos.length;

  /// When each page of the riffle back lifts, from its start: slow, then
  /// quicker, like a thumb letting the pile go. The top page (the last
  /// turned) first.
  late final List<double> riffleStarts = () {
    final out = <double>[];
    var at = 0.0;
    for (var i = 0; i < length - 1; i++) {
      out.add(at);
      at += math.max(45.0, 110.0 - i * 18);
    }
    return out;
  }();

  double get riffleAt => length * pageMs.toDouble();
  double get riffleMs => riffleStarts.isEmpty ? 0 : riffleStarts.last + flightMs;
  double get totalMs => riffleAt + riffleMs + restMs;

  /// The stretches where something moves (drawn at 30 frames a second in
  /// the video; the rest is held).
  List<(double, double)> motion() => [
    for (var i = 0; i < length - 1; i++) ((i + 1) * pageMs - flipMs.toDouble(), (i + 1) * pageMs.toDouble()),
    if (length > 1) (riffleAt, riffleAt + riffleMs),
  ];

  /// The sounds, in order.
  List<(double, FlipCue)> cues() => [
    for (var i = 0; i < length - 1; i++) ((i + 1) * pageMs - flipMs.toDouble(), FlipCue.turn),
    if (length > 1) (riffleAt, FlipCue.riffle),
    for (final s in riffleStarts) (riffleAt + s, FlipCue.back),
  ];

  void paint(Canvas c, Size size, double t, void Function(Canvas, Rect) table) {
    table(c, Offset.zero & size);
    if (photos.isEmpty) return;
    final b = _Booklet(size);
    final n = length;
    final looped = t % totalMs;
    // the stacks' edges: a few pixels at most, by how many pages are there
    final maxT = b.bookW * 0.0075;
    double thick(int pages) => n < 2 || pages <= 1 ? 0 : maxT * (pages - 1) / (n - 1);

    if (looped < riffleAt) {
      final turned = math.min(n - 1, (looped / pageMs).floor());
      final into = looped - turned * pageMs;
      final turning = n > 1 && turned < n - 1 && into >= pageMs - flipMs;
      b.under(c, thick(n - turned - (turning ? 1 : 0)));
      b.flat(c, _front(b, turning ? turned + 1 : turned));
      b.staples(c);
      if (turned > 0) {
        b.leftEdge(c, thick(turned));
        _turn(c, b, turned - 1, math.pi, 0);
      }
      if (turning) {
        final e = ((into - (pageMs - flipMs)) / flipMs).clamp(0.0, 1.0);
        _motion(c, b, turned, e);
      }
    } else {
      final r = looped - riffleAt;
      var onLeft = 0, top = n - 1;
      final flying = <(int, double)>[];
      for (var k = n - 2; k >= 0; k--) {
        final e = ((r - riffleStarts[n - 2 - k]) / flightMs).clamp(0.0, 1.0);
        if (e <= 0) {
          onLeft++;
        } else if (e >= 1) {
          top = k;
        } else {
          flying.add((k, e));
        }
      }
      b.under(c, thick(n - onLeft - flying.length));
      b.flat(c, _front(b, top));
      b.staples(c);
      if (onLeft > 0) {
        b.leftEdge(c, thick(onLeft));
        _turn(c, b, onLeft - 1, math.pi, 0);
      }
      // the one that left first is underneath: it lands first, the next on it
      for (final (k, e) in flying) {
        _motion(c, b, k, 1 - e);
      }
    }
  }

  /// A page's turn, e 0 (flat, right) .. 1 (face down, left): the corner
  /// curls up first and lets go as the page goes over.
  void _motion(Canvas c, _Booklet b, int page, double e) {
    final phi = math.pi * Curves.easeInOut.transform(e);
    final curl = 1.5 * math.sin(math.pi * math.pow(e, 0.7));
    _turn(c, b, page, phi, curl, tilt: 0.65 - 0.4 * e);
  }

  ui.Image _front(_Booklet b, int page) => _PageTextures.of(photos[page], b, back: false);
  ui.Image _back(_Booklet b, int page) => _PageTextures.of(photos[page], b, back: true);

  /// [page] bent in its own plane (the free corner up by [curl], along a
  /// line leaning [tilt], nothing at the spine), then turned about the
  /// spine by [phi] (0 flat on the right, pi face down on the left). Drawn
  /// as a mesh with the page's picture on it, far triangles first.
  void _turn(Canvas c, _Booklet b, int page, double phi, double curl, {double tilt = 0.6}) {
    final face = b.face, hinge = b.hinge;
    final w = face.right - hinge, h = face.height;
    final nx = math.cos(tilt), ny = math.sin(tilt);
    double dOf(double u, double v) => u * nx + (v - h) * ny;
    final dMax = dOf(w, h);
    double ang(double d) => d <= 0 || curl == 0 ? 0 : curl * math.pow(d / dMax, 2.4);
    const nT = 240;
    final xs = Float64List(nT + 1), zs = Float64List(nT + 1);
    final step = dMax / nT;
    for (var i = 1; i <= nT; i++) {
      final a = ang((i - 0.5) * step);
      xs[i] = xs[i - 1] + math.cos(a) * step;
      zs[i] = zs[i - 1] + math.sin(a) * step;
    }
    (double, double) at(double d) {
      if (d <= 0) return (d, 0);
      final f = (d / step).clamp(0.0, nT.toDouble());
      final i = f.floor().clamp(0, nT - 1), r = f - i;
      return (xs[i] + (xs[i + 1] - xs[i]) * r, zs[i] + (zs[i + 1] - zs[i]) * r);
    }

    // columns: two inside the shade beside the spine (so it's drawn as on
    // a page lying flat), then even
    final spine = w * _Booklet.spineShade;
    final us = <double>[0, spine / 2, spine, for (var i = 1; i <= 40; i++) spine + (w - spine) * i / 40];
    const rows = 40;
    final cols = us.length - 1;
    final f = face.width * 2.6;
    final cx = face.center.dx, cy = face.center.dy;
    final count = (cols + 1) * (rows + 1);
    final pos = <Offset>[], tex = <Offset>[], col = <Color>[];
    final zv = Float64List(count);
    final backV = List<bool>.filled(count, false);
    final flat = _shade(0, 0, 1);
    final cp = math.cos(phi), sp = math.sin(phi);
    final tw = _PageTextures.scaleOf(b);
    var idx = 0;
    for (var j = 0; j <= rows; j++) {
      for (var i = 0; i <= cols; i++, idx++) {
        final u = us[i], v = h * j / rows;
        final d = dOf(u, v);
        final (xd, zl) = at(d);
        final x0 = u + (xd - d) * nx, y0 = v + (xd - d) * ny;
        final a = ang(d);
        final lnx = -math.sin(a) * nx, lny = -math.sin(a) * ny, lnz = math.cos(a);
        final x = x0 * cp - zl * sp, z = x0 * sp + zl * cp;
        final nX = lnx * cp - lnz * sp, nZ = lnx * sp + lnz * cp, nY = lny;
        final px = hinge + x, py = face.top + y0;
        final k = f / (f - z);
        pos.add(Offset(cx + (px - cx) * k, cy + (py - cy) * k));
        // texture: the page's picture is face-sized from the face's corner
        tex.add(Offset((hinge - face.left + u) * tw, v * tw));
        zv[idx] = z;
        final back = nZ < 0;
        backV[idx] = back;
        final s = ((back ? _shade(-nX, -nY, -nZ) : _shade(nX, nY, nZ)) / flat).clamp(0.0, 1.0);
        final g = (255 * s).round();
        col.add(Color.fromARGB(255, g, g, g));
      }
    }
    // its shadow on what's beneath, strongest when it's up
    final lifted = math.sin(phi.clamp(0.0, math.pi));
    if (lifted > 0.01) {
      final outline = Path();
      void edge(int i, bool first) =>
          first ? outline.moveTo(pos[i].dx, pos[i].dy) : outline.lineTo(pos[i].dx, pos[i].dy);
      for (var i = 0; i <= cols; i++) {
        edge(i, i == 0);
      }
      for (var j = 1; j <= rows; j++) {
        edge(j * (cols + 1) + cols, false);
      }
      for (var i = cols; i >= 0; i--) {
        edge(rows * (cols + 1) + i, false);
      }
      for (var j = rows; j >= 0; j--) {
        edge(j * (cols + 1), false);
      }
      c.drawPath(
        outline.shift(Offset(face.width * 0.05 * lifted * cp, face.width * 0.06 * lifted)),
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, 0.32 * lifted)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, face.width * 0.035 * (0.3 + lifted)),
      );
    }
    final tris = <(double, int)>[];
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final a0 = j * (cols + 1) + i, b0 = a0 + 1, c0 = a0 + cols + 1, d0 = c0 + 1;
        tris.add(((zv[a0] + zv[b0] + zv[c0]) / 3, a0 * 2));
        tris.add(((zv[b0] + zv[d0] + zv[c0]) / 3, a0 * 2 + 1));
      }
    }
    // (flat: one side, no order to keep)
    if (curl != 0 || (phi != 0 && phi != math.pi)) tris.sort((p, q) => p.$1.compareTo(q.$1));
    final shaders = [
      ImageShader(_front(b, page), TileMode.clamp, TileMode.clamp, Float64List.fromList(_identity)),
      ImageShader(_back(b, page), TileMode.clamp, TileMode.clamp, Float64List.fromList(_identity)),
    ];
    var run = <int>[];
    int? runSide;
    void flush() {
      if (run.isEmpty) return;
      c.drawVertices(
        ui.Vertices(VertexMode.triangles, pos, textureCoordinates: tex, colors: col, indices: run),
        BlendMode.modulate,
        Paint()..shader = shaders[runSide!],
      );
      run = [];
    }

    for (final (_, code) in tris) {
      final a0 = code ~/ 2;
      final b0 = a0 + 1, c0 = a0 + cols + 1, d0 = c0 + 1;
      final t = code.isEven ? [a0, b0, c0] : [b0, d0, c0];
      final side = backV[t[0]] && backV[t[1]] && backV[t[2]] ? 1 : 0;
      if (side != runSide) {
        flush();
        runSide = side;
      }
      run.addAll(t);
    }
    flush();
  }

  static const _identity = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

  /// Light from the top left, above; a sheen where the paper faces the eye.
  static double _shade(double x, double y, double z) {
    const lx = -0.35, ly = -0.45, lz = 0.82;
    final ndl = x * lx + y * ly + z * lz;
    final hz = x * lx * 0.5 + y * ly * 0.5 + z * (lz + 1) * 0.5;
    return 0.55 + 0.5 * ndl.clamp(0.0, 1.0) + math.pow(hz.clamp(0.0, 1.0), 40) * 0.35;
  }
}

/// Where the booklet sits in a frame of [size]: room for half the left pile,
/// the book centred.
class _Booklet {
  _Booklet(Size size) {
    // (in book widths: the half pile + margin to its left, the book, a margin right)
    const crop = 1.428;
    bookW = math.min(size.width * 0.96 / crop, size.height * 0.86 / 1.25);
    final bookH = bookW * 1.25;
    step = bookW * 0.011;
    final faceW = bookW - step * 4, faceH = bookH - step * 3;
    final pageW = faceW * (1 - 0.115);
    final cropW = bookW * crop;
    final cropLeft = (size.width - cropW) / 2;
    final hingeX = cropLeft + bookW * 0.03 + pageW * 0.5;
    final left = hingeX - faceW * 0.115;
    final top = (size.height - bookH) / 2;
    face = Rect.fromLTWH(left, top, faceW, faceH);
    book = Rect.fromLTWH(left, top, bookW, bookH);
  }

  late final double bookW, step;
  late final Rect face, book;

  /// The shade beside the spine, as a share of the page's width.
  static const spineShade = 0.035;

  double get hinge => face.left + face.width * 0.115;
  double get pageW => face.right - hinge;

  Rect get photoRect {
    final fw = face.width;
    return Rect.fromLTRB(
      face.left + fw * 0.17,
      face.top + fw * 0.06,
      face.right - fw * 0.06,
      face.bottom - fw * 0.06,
    );
  }

  /// The book's shadow and the pages under the top one ([thick] px of edge).
  void under(Canvas c, double thick) {
    c.drawRect(
      book.shift(Offset(step * 1.2, step * 2.4)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, step * 3),
    );
    _edge(c, face, thick, right: true);
  }

  /// The edges of the left pile's pages under its top one.
  void leftEdge(Canvas c, double thick) =>
      _edge(c, Rect.fromLTRB(hinge - pageW, face.top, hinge, face.bottom), thick, right: false);

  void _edge(Canvas c, Rect r, double thick, {required bool right}) {
    if (thick <= 0.05) return;
    final e = right
        ? Rect.fromLTRB(r.left, r.top + thick * 0.4, r.right + thick, r.bottom + thick)
        : Rect.fromLTRB(r.left - thick, r.top + thick * 0.4, r.right, r.bottom + thick);
    c.drawRect(e, Paint()..color = const Color(0xFFD8CFBE));
    final line = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = math.max(0.5, step * 0.1);
    for (var k = 1.2; k < thick; k += 1.2) {
      if (right) {
        c.drawLine(Offset(r.left, r.bottom + k), Offset(r.right + k, r.bottom + k), line);
        c.drawLine(Offset(r.right + k, r.top + k * 0.4), Offset(r.right + k, r.bottom + k), line);
      } else {
        c.drawLine(Offset(r.left - k, r.bottom + k), Offset(r.right, r.bottom + k), line);
        c.drawLine(Offset(r.left - k, r.top + k * 0.4), Offset(r.left - k, r.bottom + k), line);
      }
    }
  }

  /// A page lying flat on the right: its picture, as the mesh draws it.
  void flat(Canvas c, ui.Image front) => c.drawImageRect(
    front,
    Offset.zero & Size(front.width.toDouble(), front.height.toDouble()),
    face,
    Paint()..filterQuality = FilterQuality.medium,
  );

  /// The stapled margin and two staples (covered once a page lies on the left).
  void staples(Canvas c) {
    c.drawRect(
      Rect.fromLTRB(face.left, face.top, hinge, face.bottom),
      Paint()
        ..shader = ui.Gradient.linear(Offset(face.left, 0), Offset(hinge, 0), const [
          Color(0xFFEFEADF),
          Color(0xFFE2DBCB),
        ]),
    );
    final x = face.left + face.width * 0.055;
    final wire = math.max(1.2, face.width * 0.014);
    for (final y in [0.24, 0.76]) {
      final a = Offset(x, face.top + face.height * (y - 0.035)),
          b = Offset(x, face.top + face.height * (y + 0.035));
      final round = Paint()
        ..strokeWidth = wire
        ..strokeCap = StrokeCap.round;
      c.drawLine(
        a + Offset(wire * 0.4, wire * 0.5),
        b + Offset(wire * 0.4, wire * 0.5),
        round..color = const Color(0x55000000),
      );
      c.drawLine(a, b, round..color = const Color(0xFFA9ABB2));
      c.drawLine(
        a,
        b,
        round
          ..color = const Color(0xAAFFFFFF)
          ..strokeWidth = wire * 0.35,
      );
    }
  }
}

/// The pages' pictures (front: paper, photo, the shade by the spine; back:
/// paper with the photo faintly through it), drawn once and kept for the
/// few pages in use. Shared by every stapled flip book on screen.
class _PageTextures {
  static const _paper = Color(0xFFF7F4EE), _backPaper = Color(0xFFEDE7DA);
  static final _cache = <String, ui.Image>{};
  static const _keep = 20;

  /// Texture pixels per canvas unit (at most 900 px wide).
  static double scaleOf(_Booklet b) => math.min(2.0, 900 / b.face.width);

  static ui.Image of(ui.Image photo, _Booklet b, {required bool back}) {
    final s = scaleOf(b);
    final w = (b.face.width * s).round(), h = (b.face.height * s).round();
    final key = '${identityHashCode(photo)}:${photo.width}x${photo.height}:$back:${w}x$h';
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.scale(s);
    c.translate(-b.face.left, -b.face.top);
    final face = b.face;
    c.drawRect(face, Paint()..color = back ? _backPaper : _paper);
    drawCover(
      c,
      photo,
      b.photoRect,
      paint: Paint()
        ..filterQuality = FilterQuality.medium
        ..color = back ? const Color(0x14000000) : const Color(0xFF000000),
    );
    if (!back) {
      final hinge = b.hinge, sw = b.pageW * _Booklet.spineShade;
      c.drawRect(
        Rect.fromLTRB(hinge, face.top, hinge + sw, face.bottom),
        Paint()
          ..shader = ui.Gradient.linear(Offset(hinge, 0), Offset(hinge + sw, 0), const [
            Color(0x38000000),
            Color(0x00000000),
          ]),
      );
    }
    final image = rec.endRecording().toImageSync(w, h);
    _cache[key] = image;
    while (_cache.length > _keep) {
      final old = _cache.keys.first;
      _cache.remove(old)!.dispose();
    }
    return image;
  }

  static void clear() {
    for (final i in _cache.values) {
      i.dispose();
    }
    _cache.clear();
  }
}

/// Lets go of the stapled flip books' page pictures (when the last one on
/// screen goes, or after a video is made).
void clearStapledTextures() => _PageTextures.clear();
