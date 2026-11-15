import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

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
  });

  final StudioWork work;
  final Riffle riffle;
  final Widget? face;

  /// The photos' size for playing (longest side).
  final int cacheWidth;

  @override
  State<FlipBooklet> createState() => _FlipBookletState();
}

class _FlipBookletState extends State<FlipBooklet> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((e) => setState(() => _t = e));
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
    if (widget.riffle == Riffle.loop) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
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
