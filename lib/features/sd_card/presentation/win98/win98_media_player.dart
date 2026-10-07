import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import 'win98_widgets.dart';
import '../../../../core/device/haptics.dart';

enum _Transport { previous, rewind, play, pause, stop, fastForward, next }

/// "Media Player" for clips on C:: a real transport row instead of tap to
/// play. Holding ◀◀ / ▶▶ scans the tape, with the rolling noise bars and
/// jitter of a cheap VCR searching.
class Win98MediaPlayer extends StatefulWidget {
  const Win98MediaPlayer({super.key, required this.path, this.onPrevious, this.onNext});

  final String path;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  State<Win98MediaPlayer> createState() => _Win98MediaPlayerState();
}

class _Win98MediaPlayerState extends State<Win98MediaPlayer> {
  VideoPlayerController? _c;
  String? _error;

  /// -1 rewinding, +1 fast-forwarding, 0 not scanning.
  int _scan = 0;
  bool _wasPlaying = false;
  bool _stopped = false;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load(play: true));
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    unawaited(_c?.dispose());
    super.dispose();
  }

  /// (Re)opens the clip. Re-opening is also how a finished clip restarts:
  /// Android's player can stay stuck in its "ended" state otherwise.
  Future<void> _load({required bool play}) async {
    final old = _c;
    final c = VideoPlayerController.file(File(widget.path));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _c = c;
        _stopped = !play;
      });
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(old.dispose()));
      if (play) await c.play();
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _error = 'Cannot play this file.\n\nThe file may be damaged.');
    }
  }

  bool _atEnd(VideoPlayerValue v) =>
      v.isCompleted || v.position >= v.duration - const Duration(milliseconds: 250);

  void _press(_Transport t) {
    final c = _c;
    if (c == null) return;
    unawaited(Haptics.selectionClick());
    switch (t) {
      case _Transport.play:
        if (_atEnd(c.value)) {
          unawaited(_load(play: true));
        } else {
          unawaited(c.play());
        }
        setState(() => _stopped = false);
      case _Transport.pause:
        unawaited(c.pause());
      case _Transport.stop:
        unawaited(c.pause().then((_) => c.seekTo(Duration.zero)));
        setState(() => _stopped = true);
      case _Transport.previous:
        widget.onPrevious?.call();
      case _Transport.next:
        widget.onNext?.call();
      case _Transport.rewind || _Transport.fastForward:
        break; // held: see _startScan
    }
  }

  void _startScan(int dir) {
    final c = _c;
    if (c == null || _scan != 0) return;
    _wasPlaying = c.value.isPlaying;
    unawaited(c.pause());
    setState(() {
      _scan = dir;
      _stopped = false;
    });
    // ~8x through the tape, one seek every 90 ms.
    _scanTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      final v = c.value;
      final next = v.position + Duration(milliseconds: 720 * dir);
      if (next <= Duration.zero || next >= v.duration) {
        unawaited(c.seekTo(next <= Duration.zero ? Duration.zero : v.duration));
        _endScan();
        return;
      }
      unawaited(c.seekTo(next));
    });
  }

  void _endScan() {
    if (_scan == 0) return;
    _scanTimer?.cancel();
    _scanTimer = null;
    final c = _c;
    setState(() => _scan = 0);
    if (c != null && _wasPlaying && !_atEnd(c.value)) unawaited(c.play());
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Win98Bevel(
            style: BevelStyle.sunken,
            color: Colors.black,
            padding: const EdgeInsets.all(2),
            child: _error != null
                ? Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: W98.text.copyWith(color: Colors.white),
                    ),
                  )
                : c == null
                ? const SizedBox.expand()
                : Center(
                    child: AspectRatio(
                      aspectRatio: c.value.aspectRatio,
                      child: _TapeScan(scanning: _scan != 0, child: VideoPlayer(c)),
                    ),
                  ),
          ),
        ),
        if (c != null)
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (context, v, _) {
              final total = v.duration.inMilliseconds.clamp(1, 1 << 31);
              final pos = v.position.inMilliseconds.clamp(0, total);
              final playing = v.isPlaying;
              final status = switch (_scan) {
                1 => 'Fast Forward',
                -1 => 'Rewind',
                _ => _stopped ? 'Stopped' : (playing ? 'Playing' : (_atEnd(v) ? 'Finished' : 'Paused')),
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  Win98Slider(
                    value: pos / total,
                    ticks: 20,
                    onChanged: (f) => unawaited(c.seekTo(Duration(milliseconds: (f * total).round()))),
                  ),
                  Row(
                    children: [
                      _Key(glyph: _Transport.previous, onTap: widget.onPrevious == null ? null : _press),
                      _Key(glyph: _Transport.rewind, onHold: _startScan, onRelease: _endScan, dir: -1),
                      _Key(glyph: playing ? _Transport.pause : _Transport.play, onTap: _press, wide: true),
                      _Key(glyph: _Transport.stop, onTap: _press),
                      _Key(glyph: _Transport.fastForward, onHold: _startScan, onRelease: _endScan, dir: 1),
                      _Key(glyph: _Transport.next, onTap: widget.onNext == null ? null : _press),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Win98Bevel(
                          style: BevelStyle.shallow,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Text(status, maxLines: 1),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Win98Bevel(
                        style: BevelStyle.shallow,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text('${_clock(pos)} / ${_clock(total)}'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  static String _clock(int ms) {
    final s = ms ~/ 1000;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

/// One transport key. Tap keys fire on release; scan keys work while held.
class _Key extends StatelessWidget {
  const _Key({required this.glyph, this.onTap, this.onHold, this.onRelease, this.dir = 0, this.wide = false});

  final _Transport glyph;
  final ValueChanged<_Transport>? onTap;
  final ValueChanged<int>? onHold;
  final VoidCallback? onRelease;
  final int dir;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null || onHold != null;
    final button = SizedBox(
      height: 30,
      child: Win98Button(
        padding: EdgeInsets.zero,
        // Scan keys handle their own press-and-hold below.
        onPressed: onTap != null ? () => onTap!(glyph) : (onHold != null ? () {} : null),
        child: Center(
          child: CustomPaint(
            size: const Size(22, 12),
            painter: _GlyphPainter(glyph, enabled ? W98.dark : W98.shadow),
          ),
        ),
      ),
    );
    return Expanded(
      flex: wide ? 3 : 2,
      child: Padding(
        padding: const EdgeInsets.only(right: 2),
        child: onHold == null
            ? button
            : Listener(
                onPointerDown: (_) => onHold!(dir),
                onPointerUp: (_) => onRelease?.call(),
                onPointerCancel: (_) => onRelease?.call(),
                child: button,
              ),
      ),
    );
  }
}

/// Transport symbols drawn as shapes (no font has all of them).
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final _Transport glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final h = size.height, cx = size.width / 2;
    Path tri(double x, double w, {bool left = false}) => left
        ? (Path()
            ..moveTo(x + w, 0)
            ..lineTo(x, h / 2)
            ..lineTo(x + w, h)
            ..close())
        : (Path()
            ..moveTo(x, 0)
            ..lineTo(x + w, h / 2)
            ..lineTo(x, h)
            ..close());
    switch (glyph) {
      case _Transport.play:
        canvas.drawPath(tri(cx - 5, 10), p);
      case _Transport.pause:
        canvas.drawRect(Rect.fromLTWH(cx - 5, 0, 3.5, h), p);
        canvas.drawRect(Rect.fromLTWH(cx + 1.5, 0, 3.5, h), p);
      case _Transport.stop:
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, h / 2), width: h - 1, height: h - 1), p);
      case _Transport.fastForward:
        canvas.drawPath(tri(cx - 8, 8), p);
        canvas.drawPath(tri(cx, 8), p);
      case _Transport.rewind:
        canvas.drawPath(tri(cx - 8, 8, left: true), p);
        canvas.drawPath(tri(cx, 8, left: true), p);
      case _Transport.next:
        canvas.drawPath(tri(cx - 6, 8), p);
        canvas.drawRect(Rect.fromLTWH(cx + 3, 0, 2.5, h), p);
      case _Transport.previous:
        canvas.drawRect(Rect.fromLTWH(cx - 5.5, 0, 2.5, h), p);
        canvas.drawPath(tri(cx - 2, 8, left: true), p);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}

/// A cheap VCR searching: the picture shakes and shears, and bands of
/// snow roll up through it with a bright tracking line.
class _TapeScan extends StatefulWidget {
  const _TapeScan({required this.scanning, required this.child});

  final bool scanning;
  final Widget child;

  @override
  State<_TapeScan> createState() => _TapeScanState();
}

class _TapeScanState extends State<_TapeScan> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((e) => setState(() => _t = e.inMicroseconds / 1e6));
  double _t = 0;
  final _rnd = math.Random();

  @override
  void didUpdateWidget(_TapeScan old) {
    super.didUpdateWidget(old);
    if (widget.scanning && !_ticker.isActive) {
      unawaited(_ticker.start());
    } else if (!widget.scanning && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.scanning) return widget.child;
    final shake = (_rnd.nextDouble() - 0.5) * 6;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform(
            transform: Matrix4.identity()
              ..translateByDouble(shake, 0, 0, 1)
              ..setEntry(0, 1, 0.03 * math.sin(_t * 9)),
            child: widget.child,
          ),
          IgnorePointer(child: CustomPaint(painter: _SnowBands(_t, _rnd.nextInt(1 << 30)))),
        ],
      ),
    );
  }
}

class _SnowBands extends CustomPainter {
  _SnowBands(this.t, this.seed);

  final double t;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final w = size.width, h = size.height;
    // Two noise bands rolling upward at different speeds.
    for (final (speed, height) in [(0.9, 0.14), (1.6, 0.07)]) {
      final y0 = h - ((t * speed * h) % (h * 1.3));
      final bandH = h * height;
      canvas.drawRect(Rect.fromLTWH(0, y0, w, bandH), Paint()..color = const Color(0x55000000));
      for (var i = 0; i < 260; i++) {
        final y = y0 + rnd.nextDouble() * bandH;
        final x = rnd.nextDouble() * w;
        final g = 150 + rnd.nextInt(105);
        canvas.drawRect(
          Rect.fromLTWH(x, y, 2 + rnd.nextDouble() * 14, 1 + rnd.nextDouble() * 1.5),
          Paint()..color = Color.fromARGB(220, g, g, g),
        );
      }
      // Bright tracking line at the band's leading edge.
      canvas.drawRect(Rect.fromLTWH(0, y0, w, 1.5), Paint()..color = const Color(0xCCFFFFFF));
    }
  }

  @override
  bool shouldRepaint(_SnowBands old) => old.t != t;
}
