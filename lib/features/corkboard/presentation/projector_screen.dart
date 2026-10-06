import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/db/media_repository.dart';
import '../../../core/providers.dart';
import '../../cameras/domain/camera_catalog.dart';
import '../../viewer/presentation/media_actions.dart';

/// Super 8 reels play on a home-movie projector: warm beam, running
/// sprocket strips, a footage counter and chunky transport keys.
class ProjectorScreen extends ConsumerStatefulWidget {
  const ProjectorScreen({super.key, required this.reels, required this.initialIndex});

  final List<MediaItem> reels;
  final int initialIndex;

  static Route<void> route(List<MediaItem> reels, int index) => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, _, _) => ProjectorScreen(reels: reels, initialIndex: index < 0 ? 0 : index),
    // Lights go down.
    transitionsBuilder: (context, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeInOut),
      child: child,
    ),
  );

  @override
  ConsumerState<ProjectorScreen> createState() => _ProjectorScreenState();
}

class _ProjectorScreenState extends ConsumerState<ProjectorScreen> with SingleTickerProviderStateMixin {
  late final List<String> _ids = widget.reels.map((m) => m.id).toList();
  late int _index = widget.initialIndex.clamp(0, _ids.length - 1);
  VideoPlayerController? _c;
  String? _error;
  bool _saving = false;

  /// Drives the sprocket strips and the lamp flicker while playing.
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _run.dispose();
    unawaited(_c?.dispose());
    super.dispose();
  }

  MediaItem _item(Map<String, MediaItem> live) =>
      live[_ids[_index]] ?? widget.reels.firstWhere((m) => m.id == _ids[_index]);

  /// Threads the current reel. [rethread] swaps in a fresh player for the same
  /// reel without blanking the screen (used to replay from the end).
  Future<void> _load({bool rethread = false, bool play = true}) async {
    final old = _c;
    if (!rethread) {
      _c = null;
      _error = null;
      if (mounted) setState(() {});
      old?.removeListener(_onTick);
      await old?.dispose();
    }
    final item = widget.reels.firstWhere((m) => m.id == _ids[_index]);
    final path = item.outputPath;
    if (path == null) return;
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_onTick);
      setState(() => _c = c);
      if (rethread && old != null) {
        old.removeListener(_onTick);
        // After the frame, so no widget still listens to the old player.
        WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(old.dispose()));
      }
      if (play) await c.play();
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _error = 'This reel cannot be played.');
    }
  }

  void _onTick() {
    final c = _c;
    if (c == null) return;
    final playing = c.value.isPlaying;
    if (playing && !_run.isAnimating) {
      _run.repeat();
    } else if (!playing && _run.isAnimating) {
      _run.stop();
    }
  }

  void _toggle() {
    final c = _c;
    if (c == null) return;
    unawaited(HapticFeedback.mediumImpact());
    if (c.value.isPlaying) {
      unawaited(c.pause());
    } else if (_atEnd(c.value)) {
      // Android's player can get stuck in its "ended" state, so a reel that
      // ran out would not play again (digital clips loop, so never hit this).
      // Re-threading the reel is the reliable way back to the start.
      unawaited(_load(rethread: true));
    } else {
      unawaited(c.play());
    }
  }

  static bool _atEnd(VideoPlayerValue v) =>
      v.isCompleted || v.position >= v.duration - const Duration(milliseconds: 250);

  void _rewind() {
    final c = _c;
    if (c == null) return;
    unawaited(HapticFeedback.selectionClick());
    if (_atEnd(c.value) && !c.value.isPlaying) {
      unawaited(_load(rethread: true, play: false));
    } else {
      unawaited(c.seekTo(Duration.zero));
    }
  }

  void _step(int d) {
    final next = _index + d;
    if (next < 0 || next >= _ids.length) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _index = next);
    unawaited(_load());
  }

  Future<void> _save(MediaItem item) async {
    if (_saving || item.isSaved) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final err = await keepMedia(ref.read(filmRepositoryProvider), item, album: filmAlbum);
    if (!mounted) return;
    setState(() => _saving = false);
    messenger.showSnackBar(SnackBar(content: Text(err ?? 'Saved to your photo library ($filmAlbum).')));
  }

  Future<void> _delete(MediaItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Throw this reel away?'),
        content: Text(
          item.isSaved
              ? 'The copy in your photo library stays.'
              : 'It has not been saved. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Throw away')),
        ],
      ),
    );
    if (ok != true) return;
    await _c?.pause();
    await deleteMedia(ref.read(filmRepositoryProvider), item);
    if (!mounted) return;
    _ids.remove(item.id);
    if (_ids.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index = _index.clamp(0, _ids.length - 1));
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final live = {for (final m in ref.watch(filmItemsProvider).value ?? widget.reels) m.id: m};
    final item = _item(live);
    final c = _c;

    return Scaffold(
      backgroundColor: const Color(0xFF070605),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white60),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName.replaceAll('.MP4', '').replaceAll('REEL', 'REEL '),
                          style: const TextStyle(
                            color: Color(0xFFF3E3C8),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          '${CameraCatalog.byId(item.cameraId).name} · ${formatDuration(item.durationMs)} · ${MaterialLocalizations.of(context).formatMediumDate(item.capturedAt)}',
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (_ids.length > 1)
                    Text('${_index + 1} / ${_ids.length}', style: const TextStyle(color: Colors.white38)),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: _toggle,
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -300) _step(1);
                  if (v > 300) _step(-1);
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // The beam.
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            radius: 0.75,
                            colors: [Color(0x40FFD9A0), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _SprocketStrip(run: _run),
                        Expanded(
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: c == null
                                  ? Text(
                                      _error ?? 'Threading the film…',
                                      key: ValueKey(_error),
                                      style: const TextStyle(color: Colors.white38),
                                    )
                                  : AspectRatio(
                                      key: ValueKey(_ids[_index]),
                                      aspectRatio: c.value.aspectRatio,
                                      child: DecoratedBox(
                                        decoration: const BoxDecoration(
                                          boxShadow: [
                                            BoxShadow(
                                              color: Color(0x55FFCC88),
                                              blurRadius: 40,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              VideoPlayer(c),
                                              _LampFlicker(run: _run),
                                              ValueListenableBuilder<VideoPlayerValue>(
                                                valueListenable: c,
                                                builder: (context, v, _) => AnimatedOpacity(
                                                  opacity: v.isPlaying ? 0 : 1,
                                                  duration: const Duration(milliseconds: 200),
                                                  child: const ColoredBox(
                                                    color: Color(0x66000000),
                                                    child: Center(
                                                      child: Icon(
                                                        Icons.play_arrow_rounded,
                                                        color: Colors.white70,
                                                        size: 72,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        _SprocketStrip(run: _run),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (c != null)
              _Transport(
                controller: c,
                onToggle: _toggle,
                onRewind: _rewind,
                onPrev: _index > 0 ? () => _step(-1) : null,
                onNext: _index < _ids.length - 1 ? () => _step(1) : null,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Builder(
                    builder: (anchor) => TextButton.icon(
                      onPressed: () => unawaited(shareMedia(anchor, item)),
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('Share'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: item.isSaved
                        ? const TextButton(
                            key: ValueKey('s'),
                            onPressed: null,
                            child: Row(
                              children: [
                                Icon(Icons.check, size: 18, color: Color(0xFFB9E3A0)),
                                SizedBox(width: 6),
                                Text('Saved', style: TextStyle(color: Color(0xFFB9E3A0))),
                              ],
                            ),
                          )
                        : FilledButton.icon(
                            key: const ValueKey('u'),
                            onPressed: _saving ? null : () => _save(item),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFF3E3C8),
                              foregroundColor: const Color(0xFF3B2A1A),
                            ),
                            icon: const Icon(Icons.download, size: 18),
                            label: Text(_saving ? 'Saving…' : 'Save'),
                          ),
                  ),
                  TextButton.icon(
                    onPressed: () => _delete(item),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Throw away'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faint per-frame brightness wobble of a projector lamp.
class _LampFlicker extends StatelessWidget {
  const _LampFlicker({required this.run});

  final Animation<double> run;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: run,
        builder: (context, _) {
          final frame = (run.value * 18).floor();
          final r = math.Random(frame * 7919).nextDouble();
          return ColoredBox(color: Color.fromRGBO(0, 0, 0, run.isAnimating ? 0.02 + r * 0.05 : 0));
        },
      ),
    );
  }
}

/// A strip of film running past the gate, sprocket holes lit by the lamp.
class _SprocketStrip extends StatelessWidget {
  const _SprocketStrip({required this.run});

  final Animation<double> run;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      child: AnimatedBuilder(
        animation: run,
        builder: (context, _) => CustomPaint(
          painter: _SprocketPainter(phase: run.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SprocketPainter extends CustomPainter {
  _SprocketPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1C120B));
    const pitch = 18.0;
    // 18 frames a second, one hole per frame.
    final offset = (phase * 18 * pitch) % pitch;
    final hole = Paint()..color = const Color(0x55FFE2B0);
    for (var y = -pitch + offset; y < size.height + pitch; y += pitch) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(size.width / 2 - 4, y, 8, 10), const Radius.circular(2)),
        hole,
      );
    }
    final edge = Paint()..color = const Color(0x22FFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, 1, size.height), edge);
    canvas.drawRect(Rect.fromLTWH(size.width - 1, 0, 1, size.height), edge);
  }

  @override
  bool shouldRepaint(_SprocketPainter old) => old.phase != phase;
}

/// Footage counter, scrubber and the transport keys.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.controller,
    required this.onToggle,
    required this.onRewind,
    this.onPrev,
    this.onNext,
  });

  final VideoPlayerController controller;
  final VoidCallback onToggle;
  final VoidCallback onRewind;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final total = v.duration.inMilliseconds.clamp(1, 1 << 31);
        final pos = v.position.inMilliseconds.clamp(0, total);
        // Super 8: 72 frames per foot at 18 fps => 4 seconds a foot.
        final feet = (pos / 1000 / 4).floor();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            children: [
              Row(
                children: [
                  _Counter(value: feet),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: const Color(0xFFF3E3C8),
                        inactiveTrackColor: Colors.white12,
                        thumbColor: const Color(0xFFF3E3C8),
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      ),
                      child: Slider(
                        value: pos / total,
                        onChanged: (f) =>
                            unawaited(controller.seekTo(Duration(milliseconds: (f * total).round()))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatDuration(pos),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Key(icon: Icons.skip_previous_rounded, onTap: onPrev),
                  const SizedBox(width: 14),
                  _Key(icon: Icons.replay_rounded, onTap: onRewind),
                  const SizedBox(width: 14),
                  _Key(
                    icon: v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    onTap: onToggle,
                    big: true,
                  ),
                  const SizedBox(width: 14),
                  _Key(icon: Icons.skip_next_rounded, onTap: onNext),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final digits = value.clamp(0, 999).toString().padLeft(3, '0');
    return Row(
      children: [
        const Text('FT ', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1)),
        for (final d in digits.split(''))
          Container(
            width: 16,
            height: 22,
            margin: const EdgeInsets.only(right: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A2A2A), Color(0xFF0E0E0E), Color(0xFF2A2A2A)],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              d,
              style: const TextStyle(color: Color(0xFFF3E3C8), fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.icon, this.onTap, this.big = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final s = big ? 64.0 : 44.0;
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5A5A5A), Color(0xFF1E1E1E)],
            ),
            border: Border.all(color: const Color(0xFF777777), width: 1),
            boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 3))],
          ),
          child: Icon(icon, color: const Color(0xFFF3E3C8), size: big ? 36 : 24),
        ),
      ),
    );
  }
}
