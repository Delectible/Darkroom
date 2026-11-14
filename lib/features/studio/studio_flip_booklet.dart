import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'studio_render.dart';
import 'studio_store.dart';

/// How a booklet moves: still, riffled through now and then (on a page of
/// the book), or flipping round and round (held big).
enum Riffle { still, nowAndThen, loop }

/// A flip book as the thing itself: a clipped booklet of pages, each a print
/// on the book's paper; its pages flick over, the top one swinging away
/// from the binding, the next print flashing as it lands. A flip book from
/// before its pages were kept shows its cover, or [face] (its video).
class FlipBooklet extends StatefulWidget {
  const FlipBooklet({
    super.key,
    required this.work,
    this.riffle = Riffle.still,
    this.pageMs,
    this.face,
    this.cacheWidth = 500,
    this.badge = false,
  });

  final StudioWork work;
  final Riffle riffle;

  /// Time a page; else the flip book's own.
  final int? pageMs;
  final Widget? face;
  final int cacheWidth;

  /// A play mark in the corner (on the book's page: tap to watch).
  final bool badge;

  @override
  State<FlipBooklet> createState() => _FlipBookletState();
}

class _FlipBookletState extends State<FlipBooklet> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _t = Duration.zero;
  (int, int, int)? _shown; // page, turn step, flash: redraw only on change

  List<String> get _pages => widget.work.pages;
  int get _ms => widget.pageMs ?? widget.work.pageMs ?? 360;

  // (riffled now and then: a rest of 6 to 10 s, its own for each book)
  late final int _restMs = 6000 + (widget.work.id.hashCode.abs() % 4000);

  @override
  void initState() {
    super.initState();
    if (widget.riffle != Riffle.still && _pages.length > 1) _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final p in _pages) {
      precacheImage(ResizeImage(FileImage(File(p)), width: widget.cacheWidth), context, onError: (_, _) {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // (looping: where it is, in pages, moved on at the speed of the moment,
  // so a new speed changes the pace and not the page)
  double _pos = 0;

  void _tick(Duration elapsed) {
    _pos += (elapsed - _t).inMicroseconds / 1000 / _ms;
    _t = elapsed;
    final s = _state();
    final key = (s.$1, (s.$2 * 12).floor(), s.$3 ? 1 : 0);
    if (key != _shown) setState(() => _shown = key);
  }

  /// (page, how far the last page has swung away 0..1, flash)
  (int, double, bool) _state() {
    final n = _pages.length;
    if (n < 2 || widget.riffle == Riffle.still) return (0, 1, false);
    var t = _t.inMilliseconds;
    var page = 0;
    if (widget.riffle == Riffle.nowAndThen) {
      // rest on the cover, then one pass through and shut again
      final cycle = _restMs + n * _ms;
      t %= cycle;
      if (t < _restMs) return (0, 1, false);
      t -= _restMs;
      page = (1 + t ~/ _ms) % n;
    } else {
      final whole = _pos.floor();
      if (whole == 0) return (0, 1, false);
      page = whole % n;
      t = ((_pos - whole) * _ms).round();
    }
    final into = t % _ms;
    final turnMs = math.min(_ms * 0.55, 170.0);
    return (page, (into / turnMs).clamp(0.0, 1.0), into < 40);
  }

  Widget _page(int i, {bool flash = false}) {
    final paper = StudioPaper.values.asNameMap()[widget.work.paper] ?? StudioPaper.cream;
    return Stack(
      fit: StackFit.expand,
      children: [
        StudioPaperView(paper: paper),
        Center(
          child: FractionallySizedBox(
            widthFactor: 0.86,
            child: Container(
              padding: const EdgeInsets.all(4),
              color: const Color(0xFFF7F4EE),
              child: Stack(
                children: [
                  Image.file(
                    File(_pages[i]),
                    cacheWidth: widget.cacheWidth,
                    gaplessPlayback: true,
                    // (a print's shape while it loads, not a sliver)
                    frameBuilder: (context, child, frame, sync) => frame == null && !sync
                        ? const AspectRatio(
                            aspectRatio: 4 / 3,
                            child: ColoredBox(color: Color(0xFFE9E2D3)),
                          )
                        : child,
                  ),
                  if (flash) const Positioned.fill(child: ColoredBox(color: Color(0xFFFFFFFF))),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final (page, swing, flash) = _state();
    final n = _pages.length;
    final Widget top;
    Widget? leaving;
    if (widget.face != null) {
      top = widget.face!;
    } else if (n == 0) {
      top = widget.work.cover != null
          ? Image.file(File(widget.work.cover!), fit: BoxFit.cover, cacheWidth: widget.cacheWidth)
          : const ColoredBox(color: Color(0xFFF7F4EE));
    } else {
      top = _page(page, flash: flash);
      if (swing < 1) leaving = _page((page - 1 + n) % n);
    }
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: LayoutBuilder(
        builder: (context, box) {
          final u = box.maxWidth;
          final edge = u * 0.014;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // the pages beneath, their edges showing
              for (var k = 3; k >= 1; k--)
                Positioned.fill(
                  left: edge * k,
                  top: edge * k,
                  right: -edge * k,
                  bottom: -edge * k,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color.lerp(const Color(0xFFF3EEE3), const Color(0xFFDCD3C2), k / 3),
                      borderRadius: BorderRadius.horizontal(right: Radius.circular(u * 0.02)),
                      boxShadow: k == 3
                          ? const [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(2, 5))]
                          : null,
                    ),
                  ),
                ),
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(u * 0.02)),
                  child: top,
                ),
              ),
              // the page flicking over, away from the binding
              if (leaving != null)
                Positioned.fill(
                  child: Transform(
                    alignment: Alignment.centerLeft,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0016)
                      ..rotateY(-swing * math.pi * 0.52),
                    child: ClipRRect(
                      borderRadius: BorderRadius.horizontal(right: Radius.circular(u * 0.02)),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          leaving,
                          ColoredBox(color: Color.fromRGBO(0, 0, 0, 0.25 * swing)),
                        ],
                      ),
                    ),
                  ),
                ),
              // the binding clip
              Positioned(
                left: -u * 0.035,
                top: u * 0.14,
                bottom: u * 0.14,
                width: u * 0.07,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(u * 0.015),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A1A1A), Color(0xFF5E5E5E), Color(0xFF1A1A1A)],
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(1, 2)),
                    ],
                  ),
                ),
              ),
              if (widget.badge)
                Positioned(
                  right: -u * 0.05,
                  bottom: -u * 0.05,
                  child: Container(
                    width: math.max(22, u * 0.2),
                    height: math.max(22, u * 0.2),
                    decoration: const BoxDecoration(
                      color: Color(0xFFD9A35B),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      color: const Color(0xFF22150B),
                      size: math.max(14, u * 0.13),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
