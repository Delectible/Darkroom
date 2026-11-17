import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/audio/sfx.dart';
import 'studio_flip_frames.dart';
import 'studio_render.dart';
import 'studio_store.dart';

/// How a flip book plays in the app: still, or round and round.
enum Riffle { still, loop }

/// A flip book playing, frame for frame as its video: drawn by the same
/// [FlipFrames] from its photos (kept when it was made). One from before its
/// photos were kept shows its cover, or [face] (its video).
class FlipBooklet extends StatefulWidget {
  const FlipBooklet({
    super.key,
    required this.work,
    this.riffle = Riffle.loop,
    this.face,
    this.cacheWidth = 700,
    this.sound = false,
  });

  final StudioWork work;
  final Riffle riffle;
  final Widget? face;

  /// The photos' size for playing (longest side).
  final int cacheWidth;

  /// Its page sounds as it plays (the stapled style's turns and riffle back).
  final bool sound;

  @override
  State<FlipBooklet> createState() => _FlipBookletState();
}

class _FlipBookletState extends State<FlipBooklet> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((e) {
    _sounds(_t, e);
    setState(() => _t = e);
  });

  /// The cues passed between [from] and [to] (the loop may have wrapped).
  void _sounds(Duration from, Duration to) {
    final frames = _frames;
    if (!widget.sound || frames == null) return;
    final cues = frames.cues();
    if (cues.isEmpty) return;
    final total = frames.totalMs.toDouble();
    final a = from.inMicroseconds / 1000, b = to.inMicroseconds / 1000;
    if (b <= a) return;
    final la = a % total, lb = la + (b - a);
    for (final (at, cue) in cues) {
      final hit = (at > la && at <= lb) || (at + total > la && at + total <= lb);
      if (!hit) continue;
      switch (cue) {
        case FlipCue.turn:
          Sfx.pageTurn();
        case FlipCue.riffle:
          Sfx.flipRiffle.play();
        case FlipCue.back:
          break; // (the riffle sound covers them)
      }
    }
  }

  Duration _t = Duration.zero;
  FlipFrames? _frames;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final w = widget.work;
    if (w.pages.isEmpty) return;
    final images = <ui.Image>[];
    try {
      for (final p in w.pages) {
        images.add(await loadStudioImage(p, maxSide: widget.cacheWidth));
      }
    } catch (_) {
      for (final i in images) {
        i.dispose();
      }
      return;
    }
    if (!mounted) {
      for (final i in images) {
        i.dispose();
      }
      return;
    }
    setState(
      () => _frames = FlipFrames(
        photos: images,
        paper: StudioPaper.values.asNameMap()[w.paper] ?? StudioPaper.cream,
        style: FlipStyle.named(w.flipStyle),
        pageMs: w.pageMs ?? 360,
      ),
    );
    if (widget.sound) {
      for (final s in [...Sfx.pageTurns, Sfx.flipRiffle]) {
        unawaited(s.preload());
      }
    }
    if (widget.riffle == Riffle.loop) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    clearStapledTextures();
    for (final i in _frames?.photos ?? const <ui.Image>[]) {
      i.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = _frames;
    final Widget picture;
    if (widget.face != null) {
      picture = widget.face!;
    } else if (frames != null) {
      picture = CustomPaint(painter: _FramePainter(frames, _t.inMicroseconds / 1000));
    } else if (widget.work.cover != null) {
      picture = Image.file(File(widget.work.cover!), fit: BoxFit.cover, gaplessPlayback: true);
    } else {
      picture = const ColoredBox(color: Color(0xFFF7F4EE));
    }
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: LayoutBuilder(
        builder: (context, box) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(2, 5))],
                  ),
                  child: ClipRect(child: picture),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.frames, this.t);

  final FlipFrames frames;
  final double t;

  @override
  void paint(Canvas canvas, Size size) => frames.paint(canvas, size, t);

  @override
  bool shouldRepaint(_FramePainter old) => old.t != t || !identical(old.frames, frames);
}

/// A flip book as it sits in the album: a little book of prints stapled
/// down its left edge, its pages flicking over one after another, each
/// showing the next photo (whatever style its video plays in: that's seen
/// when it's opened). One from before its photos were kept is the old
/// booklet, still.
class StapledFlipBook extends StatefulWidget {
  const StapledFlipBook({super.key, required this.work, this.still = false});

  final StudioWork work;

  /// Shut, as just made: its first page, nothing flicking.
  final bool still;

  @override
  State<StapledFlipBook> createState() => _StapledFlipBookState();
}

class _StapledFlipBookState extends State<StapledFlipBook> with SingleTickerProviderStateMixin {
  // Drawn again only while a page is flicking over (and once as it comes
  // to rest): lying still between flicks it costs nothing.
  late final Ticker _ticker = createTicker((e) {
    final n = _photos?.length ?? 0;
    if (n < 2) return;
    final pageMs = widget.work.pageMs ?? 360;
    final ms = e.inMicroseconds / 1000;
    final into = ms % pageMs;
    final moving = into < _StapledPainter.flipMsOf(pageMs);
    final phase = moving ? -1 : ms ~/ pageMs;
    if (!moving && phase == _rest) return;
    _rest = phase;
    setState(() => _t = e);
  });
  Duration _t = Duration.zero;
  int _rest = -2;
  List<ui.Image>? _photos;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final images = <ui.Image>[];
    try {
      for (final p in widget.still ? widget.work.pages.take(1) : widget.work.pages) {
        images.add(await loadStudioImage(p, maxSide: widget.still ? 900 : 500));
      }
    } catch (_) {
      // (the old booklet instead)
    }
    if (!mounted || images.isEmpty || (!widget.still && images.length != widget.work.pages.length)) {
      for (final i in images) {
        i.dispose();
      }
      return;
    }
    setState(() => _photos = images);
    if (images.length > 1) unawaited(_ticker.start());
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final i in _photos ?? const <ui.Image>[]) {
      i.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    if (photos == null) {
      // (still loading: nothing; none kept: the booklet as it was)
      return widget.work.pages.isEmpty
          ? FlipBooklet(work: widget.work, riffle: Riffle.still)
          : const AspectRatio(aspectRatio: 4 / 5);
    }
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _StapledPainter(photos, _t.inMicroseconds / 1000, widget.work.pageMs ?? 360),
        ),
      ),
    );
  }
}

class _StapledPainter extends CustomPainter {
  _StapledPainter(this.photos, this.t, this.pageMs);

  final List<ui.Image> photos;
  final double t;
  final int pageMs;

  static const _paper = Color(0xFFF7F4EE);

  /// How long a page takes to flick over.
  static double flipMsOf(int pageMs) => math.min(pageMs * 0.7, 240.0);

  /// A page's face: paper, the stapled margin down its left, its photo.
  void _face(Canvas c, Rect face, ui.Image photo) {
    final fw = face.width;
    c.drawRect(face, Paint()..color = _paper);
    drawCover(
      c,
      photo,
      Rect.fromLTRB(
        face.left + fw * 0.17,
        face.top + fw * 0.06,
        face.right - fw * 0.06,
        face.bottom - fw * 0.06,
      ),
      paint: Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  void paint(Canvas c, Size size) {
    final n = photos.length;
    final step = size.width * 0.011;
    // the top page; the rest of the book shows as edges to its right and below
    final face = Rect.fromLTWH(0, 0, size.width - step * 4, size.height - step * 3);
    c.drawRect(
      Rect.fromLTRB(0, 0, size.width, size.height).shift(Offset(step * 1.2, step * 2.4)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, step * 3),
    );
    for (var k = 4; k >= 1; k--) {
      c.drawRect(
        Rect.fromLTRB(
          face.left,
          face.top + k * step * 0.3,
          face.right + k * step,
          face.bottom + k * step * 0.75,
        ),
        Paint()..color = k.isOdd ? const Color(0xFFE9E3D6) : const Color(0xFFC9BFAB),
      );
    }
    final looped = t % (n * pageMs);
    final page = (looped ~/ pageMs).clamp(0, n - 1);
    final into = looped - page * pageMs;
    final flipMs = flipMsOf(pageMs);
    final q = n > 1 ? (into / flipMs).clamp(0.0, 1.0) : 1.0;
    final hinge = face.left + face.width * 0.115;

    _face(c, face, photos[page]);
    if (q < 1) {
      // The page before, flicked over: swinging up on the staples, quicker
      // as it goes, gone when it's on edge. Its shadow on the page beneath.
      final angle = Curves.easeIn.transform(q) * math.pi / 2;
      final reach = (face.right - hinge) * math.cos(angle);
      c.drawRect(
        Rect.fromLTRB(hinge, face.top, math.min(face.right, hinge + reach * 1.25), face.bottom),
        Paint()
          ..shader = ui.Gradient.linear(Offset(hinge + reach * 0.6, 0), Offset(hinge + reach * 1.25, 0), [
            Color.fromRGBO(0, 0, 0, 0.3 * (1 - q)),
            const Color(0x00000000),
          ]),
      );
      final m = Matrix4.translationValues(hinge, face.center.dy, 0)
        ..multiply(Matrix4.identity()..setEntry(3, 2, 0.3 / face.width))
        ..multiply(Matrix4.rotationY(angle))
        ..multiply(Matrix4.translationValues(-hinge, -face.center.dy, 0));
      c.save();
      c.transform(m.storage);
      c.clipRect(Rect.fromLTRB(hinge, face.top, face.right, face.bottom));
      _face(c, face, photos[(page - 1 + n) % n]);
      c.drawRect(face, Paint()..color = Color.fromRGBO(0, 0, 0, 0.32 * math.sin(angle)));
      c.restore();
    }
    // the stapled edge: pressed down, a crease beside it, two staples
    c.drawRect(
      Rect.fromLTRB(face.left, face.top, hinge, face.bottom),
      Paint()
        ..shader = ui.Gradient.linear(Offset(face.left, 0), Offset(hinge, 0), const [
          Color(0xFFEFEADF),
          Color(0xFFE2DBCB),
        ]),
    );
    c.drawRect(
      Rect.fromLTRB(hinge, face.top, hinge + face.width * 0.035, face.bottom),
      Paint()
        ..shader = ui.Gradient.linear(Offset(hinge, 0), Offset(hinge + face.width * 0.035, 0), const [
          Color(0x38000000),
          Color(0x00000000),
        ]),
    );
    final x = face.left + face.width * 0.055;
    final wire = math.max(1.2, face.width * 0.014);
    for (final y in [0.24, 0.76]) {
      final a = Offset(x, face.top + face.height * (y - 0.035)),
          b = Offset(x, face.top + face.height * (y + 0.035));
      c.drawLine(
        a + Offset(wire * 0.4, wire * 0.5),
        b + Offset(wire * 0.4, wire * 0.5),
        Paint()
          ..color = const Color(0x55000000)
          ..strokeWidth = wire
          ..strokeCap = StrokeCap.round,
      );
      c.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xFFA9ABB2)
          ..strokeWidth = wire
          ..strokeCap = StrokeCap.round,
      );
      c.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xAAFFFFFF)
          ..strokeWidth = wire * 0.35
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_StapledPainter old) => old.t != t || !identical(old.photos, photos);
}
