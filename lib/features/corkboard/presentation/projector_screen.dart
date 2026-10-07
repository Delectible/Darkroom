import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/audio/sfx.dart';
import '../../../core/db/media_repository.dart';
import '../../../core/providers.dart';
import '../../cameras/domain/camera_catalog.dart';
import '../../viewer/presentation/media_actions.dart';
import 'reel_painter.dart';

/// Super 8 reels play on a home-movie projector: a warm beam on the screen,
/// and below it the machine's deck: the reel (tap its label tape to rename
/// it), an amber dial for the position, a drum counter for the time left,
/// and a row of chunky piano keys. Only the keys change reels.
///
/// Fast forward and rewind shuttle the film like the real thing: they spin
/// up over a second or so, the picture smears and the frame line rolls
/// while it runs, and it stops at the end of the reel.
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

/// What the transport is doing.
enum ReelShuttle { none, forward, rewind, toStart }

class _ProjectorScreenState extends ConsumerState<ProjectorScreen> with SingleTickerProviderStateMixin {
  late final List<String> _ids = widget.reels.map((m) => m.id).toList();
  late int _index = widget.initialIndex.clamp(0, _ids.length - 1);
  VideoPlayerController? _c;
  String? _error;
  bool _saving = false;

  /// Drives the sprocket strips, lamp flicker and shuttle artefacts.
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  // ---- Shuttle (fast forward / rewind) --------------------------------------
  ReelShuttle _shuttle = ReelShuttle.none;
  Timer? _shuttleTimer;
  final Stopwatch _shuttleClock = Stopwatch();
  Duration _shuttlePos = Duration.zero;

  /// Fast forward / rewind are held: was the reel running when the key went
  /// down? It carries on from the new spot when the key comes up.
  bool _resumeAfterShuttle = false;

  // ---- Seeking --------------------------------------------------------------
  // One seek in flight at a time; while it runs only the newest target is
  // kept. Dragging the needle used to queue dozens of seeks, so the picture
  // lagged a second behind the finger.
  Duration? _seekTarget;

  /// The player a seek is in flight on (a re-threaded reel gets a new one).
  VideoPlayerController? _seekingOn;
  bool get _seekBusy => _seekingOn != null && _seekingOn == _c;

  /// Where the needle sits while a dial seek is catching up.
  Duration? _scrubPos;

  /// Android's player can get stuck after the reel has run out: play() is
  /// accepted but no frames come. Once a reel has ended, playing threads a
  /// fresh player instead. [_watch] catches any other stall the same way.
  bool _ended = false;
  Timer? _watch;
  int _stallRetries = 0;

  /// Current shuttle speed (x real time), for the artefacts.
  double _speed = 0;

  @override
  void initState() {
    super.initState();
    unawaited(Sfx.keyDown.preload());
    unawaited(Sfx.keyUp.preload());
    unawaited(_load());
  }

  @override
  void dispose() {
    _shuttleTimer?.cancel();
    _watch?.cancel();
    _run.dispose();
    unawaited(_c?.dispose());
    super.dispose();
  }

  MediaItem _item(Map<String, MediaItem> live) =>
      live[_ids[_index]] ?? widget.reels.firstWhere((m) => m.id == _ids[_index]);

  /// Threads the current reel. [rethread] swaps in a fresh player for the same
  /// reel without blanking the screen (Android's player can stay stuck in its
  /// "ended" state), starting at [startAt].
  Future<void> _load({bool rethread = false, bool play = true, Duration startAt = Duration.zero}) async {
    final old = _c;
    if (!rethread) {
      _stopShuttle();
      _c = null;
      _error = null;
      if (mounted) setState(() {});
      old?.removeListener(_onTick);
      await old?.dispose();
    }
    final live = {for (final m in ref.read(filmItemsProvider).value ?? widget.reels) m.id: m};
    final path = _item(live).outputPath;
    if (path == null) return;
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      if (startAt > Duration.zero) await c.seekTo(startAt);
      c.addListener(_onTick);
      _ended = false;
      _seekTarget = null;
      _scrubPos = null;
      setState(() => _c = c);
      if (rethread && old != null) {
        old.removeListener(_onTick);
        WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(old.dispose()));
      }
      if (play) {
        await c.play();
        _watchPlayback(c, startAt);
      }
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _error = 'This reel cannot be played.');
    }
  }

  void _onTick() {
    final c = _c;
    if (c == null) return;
    if (c.value.isCompleted) _ended = true;
    final moving = c.value.isPlaying || _shuttle != ReelShuttle.none;
    if (moving && !_run.isAnimating) {
      _run.repeat();
    } else if (!moving && _run.isAnimating) {
      _run.stop();
    }
  }

  void _play() {
    final c = _c;
    if (c == null) return;
    final shuttling = _shuttle != ReelShuttle.none;
    final from = shuttling ? _shuttlePos : (_seekTarget ?? _scrubPos ?? c.value.position);
    _stopShuttle();
    _stallRetries = 0;
    if (from >= c.value.duration - const Duration(milliseconds: 250)) {
      // Ran out: thread it again from the top.
      unawaited(_load(rethread: true));
    } else if (_ended || c.value.isCompleted) {
      unawaited(_load(rethread: true, startAt: from));
    } else {
      unawaited(() async {
        if (shuttling || _seekBusy || _seekTarget != null) {
          _seek(from);
          await _seekSettled();
        }
        if (_c != c) return;
        await c.play();
        _watchPlayback(c, from);
      }());
    }
  }

  /// If the picture hasn't moved a second after play, thread a fresh player
  /// at that spot (see [_ended]).
  void _watchPlayback(VideoPlayerController c, Duration from) {
    _watch?.cancel();
    _watch = Timer(const Duration(milliseconds: 1300), () {
      if (!mounted || _c != c || !c.value.isPlaying || _shuttle != ReelShuttle.none) return;
      if (c.value.position <= from + const Duration(milliseconds: 150) && _stallRetries++ < 1) {
        unawaited(_load(rethread: true, startAt: from));
      }
    });
  }

  /// Seeks to [to], coalescing: only the newest target waits behind the one
  /// in flight.
  void _seek(Duration to) {
    final c = _c;
    if (c == null) return;
    _seekTarget = to;
    if (_seekingOn == c) return;
    _seekingOn = c;
    unawaited(() async {
      try {
        while (_seekTarget != null && _c == c) {
          final t = _seekTarget!;
          _seekTarget = null;
          await c.seekTo(t);
          // The platform call returns at once, but Android's player restarts
          // its decoder on every seek: give it time to put the frame up
          // before asking for the next one, or it never draws any.
          if (_seekTarget != null) await Future<void>.delayed(const Duration(milliseconds: 110));
        }
      } finally {
        if (_seekingOn == c) _seekingOn = null;
        if (_c == c && _seekTarget == null && _scrubPos != null) {
          _scrubPos = null;
          if (mounted) setState(() {});
        }
      }
    }());
  }

  Future<void> _seekSettled() async {
    final give = DateTime.now().add(const Duration(seconds: 3));
    while ((_seekBusy || _seekTarget != null) && DateTime.now().isBefore(give)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  /// The needle was moved on the dial.
  void _scrub(Duration to) {
    _stopShuttle();
    setState(() => _scrubPos = to);
    _seek(to);
  }

  /// A drag on the dial started (true) or ended (false). The reel stops
  /// while the needle is dragged, so each frame gets drawn, and runs on
  /// from the new spot afterwards if it was running.
  bool _resumeAfterScrub = false;
  void _scrubbing(bool active) {
    final c = _c;
    if (c == null) return;
    if (active) {
      _resumeAfterScrub = c.value.isPlaying;
      _watch?.cancel();
      if (_resumeAfterScrub) unawaited(c.pause());
    } else if (_resumeAfterScrub) {
      _resumeAfterScrub = false;
      _play();
    }
  }

  void _togglePlay() {
    final c = _c;
    if (c == null) return;
    unawaited(HapticFeedback.mediumImpact());
    if (c.value.isPlaying && _shuttle == ReelShuttle.none) {
      _watch?.cancel();
      unawaited(c.pause());
    } else {
      _play();
    }
  }

  /// Fast forward / rewind run while their key is held; on release the reel
  /// carries on playing if it was playing before.
  void _hold(ReelShuttle mode, bool down) {
    final c = _c;
    if (c == null) return;
    if (down) {
      if (_shuttle == ReelShuttle.none) _resumeAfterShuttle = c.value.isPlaying;
      _engage(mode);
    } else if (_shuttle == mode) {
      final at = _shuttlePos;
      final resume = _resumeAfterShuttle;
      _stopShuttle(seekTo: at);
      if (resume && at < c.value.duration - const Duration(milliseconds: 250)) _play();
    }
  }

  /// START: one press spools back to the beginning (press again to stop).
  void _toStart() {
    if (_shuttle == ReelShuttle.toStart) {
      unawaited(HapticFeedback.mediumImpact());
      _stopShuttle(seekTo: _shuttlePos);
      return;
    }
    _resumeAfterShuttle = false;
    _engage(ReelShuttle.toStart);
  }

  void _engage(ReelShuttle mode) {
    final c = _c;
    if (c == null || _shuttle == mode) return;
    unawaited(HapticFeedback.mediumImpact());
    _watch?.cancel();
    _scrubPos = null;
    _shuttlePos = _shuttle != ReelShuttle.none ? _shuttlePos : (_seekTarget ?? c.value.position);
    _shuttleTimer?.cancel();
    unawaited(c.pause());
    unawaited(c.setVolume(0));
    _shuttle = mode;
    _shuttleClock
      ..reset()
      ..start();
    _shuttleTimer = Timer.periodic(const Duration(milliseconds: 110), (_) => _shuttleStep());
    _onTick();
    setState(() {});
  }

  void _shuttleStep() {
    final c = _c;
    if (c == null || _shuttle == ReelShuttle.none) return;
    final t = _shuttleClock.elapsedMilliseconds / 1000;
    // The motor spins up: ~2x at once, ~12x after a second or so (rewind to
    // start runs harder).
    final top = _shuttle == ReelShuttle.toStart ? 20.0 : 12.0;
    _speed = 2 + (top - 2) * (1 - math.exp(-t / 0.9));
    final step = Duration(milliseconds: (_speed * 110).round());
    final total = c.value.duration;
    final forward = _shuttle == ReelShuttle.forward;
    var next = forward ? _shuttlePos + step : _shuttlePos - step;
    var done = false;
    if (next <= Duration.zero) {
      next = Duration.zero;
      done = true;
    } else if (next >= total) {
      next = total;
      done = true;
    }
    _shuttlePos = next;
    _seek(next);
    if (done) {
      unawaited(HapticFeedback.heavyImpact()); // the reel runs out / bottoms
      _stopShuttle(seekTo: next);
    }
    if (mounted) setState(() {});
  }

  void _stopShuttle({Duration? seekTo}) {
    if (_shuttle == ReelShuttle.none) return;
    _shuttleTimer?.cancel();
    _shuttleTimer = null;
    _shuttleClock.stop();
    _shuttle = ReelShuttle.none;
    _speed = 0;
    final c = _c;
    if (c != null) {
      unawaited(c.setVolume(1));
      if (seekTo != null) _seek(seekTo);
    }
    _onTick();
    if (mounted) setState(() {});
  }

  void _step(int d) {
    final next = _index + d;
    if (next < 0 || next >= _ids.length) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _index = next);
    unawaited(_load());
  }

  Future<void> _rename(MediaItem item) async {
    final text = TextEditingController(text: reelLabel(item));
    const tape = Color(0xFFF6F0DC), ink = Color(0xFF1F2A5A);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(useMaterial3: true).copyWith(
          colorScheme: const ColorScheme.light(primary: ink, onPrimary: tape, surface: tape, onSurface: ink),
        ),
        child: AlertDialog(
          backgroundColor: tape,
          title: const Text('Label this reel', style: TextStyle(color: ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: text,
                autofocus: true,
                maxLength: maxReelLabel,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                  color: ink,
                  fontSize: 22,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  hintText: 'Lake trip \'26',
                  hintStyle: TextStyle(color: ink.withValues(alpha: 0.3), fontStyle: FontStyle.italic),
                  counterStyle: TextStyle(color: ink.withValues(alpha: 0.6)),
                ),
                onSubmitted: (v) => Navigator.pop(context, v),
              ),
              if (item.isSaved)
                Text(
                  'The copy already in your photo library keeps its old name.',
                  style: TextStyle(color: ink.withValues(alpha: 0.6), fontSize: 12),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, text.text), child: const Text('Label')),
          ],
        ),
      ),
    );
    text.dispose();
    if (label == null || !mounted) return;
    final used = await renameReel(ref.read(filmRepositoryProvider), item, label);
    if (used == null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Write a name on the label first.')));
    }
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
    _stopShuttle();
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
                          reelLabel(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF3E3C8),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          '${CameraCatalog.byId(item.cameraId).name} · ${formatDuration(item.durationMs)} · '
                          '${MaterialLocalizations.of(context).formatMediumDate(item.capturedAt)}',
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
            // The screen. Everything is on the deck's keys: no taps or swipes.
            Expanded(
              child: IgnorePointer(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
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
                        _SprocketStrip(run: _run, speed: _shuttle == ReelShuttle.none ? 1 : _speed),
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
                                  : _Picture(
                                      key: ValueKey(_ids[_index]),
                                      controller: c,
                                      run: _run,
                                      shuttle: _shuttle == ReelShuttle.none ? 0 : _speed,
                                    ),
                            ),
                          ),
                        ),
                        _SprocketStrip(run: _run, speed: _shuttle == ReelShuttle.none ? 1 : _speed),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (c != null)
              ProjectorDeck(
                playback: c,
                item: item,
                run: _run,
                shuttle: _shuttle,
                cuePos: _shuttle == ReelShuttle.none ? _scrubPos : _shuttlePos,
                onRename: () => _rename(item),
                onSeek: _scrub,
                onScrub: _scrubbing,
                onStart: _toStart,
                onRewind: (down) => _hold(ReelShuttle.rewind, down),
                onPlay: _togglePlay,
                onForward: (down) => _hold(ReelShuttle.forward, down),
                onPrev: _index > 0 ? () => _step(-1) : null,
                onNext: _index < _ids.length - 1 ? () => _step(1) : null,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
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

/// The projected picture: lamp flicker, a pause veil, and while shuttling
/// the smear of film racing through the gate and the frame line rolling.
class _Picture extends StatelessWidget {
  const _Picture({super.key, required this.controller, required this.run, required this.shuttle});

  final VideoPlayerController controller;
  final Animation<double> run;

  /// Shuttle speed (x real time); 0 when playing normally.
  final double shuttle;

  @override
  Widget build(BuildContext context) {
    final s = shuttle;
    Widget video = VideoPlayer(controller);
    if (s > 0) {
      // Motion smear along the film's travel, colour washing out.
      video = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 0.4, sigmaY: 1.5 + s * 0.35, tileMode: TileMode.decal),
        child: ColorFiltered(colorFilter: _desaturate(math.min(0.6, s * 0.05)), child: video),
      );
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [BoxShadow(color: Color(0x55FFCC88), blurRadius: 40, spreadRadius: 2)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              video,
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: run,
                  builder: (context, _) => CustomPaint(
                    painter: _GatePainter(phase: run.value, running: run.isAnimating, shuttle: s),
                  ),
                ),
              ),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, v, _) => AnimatedOpacity(
                  opacity: v.isPlaying || s > 0 ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: const ColoredBox(color: Color(0x55000000)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static ColorFilter _desaturate(double amount) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final s = 1 - amount;
    final i = 1 - s;
    return ColorFilter.matrix([
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0, //
      r * i, g * i, b * i + s, 0, 0, //
      0, 0, 0, 1, 0,
    ]);
  }
}

/// Lamp flicker always; while shuttling, a harder flicker and the dark frame
/// line rolling through the picture (the film outruns the shutter).
class _GatePainter extends CustomPainter {
  _GatePainter({required this.phase, required this.running, required this.shuttle});

  final double phase;
  final bool running;
  final double shuttle;

  @override
  void paint(Canvas canvas, Size size) {
    if (!running) return;
    final frame = (phase * 18).floor();
    final r = math.Random(frame * 7919).nextDouble();
    final flicker = shuttle > 0 ? 0.06 + r * 0.16 : 0.02 + r * 0.05;
    canvas.drawRect(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, flicker));
    if (shuttle <= 0) return;
    // Frame line(s) rolling: faster film, faster roll.
    final bar = size.height * 0.07;
    final travel = (phase * shuttle * 0.9) % 1.0;
    for (final k in [0.0, 0.5]) {
      final y = ((travel + k) % 1.0) * (size.height + bar) - bar;
      final rect = Rect.fromLTWH(0, y, size.width, bar);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0xCC000000), Color(0xCC000000), Color(0x00000000)],
            stops: [0, 0.35, 0.65, 1],
          ).createShader(rect),
      );
    }
    // Specks of dust streaking past.
    final rnd = math.Random(frame * 31 + 7);
    final dust = Paint()
      ..color = const Color(0x99FFF4E0)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final x = rnd.nextDouble() * size.width, y = rnd.nextDouble() * size.height;
      canvas.drawLine(Offset(x, y), Offset(x, y + 6 + shuttle * 2), dust);
    }
  }

  @override
  bool shouldRepaint(_GatePainter old) =>
      old.phase != phase || old.running != running || old.shuttle != shuttle;
}

/// A strip of film running past the gate, sprocket holes lit by the lamp.
class _SprocketStrip extends StatelessWidget {
  const _SprocketStrip({required this.run, required this.speed});

  final Animation<double> run;
  final double speed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      child: AnimatedBuilder(
        animation: run,
        builder: (context, _) => CustomPaint(
          painter: _SprocketPainter(phase: run.value, speed: speed),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SprocketPainter extends CustomPainter {
  _SprocketPainter({required this.phase, required this.speed});

  final double phase;
  final double speed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1C120B));
    const pitch = 18.0;
    // 18 frames a second, one hole per frame (faster while shuttling).
    final offset = (phase * 18 * pitch * speed) % pitch;
    final hole = Paint()..color = const Color(0x55FFE2B0);
    for (var y = -pitch + offset; y < size.height + pitch; y += pitch) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width / 2 - 4, y, 8, speed > 3 ? 10 + speed : 10),
          const Radius.circular(2),
        ),
        hole,
      );
    }
    final edge = Paint()..color = const Color(0x22FFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, 1, size.height), edge);
    canvas.drawRect(Rect.fromLTWH(size.width - 1, 0, 1, size.height), edge);
  }

  @override
  bool shouldRepaint(_SprocketPainter old) => old.phase != phase || old.speed != speed;
}

// ---------------------------------------------------------------------------
// The deck
// ---------------------------------------------------------------------------

const _panelTop = Color(0xFF2B211A);
const _panelBottom = Color(0xFF17110D);
const _amber = Color(0xFFFFB347);
const _cream = Color(0xFFF3E3C8);

/// The projector's control deck: reel + label, dial, counter, keys.
/// Reads [playback] (the reel's player, or a stand-in in tests).
class ProjectorDeck extends StatelessWidget {
  const ProjectorDeck({
    super.key,
    required this.playback,
    required this.item,
    required this.run,
    required this.shuttle,
    required this.cuePos,
    required this.onRename,
    required this.onSeek,
    this.onScrub,
    required this.onStart,
    required this.onRewind,
    required this.onPlay,
    required this.onForward,
    this.onPrev,
    this.onNext,
  });

  final ValueListenable<VideoPlayerValue> playback;
  final MediaItem item;
  final Animation<double> run;
  final ReelShuttle shuttle;

  /// Where the needle and counter should read instead of the player's own
  /// position: the shuttle's spot, or a dial seek still catching up.
  final Duration? cuePos;
  final VoidCallback onRename;
  final ValueChanged<Duration> onSeek;

  /// A drag on the dial started (true) / ended (false).
  final ValueChanged<bool>? onScrub;
  final VoidCallback onStart, onPlay;

  /// Rewind / fast forward key went down (true) or came up (false).
  final ValueChanged<bool> onRewind, onForward;
  final VoidCallback? onPrev, onNext;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: playback,
      builder: (context, v, _) {
        final total = v.duration;
        final pos = cuePos ?? v.position;
        final frac = total.inMilliseconds <= 0
            ? 0.0
            : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
        final left = total - pos;
        final playing = v.isPlaying && shuttle == ReelShuttle.none;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_panelTop, _panelBottom],
            ),
            border: Border.all(color: const Color(0xFF4A3A2C)),
            boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // The reel on its spindle; tap the label tape to rename.
                  Semantics(
                    button: true,
                    label: 'Rename this reel',
                    child: GestureDetector(
                      onTap: onRename,
                      child: SizedBox.square(
                        dimension: 92,
                        child: CustomPaint(
                          painter: ReelPainter(
                            rotation: 0,
                            spin: -pos.inMilliseconds / 1000 * math.pi * 0.9,
                            label: '', // the tape on the deck carries the name
                            duration: '',
                            saved: item.isSaved,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LabelTape(text: reelLabel(item), onTap: onRename),
                        const SizedBox(height: 8),
                        _Dial(
                          fraction: frac,
                          total: total,
                          onSeek: (f) => onSeek(Duration(milliseconds: (f * total.inMilliseconds).round())),
                          onScrub: onScrub,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              shuttle == ReelShuttle.none
                                  ? (playing ? 'RUNNING' : 'STOPPED')
                                  : (shuttle == ReelShuttle.forward ? 'FAST FWD' : 'REWIND'),
                              style: TextStyle(
                                color: shuttle == ReelShuttle.none && !playing ? Colors.white38 : _amber,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              'TIME LEFT ',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                              ),
                            ),
                            _DrumCounter(remaining: left),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _PianoKey(
                    symbol: _Sym.toStart,
                    label: 'START',
                    onTap: onStart,
                    latched: shuttle == ReelShuttle.toStart,
                  ),
                  _PianoKey(symbol: _Sym.prev, label: 'PREV', onTap: onPrev),
                  _PianoKey(
                    symbol: _Sym.rewind,
                    label: 'REW',
                    onHold: onRewind,
                    latched: shuttle == ReelShuttle.rewind,
                  ),
                  _PianoKey(
                    symbol: playing ? _Sym.pause : _Sym.play,
                    label: playing ? 'PAUSE' : 'PLAY',
                    onTap: onPlay,
                    latched: playing,
                    flex: 3,
                  ),
                  _PianoKey(
                    symbol: _Sym.forward,
                    label: 'F.FWD',
                    onHold: onForward,
                    latched: shuttle == ReelShuttle.forward,
                  ),
                  _PianoKey(symbol: _Sym.next, label: 'NEXT', onTap: onNext),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A strip of masking tape on the deck with the reel's name in marker;
/// tap to rename the reel (and its file).
class _LabelTape extends StatelessWidget {
  const _LabelTape({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1F2A5A);
    return Semantics(
      button: true,
      label: 'Rename this reel',
      child: GestureDetector(
        onTap: onTap,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Transform.rotate(
            angle: -0.012,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
              decoration: const BoxDecoration(
                color: Color(0xFFF1E8CC),
                boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(1, 1.5))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.edit, size: 13, color: ink.withValues(alpha: 0.45)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Backlit amber dial with a minute scale and a red needle; drag or tap it
/// to wind the film to a point.
class _Dial extends StatelessWidget {
  const _Dial({required this.fraction, required this.total, required this.onSeek, this.onScrub});

  final double fraction;
  final Duration total;
  final ValueChanged<double> onSeek;
  final ValueChanged<bool>? onScrub;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        void seekAt(double dx) => onSeek(((dx - 8) / (box.maxWidth - 16)).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekAt(d.localPosition.dx),
          onHorizontalDragStart: (d) {
            onScrub?.call(true);
            seekAt(d.localPosition.dx);
          },
          onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
          onHorizontalDragEnd: (_) => onScrub?.call(false),
          onHorizontalDragCancel: () => onScrub?.call(false),
          child: SizedBox(
            height: 40,
            child: CustomPaint(
              painter: _DialPainter(fraction: fraction, seconds: total.inMilliseconds / 1000),
            ),
          ),
        );
      },
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.fraction, required this.seconds});

  final double fraction;
  final double seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    // Recessed window, lit from behind.
    canvas.drawRRect(r, Paint()..color = const Color(0xFF0C0806));
    canvas.drawRRect(
      r.deflate(2),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5A3A12), Color(0xFF8A5A1C), Color(0xFF4A2E0E)],
        ).createShader(r.outerRect),
    );
    final x0 = 8.0, x1 = size.width - 8;
    double xAt(double f) => x0 + (x1 - x0) * f;
    // Ticks: every 10 s, longer each minute, numbered in minutes.
    final tick = Paint()
      ..color = const Color(0xFF1C1206)
      ..strokeWidth = 1;
    final secs = math.max(1.0, seconds);
    final step = secs > 150 ? 20.0 : 10.0;
    for (var t = 0.0; t <= secs + 0.01; t += step) {
      final x = xAt(t / secs);
      final minute = (t % 60).abs() < 0.01;
      canvas.drawLine(Offset(x, 4), Offset(x, minute ? 16 : 10), tick..strokeWidth = minute ? 1.6 : 1);
      if (minute) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${(t / 60).round()}',
            style: const TextStyle(color: Color(0xFF1C1206), fontSize: 10, fontWeight: FontWeight.w800),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 18));
      }
    }
    // Played part of the scale, warmer.
    canvas.drawRect(
      Rect.fromLTRB(x0, size.height - 9, xAt(fraction), size.height - 6),
      Paint()..color = const Color(0xAAFFD58A),
    );
    // Needle.
    final nx = xAt(fraction);
    canvas.drawLine(
      Offset(nx, 3),
      Offset(nx, size.height - 3),
      Paint()
        ..color = const Color(0xFFD7261E)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    // Glass glare.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 2, size.width - 4, size.height * 0.35),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0x14FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.fraction != fraction || old.seconds != seconds;
}

/// Mechanical drum counter: each digit rolls over as it changes.
class _DrumCounter extends StatelessWidget {
  const _DrumCounter({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final s = math.max(0, (remaining.inMilliseconds / 1000).ceil());
    final text = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(3)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, ch) in text.split('').indexed)
            ch == ':'
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 1),
                    child: Text(
                      ':',
                      style: TextStyle(color: _cream, fontWeight: FontWeight.w800),
                    ),
                  )
                : _Drum(key: ValueKey(i), digit: ch),
        ],
      ),
    );
  }
}

class _Drum extends StatelessWidget {
  const _Drum({super.key, required this.digit});

  final String digit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 15,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E0E0E), Color(0xFF2E2E2E), Color(0xFF0E0E0E)],
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, a) => SlideTransition(
          position: Tween(begin: const Offset(0, 0.9), end: Offset.zero).animate(a),
          child: child,
        ),
        layoutBuilder: (current, previous) =>
            Stack(alignment: Alignment.center, children: [...previous, ?current]),
        child: Text(
          digit,
          key: ValueKey(digit),
          style: const TextStyle(color: _cream, fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
    );
  }
}

enum _Sym { toStart, prev, rewind, play, pause, forward, next }

/// A chunky piano key on the deck: travels down when pressed and stays down
/// while it's latched (playing, shuttling).
class _PianoKey extends StatefulWidget {
  const _PianoKey({
    required this.symbol,
    required this.label,
    this.onTap,
    this.onHold,
    this.latched = false,
    this.flex = 2,
  });

  final _Sym symbol;
  final String label;
  final VoidCallback? onTap;

  /// Held keys (rewind / fast forward): true on press, false on release.
  final ValueChanged<bool>? onHold;
  final bool latched;
  final int flex;

  @override
  State<_PianoKey> createState() => _PianoKeyState();
}

class _PianoKeyState extends State<_PianoKey> {
  bool _down = false;

  void _release() {
    if (!_down) return;
    Sfx.keyUp.play();
    setState(() => _down = false);
    widget.onHold?.call(false);
  }

  @override
  void dispose() {
    if (_down) widget.onHold?.call(false);
    super.dispose();
  }

  /// Tap keys fire on release; held keys run from press to release (a raw
  /// Listener, so sliding a finger off doesn't cut a hold short).
  Widget _press({required bool enabled, required Widget child}) {
    if (!enabled) return child;
    final hold = widget.onHold;
    if (hold != null) {
      return Listener(
        onPointerDown: (_) {
          if (_down) return;
          Sfx.keyDown.play();
          setState(() => _down = true);
          hold(true);
        },
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: child,
      );
    }
    return GestureDetector(
      onTapDown: (_) {
        Sfx.keyDown.play();
        setState(() => _down = true);
      },
      onTapCancel: () {
        Sfx.keyUp.play();
        setState(() => _down = false);
      },
      onTapUp: (_) {
        Sfx.keyUp.play();
        setState(() => _down = false);
        widget.onTap!();
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onHold != null;
    final pressed = _down || widget.latched;
    final travel = _down ? 5.0 : (widget.latched ? 3.5 : 0.0);
    return Expanded(
      flex: widget.flex,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.label,
        child: _press(
          enabled: enabled,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Column(
                children: [
                  // Key well.
                  Container(
                    height: 62,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0806),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 70),
                      margin: EdgeInsets.only(top: travel, bottom: 6 - math.min(travel, 6.0)),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: pressed
                              ? const [Color(0xFFB9B6AE), Color(0xFF8E8B84)]
                              : const [Color(0xFFE9E6DE), Color(0xFFB7B3AA)],
                        ),
                        border: Border.all(color: const Color(0xFF5C574F), width: 0.8),
                        boxShadow: pressed
                            ? null
                            : const [BoxShadow(color: Color(0xFF6E685F), offset: Offset(0, 4))],
                      ),
                      child: Stack(
                        children: [
                          // Satin highlight on the key's top edge.
                          Positioned(
                            left: 3,
                            right: 3,
                            top: 2,
                            height: 3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: pressed ? 0.15 : 0.5),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Center(
                            child: CustomPaint(
                              size: Size(widget.flex > 2 ? 30 : 24, 18),
                              painter: _SymbolPainter(widget.symbol, latchedLamp: widget.latched),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xFFBFAF96),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Transport symbols printed on the keys (and a small lamp on latched ones).
class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.symbol, {this.latchedLamp = false});

  final _Sym symbol;
  final bool latchedLamp;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF1C1A17);
    final h = size.height, w = size.width;
    final cy = h / 2;
    Path tri(double x, double width, {required bool right}) => Path()
      ..moveTo(right ? x : x + width, cy - h * 0.38)
      ..lineTo(right ? x + width : x, cy)
      ..lineTo(right ? x : x + width, cy + h * 0.38)
      ..close();
    void bar(double x) => canvas.drawRect(Rect.fromLTWH(x, cy - h * 0.38, 2.6, h * 0.76), p);
    final t = h * 0.62; // triangle width
    switch (symbol) {
      case _Sym.play:
        canvas.drawPath(tri(w / 2 - t / 2, t, right: true), p);
      case _Sym.pause:
        canvas.drawRect(Rect.fromLTWH(w / 2 - 6, cy - h * 0.38, 4, h * 0.76), p);
        canvas.drawRect(Rect.fromLTWH(w / 2 + 2, cy - h * 0.38, 4, h * 0.76), p);
      case _Sym.forward:
        canvas.drawPath(tri(w / 2 - t, t, right: true), p);
        canvas.drawPath(tri(w / 2, t, right: true), p);
      case _Sym.rewind:
        canvas.drawPath(tri(w / 2 - t, t, right: false), p);
        canvas.drawPath(tri(w / 2, t, right: false), p);
      case _Sym.toStart:
        bar(w / 2 - t - 3);
        canvas.drawPath(tri(w / 2 - t, t, right: false), p);
        canvas.drawPath(tri(w / 2, t, right: false), p);
      case _Sym.next:
        canvas.drawPath(tri(w / 2 - t / 2 - 2, t, right: true), p);
        bar(w / 2 + t / 2 - 1);
      case _Sym.prev:
        bar(w / 2 - t / 2 - 2);
        canvas.drawPath(tri(w / 2 - t / 2 + 1, t, right: false), p);
    }
    if (latchedLamp) {
      canvas.drawCircle(
        Offset(w + 3, -1),
        2.2,
        Paint()
          ..color = _amber
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2),
      );
    }
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.symbol != symbol || old.latchedLamp != latchedLamp;
}
