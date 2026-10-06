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
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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

  /// Prints being taken down (pin popped, falling off the board).
  final _falling = <String>{};

  /// Easter egg: tap a pin to take the print down.
  Future<void> _unpin(MediaItem item) async {
    unawaited(HapticFeedback.selectionClick());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          item.isVideo ? 'Would you like to discard this reel?' : 'Would you like to discard this image?',
        ),
        content: Text(
          item.isSaved
              ? 'It comes off the board. The copy in your photo library stays.'
              : "It hasn't been saved to your photo library. This cannot be undone.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    unawaited(HapticFeedback.mediumImpact()); // pin pops
    setState(() => _falling.add(item.id));
  }

  Future<void> _discard(MediaItem item) async {
    await deleteMedia(ref.read(filmRepositoryProvider), item);
    if (mounted) setState(() => _falling.remove(item.id));
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
          Positioned.fill(child: _CorkWall(scroll: _scroll)),
          SafeArea(
            child: CustomScrollView(
              controller: _scroll,
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
                        void unpin() => _unpin(m);
                        final falling = _falling.contains(m.id);
                        final pinned = m.isVideo
                            ? PinnedReel(item: m, onOpen: open, onPinTap: unpin, showPin: !falling)
                            : CameraCatalog.byId(m.cameraId).isInstant
                            ? PinnedInstant(item: m, onOpen: open, onPinTap: unpin, showPin: !falling)
                            : PinnedPrint(item: m, onOpen: open, onPinTap: unpin, showPin: !falling);
                        final child = _Falling(
                          falling: falling,
                          pinColor: _pinColors[math.Random(m.id.hashCode).nextInt(_pinColors.length)],
                          pinAt: m.isVideo ? Alignment.center : Alignment.topCenter,
                          onFallen: () => _discard(m),
                          child: pinned,
                        );
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
/// The cork wall itself. It scrolls with the prints pinned to it (you slide
/// the whole board along), so it is rendered in tiles keyed to the scroll
/// position: the shader is continuous across tiles, each tile is rendered
/// once and reused, and only the ones on screen are kept.
class _CorkWall extends ConsumerStatefulWidget {
  const _CorkWall({required this.scroll});

  final ScrollController scroll;

  @override
  ConsumerState<_CorkWall> createState() => _CorkWallState();
}

class _CorkWallState extends ConsumerState<_CorkWall> {
  static const _scale = 1.5; // texture px per logical px: plenty for cork
  final _tiles = <int, ui.Image>{};
  double? _forWidth;

  @override
  void dispose() {
    for (final t in _tiles.values) {
      t.dispose();
    }
    super.dispose();
  }

  ui.Image _render(ui.FragmentProgram program, int index, double w, double tileH) {
    final pw = (w * _scale).round(), ph = (tileH * _scale).round();
    final shader = program.fragmentShader()
      ..setFloat(0, pw.toDouble())
      ..setFloat(1, ph.toDouble())
      ..setFloat(2, 3.0 * _scale)
      ..setFloat(3, 7.0)
      ..setFloat(4, index * ph.toDouble());
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble()), Paint()..shader = shader);
    final image = recorder.endRecording().toImageSync(pw, ph);
    shader.dispose();
    return image;
  }

  @override
  Widget build(BuildContext context) {
    final programs = ref.watch(shaderProgramsProvider).value;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (programs == null || !size.isFinite || size.isEmpty) {
          return const ColoredBox(color: Color(0xFFB4875A));
        }
        if (_forWidth != size.width) {
          for (final t in _tiles.values) {
            t.dispose();
          }
          _tiles.clear();
          _forWidth = size.width;
        }
        final tileH = size.height;
        return CustomPaint(
          size: size,
          painter: _CorkWallPainter(
            scroll: widget.scroll,
            tileH: tileH,
            tile: (i) => _tiles.putIfAbsent(i, () {
              // Keep a small window of tiles around the current one.
              if (_tiles.length > 5) {
                final far = _tiles.keys.reduce((a, b) => (a - i).abs() > (b - i).abs() ? a : b);
                _tiles.remove(far)?.dispose();
              }
              return _render(programs.cork, i, size.width, tileH);
            }),
          ),
        );
      },
    );
  }
}

class _CorkWallPainter extends CustomPainter {
  _CorkWallPainter({required this.scroll, required this.tileH, required this.tile}) : super(repaint: scroll);

  final ScrollController scroll;
  final double tileH;
  final ui.Image Function(int index) tile;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    final first = (offset / tileH).floor();
    final last = ((offset + size.height) / tileH).floor();
    final paint = Paint()..filterQuality = FilterQuality.low;
    for (var i = first; i <= last; i++) {
      final img = tile(i);
      final dst = Rect.fromLTWH(0, i * tileH - offset, size.width, tileH);
      canvas.drawImageRect(img, Offset.zero & Size(img.width.toDouble(), img.height.toDouble()), dst, paint);
    }
  }

  @override
  bool shouldRepaint(_CorkWallPainter old) => old.tileH != tileH || old.scroll != scroll;
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
  const PinnedPrint({
    super.key,
    required this.item,
    required this.onOpen,
    this.onPinTap,
    this.showPin = true,
  });

  final MediaItem item;
  final VoidCallback onOpen;

  /// Tapping the pin offers to take the print down (see _CorkboardScreen).
  final VoidCallback? onPinTap;
  final bool showPin;

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
                      child: _FlipCard(
                        back: _PrintBack(item: item),
                        front: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFBF8F1),
                            boxShadow: [
                              BoxShadow(color: Colors.black45, blurRadius: 7, offset: Offset(3, 5)),
                            ],
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
                        child: _Pin(color: pin, visible: showPin, onTap: onPinTap),
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
  const PinnedInstant({
    super.key,
    required this.item,
    required this.onOpen,
    this.onPinTap,
    this.showPin = true,
  });

  final MediaItem item;
  final VoidCallback onOpen;

  /// Tapping the pin offers to take the print down (see _CorkboardScreen).
  final VoidCallback? onPinTap;
  final bool showPin;

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
                  _FlipCard(
                    back: _PrintBack(item: item, instant: true),
                    front: InstantPrint(
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
                  ),
                  Positioned(
                    top: -9,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _Pin(color: pin, visible: showPin, onTap: onPinTap),
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
  const PinnedReel({super.key, required this.item, required this.onOpen, this.onPinTap, this.showPin = true});

  final MediaItem item;
  final VoidCallback onOpen;

  /// Tapping the pin offers to take the print down (see _CorkboardScreen).
  final VoidCallback? onPinTap;
  final bool showPin;

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
                        left: size.width * 0.64,
                        top: size.height * 0.62,
                        width: size.width * 0.26,
                        child: Transform.rotate(
                          angle: -0.18 + angle * 0.15,
                          alignment: Alignment.topCenter,
                          child: FilmTail(
                            frames: 3,
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
                      child: _Pin(color: pin, visible: showPin, onTap: onPinTap),
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

/// A plastic push pin: a wide flange with a domed grip on top, a glint of
/// steel needle where it enters the cork, and a soft shadow cast down-right.
class PinPainter extends CustomPainter {
  PinPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final head = Offset(size.width / 2, 10);
    // Shadow on the board (radial gradient: no blur filter needed).
    final shadowRect = Rect.fromCenter(center: head + const Offset(6, 10), width: 22, height: 13);
    canvas.drawOval(
      shadowRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x77000000), Color(0x00000000)],
        ).createShader(shadowRect),
    );
    // Needle: a short steel glint between the head and its shadow.
    canvas.drawLine(
      head + const Offset(2.5, 5),
      head + const Offset(5.5, 10),
      Paint()
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [Color(0xFFE6E6E6), Color(0xFF6E6E6E)],
        ).createShader(Rect.fromPoints(head + const Offset(2.5, 5), head + const Offset(5.5, 10))),
    );
    final dark = Color.lerp(color, Colors.black, 0.45)!;
    final light = Color.lerp(color, Colors.white, 0.55)!;
    // Flange.
    canvas.drawCircle(
      head,
      9,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [color, dark],
          stops: const [0.55, 1],
        ).createShader(Rect.fromCircle(center: head, radius: 9)),
    );
    canvas.drawCircle(
      head,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = Colors.black.withValues(alpha: 0.35),
    );
    // Grip: a smaller dome standing up from the flange (offset toward the
    // light so it reads as height).
    final grip = head + const Offset(-1.2, -1.6);
    canvas.drawCircle(grip + const Offset(0.8, 1.2), 6, Paint()..color = dark.withValues(alpha: 0.6));
    canvas.drawCircle(
      grip,
      6,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.5),
          colors: [light, color, dark],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: grip, radius: 6)),
    );
    // Specular highlights.
    canvas.drawOval(
      Rect.fromCenter(center: grip + const Offset(-2.2, -2.4), width: 3.6, height: 2.4),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      head + const Offset(5.2, 3.2),
      1,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
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
              processing && left.isNegative
                  ? 'fixing…'
                  : '${DevelopingTankPainter.stageFor(progress)} $mm:$ss',
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

    if (!item.isVideo && !failed) {
      final stage = PrintTrayPainter.stageFor(processing ? 0 : progress);
      return SizedBox(
        width: 84,
        child: Column(
          children: [
            Expanded(
              child: _PrintTray(progress: processing ? 0 : progress, thumb: processing ? null : thumb),
            ),
            const SizedBox(height: 4),
            Text(
              processing && left.isNegative ? 'fixing…' : '${stage.label} $mm:$ss',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

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

/// A pin you can tap (it sits on top of the print's own gesture area).
class _Pin extends StatelessWidget {
  const _Pin({required this.color, required this.visible, this.onTap});

  final Color color;
  final bool visible;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(width: 26, height: 30);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CustomPaint(size: const Size(26, 30), painter: PinPainter(color)),
    );
  }
}

/// Taking a print down: the pin pops out toward you and away, the print
/// tips and drops off the bottom of the screen.
class _Falling extends StatefulWidget {
  const _Falling({
    required this.falling,
    required this.pinColor,
    required this.pinAt,
    required this.onFallen,
    required this.child,
  });

  final bool falling;
  final Color pinColor;
  final Alignment pinAt;
  final VoidCallback onFallen;
  final Widget child;

  @override
  State<_Falling> createState() => _FallingState();
}

class _FallingState extends State<_Falling> with SingleTickerProviderStateMixin {
  /// Which way it tips: picked once per fall.
  final double _spin = (math.Random().nextBool() ? 1 : -1) * 0.9;

  late final AnimationController _t =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 950))..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onFallen();
      });

  @override
  void initState() {
    super.initState();
    if (widget.falling) _t.forward();
  }

  @override
  void didUpdateWidget(_Falling old) {
    super.didUpdateWidget(old);
    if (widget.falling && !old.falling) _t.forward(from: 0);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.falling && !_t.isAnimating) return widget.child;
    final screenH = MediaQuery.sizeOf(context).height;
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final v = _t.value;
        // The print hangs a beat (the pin's gone), then gravity takes it.
        final fall = Curves.easeIn.transform(((v - 0.12) / 0.88).clamp(0.0, 1.0));
        final pin = Curves.easeOut.transform((v / 0.4).clamp(0.0, 1.0));
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.translate(
              offset: Offset(0, fall * screenH * 1.1),
              child: Transform.rotate(angle: fall * _spin, child: child),
            ),
            // The pin flying out of the cork.
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: widget.pinAt,
                  child: Opacity(
                    opacity: (1 - pin).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(pin * 40, -pin * 60 + (widget.pinAt == Alignment.topCenter ? -7 : 0)),
                      child: Transform.scale(
                        scale: 1 + pin * 0.8,
                        child: CustomPaint(size: const Size(26, 30), painter: PinPainter(widget.pinColor)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Front of a print, plus a dog-eared corner: tap the corner and the print
/// turns over to show the lab's stamp on the back; tap the back to turn it
/// round again.
class _FlipCard extends StatefulWidget {
  const _FlipCard({required this.front, required this.back});

  final Widget front;
  final Widget back;

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard> with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _back = false;

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _toggle() {
    unawaited(HapticFeedback.selectionClick());
    _back = !_back;
    if (_back) {
      _flip.forward();
    } else {
      _flip.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final a = Curves.easeInOut.transform(_flip.value) * math.pi;
        final showBack = a > math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(a),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              if (!showBack) ...[
                widget.front,
                // The folded corner: the tap target for the easter egg.
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    child: const SizedBox(
                      width: 30,
                      height: 30,
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: CustomPaint(size: Size(12, 12), painter: _DogEar()),
                      ),
                    ),
                  ),
                ),
              ] else
                // Mirror the back so its text reads correctly after the turn.
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    child: widget.back,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A turned-up paper corner.
class _DogEar extends CustomPainter {
  const _DogEar();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = const Color(0x55000000),
    );
    canvas.drawPath(
      Path()
        ..moveTo(w, 0)
        ..lineTo(0, h)
        ..lineTo(0, 0)
        ..close(),
      Paint()..color = const Color(0xFFE9E3D6),
    );
    canvas.drawLine(
      Offset(w, 0),
      Offset(0, h),
      Paint()
        ..color = const Color(0x33000000)
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(_DogEar old) => false;
}

/// The back of a print: the paper maker's watermark and the lab's stamp
/// (frame, stock, date). Instant prints have their black backing instead.
class _PrintBack extends StatelessWidget {
  const _PrintBack({required this.item, this.instant = false});

  final MediaItem item;
  final bool instant;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final spec = CameraCatalog.byId(item.cameraId);
    final d = item.readyAt;
    final date = '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
    final frame = item.fileName.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
    if (instant) {
      return Container(
        color: const Color(0xFF151515),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DARKROOM INSTANT FILM',
              style: TextStyle(
                color: Color(0xFF8A8A8A),
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Do not cut, puncture or heat.',
              style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 7),
            ),
            const Spacer(),
            Text(
              '$frame · $date',
              style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 8, letterSpacing: 1),
            ),
          ],
        ),
      );
    }
    return ClipRect(
      child: Container(
        color: const Color(0xFFF4F1EA),
        child: Stack(
          children: [
            // Paper maker's watermark, repeated diagonally.
            Positioned.fill(
              child: Transform.rotate(
                angle: -0.5,
                child: OverflowBox(
                  maxWidth: 600,
                  maxHeight: 600,
                  child: Text(
                    List.filled(40, 'DARKROOM PHOTO PAPER  ').join(),
                    style: const TextStyle(
                      color: Color(0x14000000),
                      fontSize: 9,
                      letterSpacing: 2,
                      height: 2.2,
                    ),
                  ),
                ),
              ),
            ),
            // The lab's stamp, slightly crooked, in blue ink.
            Center(
              child: Transform.rotate(
                angle: -0.07,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xAA2B4C8C), width: 1.2)),
                  child: Text(
                    '$frame\n${spec.name.toUpperCase()}\nDEV $date',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xCC2B4C8C),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      height: 1.3,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One stage of black-and-white print processing.
class PrintStage {
  const PrintStage(this.label, this.until, this.tray, this.liquid);

  final String label;

  /// Fraction of the darkroom time this stage ends at.
  final double until;
  final Color tray;
  final Color liquid;
}

/// A print going through the trays under the safelight: developer (the
/// image comes up), stop bath, fixer, then a running-water wash.
class PrintTrayPainter extends CustomPainter {
  PrintTrayPainter({required this.progress, required this.ripple, required this.stage});

  final double progress;
  final double ripple;
  final PrintStage stage;

  static const stages = [
    PrintStage('DEV', 0.55, Color(0xFF8E2A22), Color(0xFF3A1A12)),
    PrintStage('STOP', 0.65, Color(0xFFD6CEC2), Color(0xFF4A3A22)),
    PrintStage('FIX', 0.90, Color(0xFF6A6A6A), Color(0xFF2E2E30)),
    PrintStage('WASH', 1.01, Color(0xFF3F5D78), Color(0xFF1E3446)),
  ];

  static PrintStage stageFor(double p) => stages.firstWhere((s) => p < s.until, orElse: () => stages.last);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    // Tray body (lip lighter than the well).
    canvas.drawRRect(r, Paint()..color = stage.tray);
    final well = RRect.fromRectAndRadius((Offset.zero & size).deflate(4), const Radius.circular(4));
    canvas.drawRRect(well, Paint()..color = stage.liquid);
    // Ridges on the tray floor, seen through the chemistry.
    final ridge = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var x = well.left + 6; x < well.right - 4; x += 7) {
      canvas.drawLine(Offset(x, well.top + 3), Offset(x, well.bottom - 3), ridge);
    }
    // Gentle rocking: highlights drift across the surface (faster under the
    // running water of the wash).
    final speed = stage.label == 'WASH' ? 2.4 : 1.0;
    final glint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (var k = 0; k < 3; k++) {
      final y = well.top + well.height * ((ripple * speed + k / 3) % 1.0);
      final path = Path()..moveTo(well.left + 2, y);
      for (var x = well.left + 2; x <= well.right - 2; x += 4) {
        path.lineTo(x, y + math.sin(x * 0.25 + ripple * math.pi * 2 * speed) * 1.4);
      }
      canvas.drawPath(path, glint);
    }
    // Bamboo tongs resting on the lip.
    final tongs = Paint()
      ..color = const Color(0xFFD9B77A)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(size.width - 6, 2), Offset(size.width - 20, size.height * 0.42), tongs);
    canvas.drawLine(Offset(size.width - 2, 6), Offset(size.width - 16, size.height * 0.46), tongs);
  }

  @override
  bool shouldRepaint(PrintTrayPainter old) =>
      old.progress != progress || old.ripple != ripple || old.stage != stage;
}

/// The print in its tray: paper floating in the chemistry, the latent image
/// surfacing during the developer stage, all seen by red safelight.
class _PrintTray extends StatefulWidget {
  const _PrintTray({required this.progress, required this.thumb});

  final double progress;
  final String? thumb;

  @override
  State<_PrintTray> createState() => _PrintTrayState();
}

class _PrintTrayState extends State<_PrintTray> with SingleTickerProviderStateMixin {
  late final AnimationController _rock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _rock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thumb = widget.thumb;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.progress),
      duration: const Duration(seconds: 1),
      builder: (context, p, _) {
        final stage = PrintTrayPainter.stageFor(p);
        // The image comes up during the developer and is fixed after that.
        final dev = Curves.easeIn.transform((p / PrintTrayPainter.stages.first.until).clamp(0.0, 1.0));
        return AnimatedBuilder(
          animation: _rock,
          builder: (context, child) => Container(
            // Everything in here is seen by red safelight.
            foregroundDecoration: BoxDecoration(
              color: const Color(0x38C62828),
              borderRadius: BorderRadius.circular(6),
            ),
            child: CustomPaint(
              painter: PrintTrayPainter(progress: p, ripple: _rock.value, stage: stage),
              child: child,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
            child: Transform.rotate(
              angle: -0.04,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Wet paper.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFF2E9E4),
                      boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(1, 2))],
                    ),
                  ),
                  if (thumb != null)
                    Padding(
                      padding: const EdgeInsets.all(3),
                      child: Opacity(
                        opacity: dev,
                        child: ColorFiltered(
                          // Monochrome under the safelight.
                          colorFilter: const ColorFilter.matrix([
                            0.33, 0.5, 0.17, 0, 0, //
                            0.33, 0.5, 0.17, 0, 0, //
                            0.33, 0.5, 0.17, 0, 0, //
                            0, 0, 0, 1, 0,
                          ]),
                          child: Image.file(
                            File(thumb),
                            fit: BoxFit.cover,
                            cacheWidth: 160,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
