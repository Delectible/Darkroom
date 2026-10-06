import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/media_repository.dart';
import '../../../core/providers.dart';
import '../../../core/shaders/shader_library.dart';
import '../../cameras/domain/camera_catalog.dart';
import '../../viewer/presentation/media_actions.dart';
import 'instant_print.dart';
import 'print_viewer.dart';
import 'projector_screen.dart';
import 'reel_painter.dart';

/// Film gallery: developed prints and Super 8 reels pinned to a cork board,
/// with the darkroom (still developing) in a red safelight strip on top.
///
/// Nothing reaches the phone's photo library until it is saved — per print,
/// or with "Save all".
class CorkboardScreen extends ConsumerStatefulWidget {
  const CorkboardScreen({super.key});

  @override
  ConsumerState<CorkboardScreen> createState() => _CorkboardScreenState();
}

class _CorkboardScreenState extends ConsumerState<CorkboardScreen> {
  bool _saving = false;

  /// Pin-in animations only play as the board opens and for prints that come
  /// out of the darkroom while it is open. Prints scrolled into view appear
  /// at once (they used to fade in late, leaving blank gaps).
  final DateTime _openedAt = DateTime.now();

  bool _animatePin(MediaItem m, int index) =>
      m.readyAt.isAfter(_openedAt) ||
      (index < 12 && DateTime.now().difference(_openedAt) < const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    // Looking at the board clears "new print" badges and the notification.
    Future.microtask(() => ref.read(darkroomEngineProvider).markSeen());
  }

  Future<void> _saveAll(List<MediaItem> developed) async {
    final todo = developed.where((m) => !m.isSaved).toList();
    if (todo.isEmpty || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(filmRepositoryProvider);
    var ok = 0;
    String? error;
    for (final m in todo) {
      final err = await keepMedia(repo, m, album: filmAlbum);
      if (err == null) {
        ok++;
      } else {
        error ??= err;
        if (err.contains('denied')) break;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    unawaited(HapticFeedback.lightImpact());
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? 'Saved $ok to your photo library ($filmAlbum).'
              : 'Saved $ok of ${todo.length}. $error',
        ),
      ),
    );
  }

  void _open(BuildContext context, List<MediaItem> developed, MediaItem item) {
    final reels = developed.where((m) => m.isVideo).toList();
    final prints = developed.where((m) => !m.isVideo).toList();
    final route = item.isVideo
        ? ProjectorScreen.route(reels, reels.indexOf(item))
        : PrintViewerScreen.route(prints, prints.indexOf(item));
    Navigator.of(context).push(route);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(filmItemsProvider).value ?? const <MediaItem>[];
    final now = ref.watch(secondTickerProvider).value ?? DateTime.now();
    final developed = items.where((m) => m.isDevelopedAt(now)).toList();
    final inDarkroom = items.where((m) => !m.isDevelopedAt(now)).toList()
      ..sort((a, b) => a.readyAt.compareTo(b.readyAt));
    final unsaved = developed.where((m) => !m.isSaved).length;

    // Prints that came out while the board is open are "seen" too.
    ref.listen(filmItemsProvider, (prev, next) {
      final unseen = next.value?.any((m) => m.isDevelopedAt(DateTime.now()) && !m.seen) ?? false;
      if (unseen) unawaited(ref.read(darkroomEngineProvider).markSeen());
    });

    return Scaffold(
      backgroundColor: const Color(0xFF4A3220),
      body: Stack(
        children: [
          const Positioned.fill(child: _CorkBackground()),
          SafeArea(
            child: CustomScrollView(
              // Build (and decode) prints well before they scroll into view.
              scrollCacheExtent: const ScrollCacheExtent.viewport(1.5),
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    onBack: () => Navigator.of(context).pop(),
                    unsaved: unsaved,
                    total: developed.length,
                    saving: _saving,
                    onSaveAll: () => _saveAll(developed),
                  ),
                ),
                if (inDarkroom.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _DarkroomStrip(items: inDarkroom, now: now),
                  ),
                if (developed.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: _EmptyBoard())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisSpacing: 26,
                        crossAxisSpacing: 22,
                        childAspectRatio: 0.78,
                      ),
                      delegate: SliverChildBuilderDelegate(childCount: developed.length, (context, i) {
                        final m = developed[i];
                        void open() => _open(context, developed, m);
                        final child = m.isVideo
                            ? PinnedReel(item: m, onOpen: open)
                            : CameraCatalog.byId(m.cameraId).isInstant
                            ? PinnedInstant(item: m, onOpen: open)
                            : PinnedPrint(item: m, onOpen: open);
                        if (!_animatePin(m, i)) return KeyedSubtree(key: ValueKey(m.id), child: child);
                        return _PinIn(
                          key: ValueKey(m.id),
                          delay: Duration(milliseconds: 40 * math.min(i, 8)),
                          child: child,
                        );
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Items land on the board with a small "pressed in" settle.
class _PinIn extends StatefulWidget {
  const _PinIn({super.key, required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_PinIn> createState() => _PinInState();
}

class _PinInState extends State<_PinIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_c.value);
        return Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: 1.08 - 0.08 * t, child: child),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.unsaved,
    required this.total,
    required this.saving,
    required this.onSaveAll,
  });

  final VoidCallback onBack;
  final int unsaved;
  final int total;
  final bool saving;
  final VoidCallback onSaveAll;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFFF3E3C8);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(colors: [Color(0xFF6B4423), Color(0xFF8A5A33), Color(0xFF5C3A1E)]),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: ink),
            tooltip: 'Back to camera',
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'THE CORKBOARD',
                  style: TextStyle(color: ink, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 16),
                ),
                Text(
                  'tap to inspect · hold to share',
                  style: TextStyle(color: Color(0xFFD8C3A0), fontSize: 11),
                ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: total == 0
                ? const SizedBox.shrink()
                : unsaved == 0
                ? const Row(
                    key: ValueKey('saved'),
                    children: [
                      Icon(Icons.check_circle, size: 16, color: Color(0xFFB9E3A0)),
                      SizedBox(width: 4),
                      Text(
                        'All saved',
                        style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  )
                : FilledButton.tonalIcon(
                    key: const ValueKey('save'),
                    onPressed: saving ? null : onSaveAll,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF3E3C8),
                      foregroundColor: const Color(0xFF4A3220),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download, size: 16),
                    label: Text('Save all ($unsaved)'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.rotate(
        angle: -0.04,
        child: Container(
          width: 230,
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            color: Color(0xFFFFF59D),
            boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(2, 4))],
          ),
          child: const Text(
            "Nothing pinned yet.\n\nShoot a few frames in Film Mode — they'll develop in the darkroom and end up here.",
            style: TextStyle(color: Color(0xFF4E342E), fontSize: 14, height: 1.3),
          ),
        ),
      ),
    );
  }
}

/// Procedural cork painted by cork_board.frag once per screen size into an
/// image; every frame afterwards (e.g. while scrolling) only blits it.
class _CorkBackground extends ConsumerStatefulWidget {
  const _CorkBackground();

  @override
  ConsumerState<_CorkBackground> createState() => _CorkBackgroundState();
}

class _CorkBackgroundState extends ConsumerState<_CorkBackground> {
  ui.Image? _image;
  Size? _forSize;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  ui.Image _render(ui.FragmentProgram program, Size size) {
    // ~1.5 px per logical px is plenty for a soft texture and keeps memory low.
    const scale = 1.5;
    final w = (size.width * scale).round(), h = (size.height * scale).round();
    final shader = program.fragmentShader()
      ..setFloat(0, w.toDouble())
      ..setFloat(1, h.toDouble())
      ..setFloat(2, 3.0 * scale)
      ..setFloat(3, 7.0);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..shader = shader);
    final image = recorder.endRecording().toImageSync(w, h);
    shader.dispose();
    return image;
  }

  @override
  Widget build(BuildContext context) {
    final programs = ref.watch(shaderProgramsProvider).value;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (programs != null && size.isFinite && !size.isEmpty && size != _forSize) {
          _image?.dispose();
          _image = _render(programs.cork, size);
          _forSize = size;
        }
        final image = _image;
        if (image == null) return const ColoredBox(color: Color(0xFFB4875A));
        return RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.low);
      },
    );
  }
}

const _pinColors = [
  Color(0xFFD32F2F),
  Color(0xFF1976D2),
  Color(0xFFFBC02D),
  Color(0xFF388E3C),
  Color(0xFF7B1FA2),
];

/// A print with a white border, a slight random tilt and a push pin through
/// the top border — positioned on the *print*, whatever its shape, never on
/// the cork above it.
class PinnedPrint extends StatelessWidget {
  const PinnedPrint({super.key, required this.item, required this.onOpen});

  final MediaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final rnd = math.Random(item.id.hashCode);
    final angle = (rnd.nextDouble() - 0.5) * 0.14;
    final dx = (rnd.nextDouble() - 0.5) * 10;
    final pin = _pinColors[rnd.nextInt(_pinColors.length)];
    final aspect = (item.width != null && item.height != null && item.height! > 0)
        ? item.width! / item.height!
        : 2 / 3;
    final thumb = item.thumbPath;

    return Builder(
      builder: (anchor) => GestureDetector(
        onTap: onOpen,
        onLongPress: () {
          unawaited(HapticFeedback.mediumImpact());
          unawaited(shareMedia(anchor, item));
        },
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: Center(
            child: AspectRatio(
              aspectRatio: aspect,
              child: Transform.rotate(
                angle: angle,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFBF8F1),
                          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 7, offset: Offset(3, 5))],
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (thumb != null)
                              Image.file(
                                File(thumb),
                                fit: BoxFit.cover,
                                cacheWidth: 420,
                                gaplessPlayback: true,
                                // Developing-paper tone until decoded, not a hole.
                                frameBuilder: (context, child, frame, sync) => frame == null && !sync
                                    ? const ColoredBox(color: Color(0xFFE9E2D3))
                                    : child,
                                errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12),
                              ),
                            // Glossy paper sheen.
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0x22FFFFFF), Color(0x00FFFFFF), Color(0x14000000)],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Pencilled tick on the border once it's in the library.
                    if (item.isSaved)
                      const Positioned(
                        right: 3,
                        bottom: -1,
                        child: Text(
                          '✓',
                          style: TextStyle(
                            color: Color(0xFF6D6D6D),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    // The pin: head centred in the top border of the print.
                    Positioned(
                      top: -7,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: CustomPaint(size: const Size(26, 30), painter: PinPainter(pin)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An instant print pinned through its top border, note and all.
class PinnedInstant extends StatelessWidget {
  const PinnedInstant({super.key, required this.item, required this.onOpen});

  final MediaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final rnd = math.Random(item.id.hashCode);
    final angle = (rnd.nextDouble() - 0.5) * 0.12;
    final dx = (rnd.nextDouble() - 0.5) * 10;
    final pin = _pinColors[rnd.nextInt(_pinColors.length)];
    final thumb = item.thumbPath;
    return Builder(
      builder: (anchor) => GestureDetector(
        onTap: onOpen,
        onLongPress: () {
          unawaited(HapticFeedback.mediumImpact());
          unawaited(shareMedia(anchor, item));
        },
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: Center(
            child: Transform.rotate(
              angle: angle,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  InstantPrint(
                    note: item.note,
                    picture: thumb == null
                        ? const ColoredBox(color: Colors.black12)
                        : Image.file(
                            File(thumb),
                            fit: BoxFit.cover,
                            cacheWidth: 420,
                            gaplessPlayback: true,
                            frameBuilder: (context, child, frame, sync) =>
                                frame == null && !sync ? const ColoredBox(color: Color(0xFFE9E2D3)) : child,
                            errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12),
                          ),
                  ),
                  Positioned(
                    top: -9,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: CustomPaint(size: const Size(26, 30), painter: PinPainter(pin)),
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

/// A Super 8 reel hung on the board by a pin through its hub.
class PinnedReel extends StatelessWidget {
  const PinnedReel({super.key, required this.item, required this.onOpen});

  final MediaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final rnd = math.Random(item.id.hashCode);
    final angle = (rnd.nextDouble() - 0.5) * 0.6;
    final pin = _pinColors[rnd.nextInt(_pinColors.length)];
    return Builder(
      builder: (anchor) => GestureDetector(
        onTap: onOpen,
        onLongPress: () {
          unawaited(HapticFeedback.mediumImpact());
          unawaited(shareMedia(anchor, item));
        },
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, box) {
                final size = box.biggest;
                final thumb = item.thumbPath;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // The tail of film left hanging from behind the reel,
                    // its frames showing how the clip opens.
                    if (thumb != null)
                      Positioned(
                        left: size.width * 0.56,
                        top: size.height * 0.5,
                        width: size.width * 0.3,
                        child: Transform.rotate(
                          angle: -0.32 + angle * 0.2,
                          alignment: Alignment.topCenter,
                          child: FilmTail(
                            frames: 2,
                            frame: Image.file(
                              File(thumb),
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF3A2A20)),
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: ReelPainter(
                          rotation: angle,
                          label: item.fileName.replaceAll('.MP4', ''),
                          duration: formatDuration(item.durationMs),
                          saved: item.isSaved,
                        ),
                      ),
                    ),
                    Positioned(
                      left: size.width / 2 - 13,
                      top: size.height / 2 - 10,
                      child: CustomPaint(size: const Size(26, 30), painter: PinPainter(pin)),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class PinPainter extends CustomPainter {
  PinPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final head = Offset(size.width / 2, 10);
    // Shadow cast on the board (radial gradient: no blur filter needed).
    final shadowRect = Rect.fromCenter(center: head + const Offset(6, 9), width: 20, height: 12);
    canvas.drawOval(
      shadowRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x66000000), Color(0x00000000)],
        ).createShader(shadowRect),
    );
    canvas.drawCircle(
      head,
      9,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          colors: [Color.lerp(color, Colors.white, 0.6)!, color, Color.lerp(color, Colors.black, 0.5)!],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: head, radius: 9)),
    );
    canvas.drawCircle(head + const Offset(-3, -3), 2.2, Paint()..color = Colors.white70);
  }

  @override
  bool shouldRepaint(PinPainter old) => old.color != color;
}

/// Red-safelight darkroom: trays with a latent image slowly coming up.
class _DarkroomStrip extends ConsumerWidget {
  const _DarkroomStrip({required this.items, required this.now});

  final List<MediaItem> items;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0505),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF5C1010)),
        boxShadow: const [BoxShadow(color: Color(0x88FF1744), blurRadius: 18, spreadRadius: -6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.light, size: 14, color: Color(0xFFFF5252)),
              const SizedBox(width: 6),
              Text(
                'DARKROOM · ${items.length} developing',
                style: const TextStyle(
                  color: Color(0xFFFF8A80),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _Tray(item: items[i], now: now),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tray extends ConsumerWidget {
  const _Tray({required this.item, required this.now});

  final MediaItem item;
  final DateTime now;

  /// Shows why a print was ruined (the processing error is kept on the row).
  Future<void> _explainRuined(BuildContext context, WidgetRef ref) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.isVideo ? 'Ruined reel' : 'Ruined print'),
        content: SingleChildScrollView(
          child: SelectableText(item.error ?? 'Unknown error', style: const TextStyle(fontSize: 12)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if (discard == true) await deleteMedia(ref.read(filmRepositoryProvider), item);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = CameraCatalog.byId(item.cameraId);
    final total = item.readyAt.difference(item.capturedAt).inMilliseconds.clamp(1, 1 << 31);
    final left = item.readyAt.difference(now);
    final progress = (1 - left.inMilliseconds / total).clamp(0.0, 1.0);
    final failed = item.status == MediaStatus.failed;
    final processing = item.status == MediaStatus.processing;
    final mm = left.inMinutes.clamp(0, 99).toString();
    final ss = (left.inSeconds % 60).clamp(0, 59).toString().padLeft(2, '0');
    final thumb = item.thumbPath;

    if (item.isVideo && !failed) {
      return SizedBox(
        width: 84,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(aspectRatio: 1, child: _TankTray(progress: processing ? 0 : progress)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              processing && left.isNegative ? 'fixing…' : '${DevelopingTankPainter.stageFor(progress)} $mm:$ss',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    if (spec.isInstant && !failed) {
      // Instant film develops in the light: the picture surfaces through the
      // blue-grey sheet in front of you (eased between the 1 s ticks).
      return SizedBox(
        width: 84,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: processing ? 0 : progress),
                  duration: const Duration(seconds: 1),
                  builder: (context, p, _) => InstantPrint(
                    develop: p,
                    shadow: false,
                    picture: thumb == null || processing
                        ? const SizedBox.shrink()
                        : Image.file(File(thumb), fit: BoxFit.cover, cacheWidth: 160, gaplessPlayback: true),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '0:${left.inSeconds.clamp(0, 59).toString().padLeft(2, '0')}',
              style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: failed ? () => _explainRuined(context, ref) : null,
      onLongPress: failed ? () => unawaited(deleteMedia(ref.read(filmRepositoryProvider), item)) : null,
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2B0A0A),
                  border: Border.all(color: const Color(0xFF6D1B1B), width: 2),
                  borderRadius: BorderRadius.circular(item.isVideo ? 42 : 4),
                ),
                padding: const EdgeInsets.all(5),
                clipBehavior: Clip.antiAlias,
                child: failed
                    ? const Center(
                        child: Text(
                          'RUINED\ntap for\ndetails',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFFFF8A80), fontSize: 10),
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Color(0xFFF2E9E4)),
                          // The latent image surfaces as development proceeds,
                          // seen through the red safelight.
                          if (thumb != null && !processing)
                            Opacity(
                              opacity: Curves.easeIn.transform(progress) * 0.85,
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.matrix([
                                  0.5, 0.3, 0.1, 0, 0, //
                                  0.05, 0.05, 0.02, 0, 0, //
                                  0.03, 0.03, 0.02, 0, 0, //
                                  0, 0, 0, 1, 0,
                                ]),
                                child: Image.file(File(thumb), fit: BoxFit.cover, cacheWidth: 160),
                              ),
                            ),
                          const ColoredBox(color: Color(0x66B71C1C)),
                          if (item.isVideo)
                            const Center(
                              child: Icon(
                                Icons.motion_photos_on_outlined,
                                color: Color(0xAAFF8A80),
                                size: 28,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              failed ? spec.name : (processing && left.isNegative ? 'fixing…' : '$mm:$ss'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// A reel turning in its developing tank (agitation), eased between ticks.
class _TankTray extends StatefulWidget {
  const _TankTray({required this.progress});

  final double progress;

  @override
  State<_TankTray> createState() => _TankTrayState();
}

class _TankTrayState extends State<_TankTray> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.progress),
      duration: const Duration(seconds: 1),
      builder: (context, p, _) => AnimatedBuilder(
        animation: _spin,
        builder: (context, _) => CustomPaint(
          painter: DevelopingTankPainter(
            progress: p,
            // Inversion-style agitation: a few turns one way, then back.
            spin: math.sin(_spin.value * math.pi * 2) * 2.4,
          ),
        ),
      ),
    );
  }
}
