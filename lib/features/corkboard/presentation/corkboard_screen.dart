import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/system_gestures.dart';
import '../../../core/theme/darkroom_mark.dart';
import '../../../core/db/media_repository.dart';
import '../../../core/providers.dart';
import '../../../core/shaders/shader_library.dart';
import '../../camera/application/camera_ui_state.dart' show userNameProvider;
import '../../cameras/domain/camera_catalog.dart';
import '../../viewer/presentation/media_actions.dart';
import 'instant_print.dart';
import 'print_viewer.dart';
import 'projector_screen.dart';
import 'reel_painter.dart';
import '../../../core/device/haptics.dart';
import '../../../core/device/shake.dart';
import '../../../core/diagnostics/perf_recorder.dart';
import '../../../core/device/upright.dart';
import '../../../core/processing/instant_frame.dart' show InstantFrame;

/// Film gallery: developed prints and Super 8 reels pinned to a cork board,
/// with the darkroom (still developing) in a red safelight strip on top.
///
/// Nothing reaches the phone's photo library until it is saved — per print,
/// or with "Save all".
class CorkboardScreen extends ConsumerStatefulWidget {
  /// The board slides in from the left in its wooden frame, unhurried, and
  /// comes to rest against the right edge without overshooting it (and
  /// slides back out).
  static PageRouteBuilder<void> slideIn() => PageRouteBuilder<void>(
    settings: UprightApp.landscape,
    transitionDuration: slideDuration,
    reverseTransitionDuration: const Duration(milliseconds: 460),
    pageBuilder: (context, _, _) => const UprightPage(child: CorkboardScreen()),
    transitionsBuilder: (context, a, _, child) => SlideTransition(
      // Eases off, but still arrives with a little weight behind it.
      position: Tween(
        begin: const Offset(-1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: a, curve: _arrive, reverseCurve: Curves.easeInCubic)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 30, offset: Offset(10, 0))],
        ),
        child: child,
      ),
    ),
  );

  static const slideDuration = Duration(milliseconds: 860);
  static const _arrive = Cubic(0.3, 0.0, 0.5, 0.94);

  const CorkboardScreen({super.key});

  @override
  ConsumerState<CorkboardScreen> createState() => _CorkboardScreenState();
}

class _CorkboardScreenState extends ConsumerState<CorkboardScreen> with SingleTickerProviderStateMixin {
  bool _saving = false;
  late final _scroll = ScrollController()
    ..addListener(() => PerfRecorder.mark('corkboard scroll', hold: const Duration(milliseconds: 150)));

  /// Prints whose share file has been queued (id:note).
  final _warmed = <String>{};

  /// Swipe left to put the board away (it slides back out to the left).
  /// Like the swipe that brings it in, it doesn't follow the thumb: a clear
  /// swipe triggers it. Touches from the screen's side strips are left to
  /// the phone's back gesture.
  double? _swipeFrom;
  double _swipeDx = 0;

  void _swipeStart(DragStartDetails d) {
    _swipeDx = 0;
    _swipeFrom = SystemGestureZones.startsInEdge(context, d.globalPosition) ? null : d.globalPosition.dx;
  }

  void _swipeEnd(DragEndDetails d) {
    if (_swipeFrom == null) return;
    _swipeFrom = null;
    final v = d.primaryVelocity ?? 0;
    if (v < -700 || (_swipeDx < -110 && v < 200)) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _shaker.stop();
    _shake.dispose();
    super.dispose();
  }

  /// Pin-in animations only play as the board opens and for prints that come
  /// out of the darkroom while it is open. Prints scrolled into view appear
  /// at once (they used to fade in late, leaving blank gaps).
  DateTime _openedAt = DateTime.now();

  bool _animatePin(MediaItem m, int index) =>
      m.readyAt.isAfter(_openedAt) ||
      (index < 12 && DateTime.now().difference(_openedAt) < const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    // Looking at the board clears "new print" badges and the notification.
    Future.microtask(() => ref.read(darkroomEngineProvider).markSeen());
    _shaker.start();
  }

  /// Shake the phone: every print and reel that hasn't been saved comes off
  /// the board (after asking). The board judders, they unpin and fall, and
  /// the rest pin themselves back up in their new places.
  late final _shaker = ShakeDetector(() => unawaited(_shakeOff()));
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  List<MediaItem> _developed = const [];
  bool _asking = false;

  Future<void> _shakeOff() async {
    if (_asking || !mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final off = _developed.where((m) => !m.isSaved && !_falling.contains(m.id)).toList();
    unawaited(Haptics.mediumImpact());
    if (off.isEmpty) {
      unawaited(_shake.forward(from: 0));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nothing shook loose: everything on the board is saved.')));
      return;
    }
    _asking = true;
    final reels = off.where((m) => m.isVideo).length;
    final prints = off.length - reels;
    final what = [
      if (prints > 0) '$prints ${prints == 1 ? 'print' : 'prints'}',
      if (reels > 0) '$reels ${reels == 1 ? 'reel' : 'reels'}',
    ].join(' and ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Shake off the unsaved ones?'),
        content: Text("$what haven't been saved to your photo library. They'll fall off the board for good."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep them')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Shake them off')),
        ],
      ),
    );
    _asking = false;
    if (ok != true || !mounted) return;
    unawaited(_shake.forward(from: 0));
    for (var i = 0; i < 4; i++) {
      Future<void>.delayed(Duration(milliseconds: 130 * i), () => Haptics.heavyImpact());
    }
    final rnd = math.Random();
    for (final m in off) {
      Future<void>.delayed(Duration(milliseconds: 120 + rnd.nextInt(380)), () {
        if (mounted) setState(() => _falling.add(m.id));
      });
    }
    // Once they're down, the rest pin themselves up again in their new places.
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _openedAt = DateTime.now());
    });
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
    unawaited(Haptics.lightImpact());
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
    unawaited(Haptics.selectionClick());
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
    unawaited(Haptics.mediumImpact()); // pin pops
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
    PerfRecorder.mark(item.isVideo ? 'projector open' : 'print viewer open');
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
    _developed = developed;
    // Polaroids need their framed share file made: do it in the background
    // now, so holding one brings the share sheet up straight away.
    final cold = developed.where((m) => _warmed.add('${m.id}:${m.note}')).toList();
    if (cold.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final m in cold) {
          warmShareExport(m);
        }
      });
    }

    // Prints that came out while the board is open are "seen" too.
    ref.listen(filmItemsProvider, (prev, next) {
      final unseen = next.value?.any((m) => m.isDevelopedAt(DateTime.now()) && !m.seen) ?? false;
      if (unseen) unawaited(ref.read(darkroomEngineProvider).markSeen());
    });

    // System bars overlap the board: start the content clear of them, but
    // let it scroll out under them to the frame.
    final insets = MediaQuery.paddingOf(context);
    final topInset = math.max(0.0, insets.top - _WoodFrame.width);
    final bottomInset = math.max(0.0, insets.bottom - _WoodFrame.width);
    // Turned to landscape, the bars and the camera cutout sit at the sides.
    final leftInset = math.max(0.0, insets.left - _WoodFrame.width);
    final rightInset = math.max(0.0, insets.right - _WoodFrame.width);

    return GestureDetector(
      onHorizontalDragStart: _swipeStart,
      onHorizontalDragUpdate: (d) => _swipeDx += d.primaryDelta ?? 0,
      onHorizontalDragEnd: _swipeEnd,
      onHorizontalDragCancel: () => _swipeFrom = null,
      child: Scaffold(
        backgroundColor: const Color(0xFF4A3220),
        // A wooden frame round the whole board.
        body: CustomPaint(
          foregroundPainter: const _WoodFrame(thickness: _WoodFrame.width),
          child: Padding(
            padding: const EdgeInsets.all(_WoodFrame.width),
            child: ClipRect(
              // (judders when shaken: see _shakeOff)
              child: AnimatedBuilder(
                animation: _shake,
                builder: (context, child) {
                  final t = _shake.value;
                  final dx = _shake.isAnimating ? math.sin(t * math.pi * 9) * 14 * (1 - t) : 0.0;
                  return Transform.translate(offset: Offset(dx, 0), child: child);
                },
                child: Stack(
                  children: [
                    Positioned.fill(child: _CorkWall(scroll: _scroll)),
                    // The prints are pinned to the cork: no bounce or stretch
                    // past the ends, or they'd slide off the wall. They scroll
                    // right up to the frame, under the status bar and the home
                    // bar, rather than vanishing a strip short of the edges.
                    Padding(
                      padding: EdgeInsets.only(left: leftInset, right: rightInset),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
                        child: CustomScrollView(
                          controller: _scroll,
                          physics: const ClampingScrollPhysics(),
                          // Build (and decode) prints well before they scroll into view.
                          scrollCacheExtent: const ScrollCacheExtent.viewport(1.5),
                          slivers: [
                            SliverToBoxAdapter(child: SizedBox(height: topInset)),
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
                                  delegate: SliverChildBuilderDelegate(childCount: developed.length, (
                                    context,
                                    i,
                                  ) {
                                    final m = developed[i];
                                    void open() => _open(context, developed, m);
                                    void unpin() => _unpin(m);
                                    final falling = _falling.contains(m.id);
                                    final pinned = m.isVideo
                                        ? PinnedReel(
                                            item: m,
                                            onOpen: open,
                                            onPinTap: unpin,
                                            showPin: !falling,
                                          )
                                        : CameraCatalog.byId(m.cameraId).isInstant
                                        ? PinnedInstant(
                                            item: m,
                                            onOpen: open,
                                            onPinTap: unpin,
                                            showPin: !falling,
                                          )
                                        : PinnedPrint(
                                            item: m,
                                            onOpen: open,
                                            onPinTap: unpin,
                                            showPin: !falling,
                                          );
                                    final child = _Falling(
                                      falling: falling,
                                      pinColor:
                                          _pinColors[math.Random(m.id.hashCode).nextInt(_pinColors.length)],
                                      pinAt: m.isVideo ? const Alignment(0.04, -0.45) : Alignment.topCenter,
                                      onFallen: () => _discard(m),
                                      child: pinned,
                                    );
                                    if (!_animatePin(m, i)) {
                                      return KeyedSubtree(key: ValueKey(m.id), child: child);
                                    }
                                    return _PinIn(
                                      key: ValueKey(m.id),
                                      delay: Duration(milliseconds: 40 * math.min(i, 8)),
                                      child: child,
                                    );
                                  }),
                                ),
                              ),
                            SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
                          ],
                        ),
                      ),
                    ),
                    // A note tucked in the corner of the frame: the shake.
                    if (developed.isNotEmpty)
                      Positioned(
                        right: 10 + rightInset,
                        bottom: 10 + bottomInset,
                        child: const IgnorePointer(child: _ShakeNote()),
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

/// A plain wooden picture frame: mitred corners, a little grain, a lighter
/// bevel on the inside edge.
class _WoodFrame extends CustomPainter {
  const _WoodFrame({required this.thickness});

  static const width = 14.0;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, t = thickness;
    final sides = <(Path, Alignment, Alignment)>[
      (
        Path()..addPolygon([Offset.zero, Offset(w, 0), Offset(w - t, t), Offset(t, t)], true),
        Alignment.topCenter,
        Alignment.bottomCenter,
      ),
      (
        Path()..addPolygon([Offset(0, h), Offset(w, h), Offset(w - t, h - t), Offset(t, h - t)], true),
        Alignment.bottomCenter,
        Alignment.topCenter,
      ),
      (
        Path()..addPolygon([Offset.zero, Offset(t, t), Offset(t, h - t), Offset(0, h)], true),
        Alignment.centerLeft,
        Alignment.centerRight,
      ),
      (
        Path()..addPolygon([Offset(w, 0), Offset(w - t, t), Offset(w - t, h - t), Offset(w, h)], true),
        Alignment.centerRight,
        Alignment.centerLeft,
      ),
    ];
    for (final (path, outside, inside) in sides) {
      final bounds = path.getBounds();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: outside,
            end: inside,
            colors: const [Color(0xFF3B2414), Color(0xFF7A4F2E), Color(0xFFA77446)],
            stops: const [0, 0.55, 1],
          ).createShader(bounds),
      );
      // Grain running along each side.
      canvas.save();
      canvas.clipPath(path);
      final grain = Paint()
        ..color = const Color(0x33200F05)
        ..strokeWidth = 1;
      final horizontal = bounds.width > bounds.height;
      for (var k = 0; k < 7; k++) {
        final f = (k + 0.5) / 7;
        final p = Path();
        if (horizontal) {
          final y = bounds.top + bounds.height * f;
          p.moveTo(bounds.left, y);
          for (var x = bounds.left; x <= bounds.right; x += 12) {
            p.lineTo(x, y + 0.9 * math.sin(x * 0.045 + k * 1.7));
          }
        } else {
          final x = bounds.left + bounds.width * f;
          p.moveTo(x, bounds.top);
          for (var y = bounds.top; y <= bounds.bottom; y += 12) {
            p.lineTo(x + 0.9 * math.sin(y * 0.045 + k * 1.7), y);
          }
        }
        canvas.drawPath(p, grain..style = PaintingStyle.stroke);
      }
      canvas.restore();
    }
    // Mitre joints and the inner lip.
    final joint = Paint()
      ..color = const Color(0x66000000)
      ..strokeWidth = 1;
    canvas.drawLine(Offset.zero, Offset(t, t), joint);
    canvas.drawLine(Offset(w, 0), Offset(w - t, t), joint);
    canvas.drawLine(Offset(0, h), Offset(t, h - t), joint);
    canvas.drawLine(Offset(w, h), Offset(w - t, h - t), joint);
    canvas.drawRect(
      Rect.fromLTRB(t, t, w - t, h - t),
      Paint()
        ..color = const Color(0x88000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WoodFrame old) => old.thickness != thickness;
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
  @override
  Widget build(BuildContext context) {
    final programs = ref.watch(shaderProgramsProvider).value;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (programs == null || !size.isFinite || size.isEmpty) {
          return const ColoredBox(color: Color(0xFFB4875A));
        }
        return CustomPaint(
          size: size,
          painter: _CorkWallPainter(
            scroll: widget.scroll,
            tileH: size.height,
            tile: (i) => CorkTiles.tile(programs.cork, i, size),
          ),
        );
      },
    );
  }
}

/// The cork wall's rendered tiles, kept between visits (the shader is
/// expensive on slower GPUs: painting a tile in the board's first frame made
/// the slide-in stutter) and drawn ahead of time by [warm].
class CorkTiles {
  CorkTiles._();

  static const _scale = 2.0; // texture px per logical px: keeps the granules crisp
  static final _tiles = <int, ui.Image>{};
  static Size? _forSize;

  static ui.Image tile(ui.FragmentProgram program, int index, Size size) {
    if (_forSize != size) {
      for (final t in _tiles.values) {
        t.dispose();
      }
      _tiles.clear();
      _forSize = size;
    }
    return _tiles.putIfAbsent(index, () {
      // Keep a small window of tiles around the current one.
      if (_tiles.length > 4) {
        final far = _tiles.keys.reduce((a, b) => (a - index).abs() > (b - index).abs() ? a : b);
        _tiles.remove(far)?.dispose();
      }
      return _render(program, index, size.width, size.height);
    });
  }

  /// Draws the first tiles for the board on a [screen] of this size (inside
  /// its wooden frame), so the first slide-in only blits them.
  static void warm(ui.FragmentProgram program, Size screen) {
    final size = Size(screen.width - 2 * _WoodFrame.width, screen.height - 2 * _WoodFrame.width);
    if (size.isEmpty) return;
    for (var i = 0; i < 2; i++) {
      tile(program, i, size);
    }
  }

  static ui.Image _render(ui.FragmentProgram program, int index, double w, double tileH) {
    final pw = (w * _scale).round(), ph = (tileH * _scale).round();
    final shader = program.fragmentShader()
      ..setFloat(0, pw.toDouble())
      ..setFloat(1, ph.toDouble())
      ..setFloat(2, _scale)
      ..setFloat(3, 7.0)
      ..setFloat(4, index * ph.toDouble());
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble()), Paint()..shader = shader);
    final image = recorder.endRecording().toImageSync(pw, ph);
    shader.dispose();
    return image;
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
          unawaited(Haptics.mediumImpact());
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
          unawaited(Haptics.mediumImpact());
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
          unawaited(Haptics.mediumImpact());
          unawaited(shareMedia(anchor, item));
        },
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, box) {
                final size = box.biggest;
                final thumb = item.thumbPath;
                // The spool render: reel radius 100 of a 240 canvas, centred.
                final s = size.width, r = s * 100 / 240;
                final cardW = s * 0.42;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Transform.rotate(
                        angle: angle,
                        child: Image.asset(
                          'assets/corkboard/reel.webp',
                          cacheWidth: 480,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                    // It rests on two pins under the rim.
                    for (final side in const [-1.0, 1.0])
                      Positioned(
                        left: s / 2 + side * r * 0.62 - 13,
                        top: s / 2 + r * 0.8 + 1,
                        child: _Pin(color: pin, visible: showPin, onTap: onPinTap),
                      ),
                    // An instant photo of the first frame pinned on the front.
                    Positioned(
                      left: s * 0.52 - cardW / 2,
                      top: s * 0.27,
                      width: cardW,
                      child: Transform.rotate(
                        angle: angle * 0.4 + 0.08,
                        alignment: Alignment.topCenter,
                        child: _ReelCard(item: item, thumb: thumb),
                      ),
                    ),
                    Positioned(
                      left: s * 0.52 - 13,
                      top: s * 0.27 - 4,
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

/// The little instant photo on a reel: its first frame, the file name
/// written under it.
class _ReelCard extends StatelessWidget {
  const _ReelCard({required this.item, required this.thumb});

  final MediaItem item;
  final String? thumb;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, pad = w * 0.06;
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: InstantFrame.paper,
            boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(2, 3))],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: thumb == null
                      ? const ColoredBox(color: Color(0xFF2A211B))
                      : Image.file(
                          File(thumb!),
                          fit: BoxFit.cover,
                          cacheWidth: 200,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF2A211B)),
                        ),
                ),
                SizedBox(
                  height: w * 0.26,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        reelLabel(item),
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'Caveat',
                          fontSize: w * 0.17,
                          height: 1,
                          color: const Color(0xFF2B2A4A),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A traditional plastic push pin stuck in the cork, its shadow on the
/// board: a render per colour (`tool/render/blender/pin.py`, 40 x 40 dp, the
/// needle in at (20, 16)), laid out in the old 26 x 30 box with the needle
/// at (13, 10).
class PinImage extends StatelessWidget {
  const PinImage(this.color, {super.key});

  static const _pinScale = 1.15;

  final Color color;

  @override
  Widget build(BuildContext context) {
    final i = _pinColors.indexOf(color);
    return SizedBox(
      width: 26,
      height: 30,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 13 - 20 * _pinScale,
            top: 10 - 16 * _pinScale,
            width: 40 * _pinScale,
            height: 40 * _pinScale,
            child: Image.asset(
              'assets/corkboard/pin_${i < 0 ? 0 : i}.webp',
              cacheWidth: 160,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ],
      ),
    );
  }
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

  /// What went wrong in the darkroom, as the darkroom would tell it. The
  /// real (technical) error is one tap away: Copy error report.
  static const _printExcuses = [
    'Someone opened the darkroom door halfway through. The light got in and fogged it.',
    'The developer was tired. So was the person minding it. It came out blank.',
    'The fixer ran out partway, and the picture slipped away with it.',
    'A cat knocked the tray over. We are choosing to blame the cat.',
    'The safelight flickered white for a second. That second was enough.',
  ];
  static const _reelExcuses = [
    'The reel jumped its sprockets in the tank and never quite got wet.',
    'Light leaked into the tank. The whole reel came out a lovely shade of nothing.',
    'The film kinked on the spiral and stuck to itself.',
  ];

  /// Shows why a print was ruined (the processing error is kept on the row).
  Future<void> _explainRuined(BuildContext context, WidgetRef ref) async {
    final excuses = item.isVideo ? _reelExcuses : _printExcuses;
    final excuse = excuses[item.id.hashCode.abs() % excuses.length];
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.light, color: Color(0xFFE57373)),
        title: Text(item.isVideo ? "This reel didn't make it" : "This one didn't develop"),
        content: Text(excuse, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy error report'),
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: errorReport(item))));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Error report copied. Paste it into a message.')));
            },
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Throw away')),
            ],
          ),
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

    // Tap a print, Polaroid or reel for a close look at it developing.
    Widget closeUp(Widget tray) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showDarkroomCloseUp(context, item.id),
      child: tray,
    );

    if (item.isVideo && !failed) {
      return closeUp(
        SizedBox(
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
        ),
      );
    }

    if (spec.isInstant && !failed) {
      // Instant film develops in the light: the picture surfaces through the
      // blue-grey sheet in front of you (eased between the 1 s ticks).
      return closeUp(
        SizedBox(
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
                          : Image.file(
                              File(thumb),
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                              gaplessPlayback: true,
                            ),
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
        ),
      );
    }

    if (!item.isVideo && !failed) {
      final stage = PrintTrayPainter.stageFor(processing ? 0 : progress);
      return closeUp(
        SizedBox(
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

/// A close look at one print (or Polaroid, or reel) in the darkroom: the
/// board greys out a little behind it and it carries on developing in
/// front of you. Tap anywhere to go back.
Future<void> showDarkroomCloseUp(BuildContext context, String id) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Back to the corkboard',
  barrierColor: Colors.black45,
  transitionDuration: const Duration(milliseconds: 240),
  pageBuilder: (context, _, _) => _DarkroomCloseUp(id: id),
  transitionBuilder: (context, a, _, child) => FadeTransition(
    opacity: a,
    child: ScaleTransition(
      scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
);

class _DarkroomCloseUp extends ConsumerWidget {
  const _DarkroomCloseUp({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(filmItemsProvider).value ?? const <MediaItem>[];
    final now = ref.watch(secondTickerProvider).value ?? DateTime.now();
    final item = items.where((m) => m.id == id).firstOrNull;
    const ink = Color(0xFFFF8A80);
    Widget body;
    var label = '';
    if (item == null) {
      body = const SizedBox.shrink();
    } else {
      final spec = CameraCatalog.byId(item.cameraId);
      final total = item.readyAt.difference(item.capturedAt).inMilliseconds.clamp(1, 1 << 31);
      final left = item.readyAt.difference(now);
      final processing = item.status == MediaStatus.processing;
      final progress = processing ? 0.0 : (1 - left.inMilliseconds / total).clamp(0.0, 1.0);
      final thumb = processing ? null : item.thumbPath;
      final mm = left.inMinutes.clamp(0, 99).toString();
      final ss = (left.inSeconds % 60).clamp(0, 59).toString().padLeft(2, '0');
      final done = !left.isNegative ? false : !processing;
      // Landscape is short: keep the close-up within the height too.
      final screen = MediaQuery.sizeOf(context);
      final width = math.min(math.min(screen.width * 0.82, screen.height * 0.62), 420.0);
      if (item.isVideo) {
        label = done ? 'Developed' : '${DevelopingTankPainter.nameFor(progress)}  $mm:$ss';
        body = SizedBox.square(
          dimension: width * 0.8,
          child: _TankTray(progress: progress),
        );
      } else if (spec.isInstant) {
        label = done
            ? 'Developed'
            : 'Developing  0:${left.inSeconds.clamp(0, 59).toString().padLeft(2, '0')}';
        body = SizedBox(
          width: width * 0.8,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: progress),
            duration: const Duration(seconds: 1),
            builder: (context, p, _) => InstantPrint(
              develop: p,
              picture: thumb == null
                  ? const SizedBox.shrink()
                  : Image.file(File(thumb), fit: BoxFit.cover, cacheWidth: 720, gaplessPlayback: true),
            ),
          ),
        );
      } else {
        final stage = PrintTrayPainter.stageFor(progress);
        label = done ? 'Developed' : (processing && left.isNegative ? 'Fixing…' : '${stage.name}  $mm:$ss');
        body = SizedBox(
          width: width,
          height: width * 1.25,
          child: _PrintTray(progress: progress, thumb: thumb, cacheWidth: 900, large: true),
        );
      }
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            body,
            const SizedBox(height: 14),
            if (label.isNotEmpty)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      decoration: TextDecoration.none,
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
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: PinImage(color));
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
                      child: Transform.scale(scale: 1 + pin * 0.8, child: PinImage(widget.pinColor)),
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
    unawaited(Haptics.selectionClick());
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
              // The front always sets the card's size (invisible while the
              // back shows), so turning it over never changes its shape.
              Visibility(
                visible: !showBack,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: widget.front,
              ),
              if (!showBack) ...[
                // The folded corner: the tap target for the easter egg.
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    // Generous target round a small corner: easy to hit
                    // without the fold itself getting bigger.
                    child: const SizedBox(
                      width: 46,
                      height: 46,
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: CustomPaint(size: Size(12, 12), painter: _DogEar()),
                      ),
                    ),
                  ),
                ),
              ] else
                // Mirror the back so its text reads correctly after the turn.
                Positioned.fill(
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggle,
                      child: widget.back,
                    ),
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
class _PrintBack extends ConsumerWidget {
  const _PrintBack({required this.item, this.instant = false});

  final MediaItem item;
  final bool instant;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = CameraCatalog.byId(item.cameraId);
    final owner = ref.watch(userNameProvider);
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The lab's rabbit, inked with the stamp.
                      const DarkroomMark(size: 14, color: Color(0xCC2B4C8C)),
                      const SizedBox(height: 2),
                      Text(
                        '${owner == null ? '' : 'FOR ${owner.toUpperCase()}\n'}$frame\n${spec.name.toUpperCase()}\nDEV $date',
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
                    ],
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
  const PrintStage(this.label, this.name, this.until, this.tray, this.liquid);

  /// Short, for the little trays in the strip.
  final String label;

  /// In full, for the close-up.
  final String name;

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
    PrintStage('DEV', 'Developing', 0.55, Color(0xFF8E2A22), Color(0xFF3A1A12)),
    PrintStage('STOP', 'Stop bath', 0.65, Color(0xFFD6CEC2), Color(0xFF4A3A22)),
    PrintStage('FIX', 'Fixing', 0.90, Color(0xFF6A6A6A), Color(0xFF2E2E30)),
    PrintStage('WASH', 'Washing', 1.01, Color(0xFF3F5D78), Color(0xFF1E3446)),
  ];

  static PrintStage stageFor(double p) => stages.firstWhere((s) => p < s.until, orElse: () => stages.last);

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn for the little strip trays; the close-up scales everything up.
    final k = (size.shortestSide / 84).clamp(1.0, 6.0);
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(6 * k));
    // Tray body (lip lighter than the well).
    canvas.drawRRect(r, Paint()..color = stage.tray);
    final well = RRect.fromRectAndRadius((Offset.zero & size).deflate(4 * k), Radius.circular(4 * k));
    canvas.drawRRect(well, Paint()..color = stage.liquid);
    // Ridges on the tray floor, seen through the chemistry.
    final ridge = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = k;
    for (var x = well.left + 6 * k; x < well.right - 4 * k; x += 7 * k) {
      canvas.drawLine(Offset(x, well.top + 3 * k), Offset(x, well.bottom - 3 * k), ridge);
    }
    // Gentle rocking: highlights drift across the surface (faster under the
    // running water of the wash).
    final speed = stage.label == 'WASH' ? 2.4 : 1.0;
    final glint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1.2 * k
      ..style = PaintingStyle.stroke;
    for (var n = 0; n < 3; n++) {
      final y = well.top + well.height * ((ripple * speed + n / 3) % 1.0);
      final path = Path()..moveTo(well.left + 2 * k, y);
      for (var x = well.left + 2 * k; x <= well.right - 2 * k; x += 4 * k) {
        path.lineTo(x, y + math.sin(x / k * 0.25 + ripple * math.pi * 2 * speed) * 1.4 * k);
      }
      canvas.drawPath(path, glint);
    }
    // Bamboo tongs resting on the lip.
    final tongs = Paint()
      ..color = const Color(0xFFD9B77A)
      ..strokeWidth = 2 * k
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width - 6 * k, 2 * k),
      Offset(size.width - 20 * k, size.height * 0.42),
      tongs,
    );
    canvas.drawLine(
      Offset(size.width - 2 * k, 6 * k),
      Offset(size.width - 16 * k, size.height * 0.46),
      tongs,
    );
  }

  @override
  bool shouldRepaint(PrintTrayPainter old) =>
      old.progress != progress || old.ripple != ripple || old.stage != stage;
}

/// A thin film of liquid moving over the print: broad soft sheen bands that
/// slosh to and fro with the rocking tray (or stream steadily across in the
/// wash), and fine wavy caustic lines riding on them.
class _WaterOverPaper extends CustomPainter {
  _WaterOverPaper(this.t, {required this.flowing}) : super(repaint: t);

  final Animation<double> t;
  final bool flowing;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final w = size.width, h = size.height;
    final phase = t.value * math.pi * 2;
    // Where the water front is: rocking back and forth, or streaming.
    final shift = flowing ? (t.value * 3 % 1.0) * w * 1.6 - w * 0.3 : math.sin(phase) * w * 0.35;
    for (var i = 0; i < 3; i++) {
      final x = (shift + i * w * 0.55) % (w * 1.6) - w * 0.3;
      final band = Rect.fromLTWH(x - w * 0.18, -h * 0.1, w * 0.36, h * 1.2);
      canvas.save();
      canvas.translate(band.center.dx, band.center.dy);
      canvas.rotate(0.35);
      canvas.translate(-band.center.dx, -band.center.dy);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.09),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(band),
      );
      canvas.restore();
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.10);
    for (var n = 0; n < 7; n++) {
      final y0 = h * (n + 0.5) / 7;
      final path = Path()..moveTo(0, y0);
      for (var x = 0.0; x <= w; x += 6) {
        path.lineTo(
          x,
          y0 +
              math.sin(x * 0.045 + phase * (flowing ? 3 : 1) + n * 1.7) * 3 +
              math.sin(x * 0.11 - phase + n) * 1.5,
        );
      }
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_WaterOverPaper old) => old.flowing != flowing;
}

/// The print in its tray: paper floating in the chemistry, the latent image
/// surfacing during the developer stage, all seen by red safelight.
class _PrintTray extends StatefulWidget {
  const _PrintTray({required this.progress, required this.thumb, this.cacheWidth = 160, this.large = false});

  final double progress;
  final String? thumb;
  final int cacheWidth;

  /// The close-up: a roomier tray, and the chemistry visibly washing over
  /// the paper.
  final bool large;

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
              borderRadius: BorderRadius.circular(widget.large ? 20 : 6),
            ),
            child: CustomPaint(
              painter: PrintTrayPainter(progress: p, ripple: _rock.value, stage: stage),
              child: child,
            ),
          ),
          child: Padding(
            padding: widget.large
                ? const EdgeInsets.fromLTRB(36, 42, 36, 46)
                : const EdgeInsets.fromLTRB(10, 12, 10, 14),
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
                      padding: EdgeInsets.all(widget.large ? 12 : 3),
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
                            cacheWidth: widget.cacheWidth,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    ),
                  // The chemistry washing over the paper as the tray rocks
                  // (a running stream in the wash).
                  if (widget.large)
                    IgnorePointer(
                      child: CustomPaint(painter: _WaterOverPaper(_rock, flowing: stage.label == 'WASH')),
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

/// "shake to clear", handwritten on a scrap of paper tucked into the board's
/// corner.
class _ShakeNote extends StatelessWidget {
  const _ShakeNote();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.07,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF4EBD6),
          borderRadius: BorderRadius.circular(1.5),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 5, offset: Offset(2, 3))],
        ),
        child: const Text(
          'shake to clear',
          style: TextStyle(fontFamily: 'Caveat', fontSize: 19, height: 1, color: Color(0xFF2B2A4A)),
        ),
      ),
    );
  }
}
