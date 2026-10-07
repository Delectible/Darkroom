import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show Drag;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/physical_orientation.dart';
import '../../../core/device/system_gestures.dart';
import '../../../core/device/upright.dart';
import '../../../core/processing/film/film_profile.dart';
import '../../camera/application/camera_ui_state.dart';
import '../../settings/application/settings_controllers.dart';
import '../domain/camera_catalog.dart';
import '../domain/camera_spec.dart';
import 'artwork/camera_artwork.dart';
import '../../../core/device/haptics.dart';

/// Opens the full-screen film / camera picker (slides up; swipe down or the
/// chevron closes it).
Future<void> showStockSelector(BuildContext context, AppMode mode) {
  // It rises from the bottom as the user holds the phone: held sideways
  // (the activity stays portrait) that's one of the screen's long edges.
  final turns = uprightQuarterTurns(ProviderScope.containerOf(context).read(physicalOrientationProvider));
  final from = switch (turns) {
    1 => const Offset(-1, 0),
    2 => const Offset(0, -1),
    3 => const Offset(1, 0),
    _ => const Offset(0, 1),
  };
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => StockSelectorScreen(mode: mode),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        // Closing is a trigger (no finger tracking), so it leaves at speed
        // and eases off as it goes, rather than starting from a standstill.
        position: Tween(begin: from, end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInQuad),
        ),
        child: child,
      ),
    ),
  );
}

enum _Filter { all, color, mono, movie, photo, video }

enum _Axis { undecided, horizontal, vertical }

/// The carousel is driven by the screen-wide pan handler below, so the
/// PageView itself must not claim drags (it still clamps and snaps to pages).
class _ExternalDragPhysics extends ClampingScrollPhysics {
  const _ExternalDragPhysics({super.parent});

  @override
  _ExternalDragPhysics applyTo(ScrollPhysics? ancestor) =>
      _ExternalDragPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => false;
}

/// Dark, minimal picker: the selected film canister (or camera body) sits
/// under a soft spotlight, neighbours peek in smaller and dimmer, name and a
/// one-line description underneath. Swiping selects immediately. Held
/// sideways, the whole picker lays out in landscape.
class StockSelectorScreen extends ConsumerStatefulWidget {
  const StockSelectorScreen({super.key, required this.mode});

  final AppMode mode;

  @override
  ConsumerState<StockSelectorScreen> createState() => _StockSelectorScreenState();
}

class _StockSelectorScreenState extends ConsumerState<StockSelectorScreen> {
  static const _bg = Color(0xFF121212);
  static const _muted = Color(0xFF9A9A9A);

  _Filter _filter = _Filter.all;
  late List<CameraSpec> _specs;
  late PageController _pages;
  late int _index;

  /// How far a downward (close) swipe has gone. Closing is a trigger: the
  /// sheet doesn't follow the finger, a clear swipe down sends it away.
  double _down = 0;

  bool get _film => widget.mode == AppMode.film;

  @override
  void initState() {
    super.initState();
    _specs = _filtered();
    final selected = ref.read(selectedCameraProvider)[widget.mode];
    _index = math.max(0, _specs.indexWhere((s) => s.id == selected));
    _pages = PageController(viewportFraction: 0.36, initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  List<CameraSpec> _filtered() => CameraCatalog.forMode(widget.mode).where((s) {
    return switch (_filter) {
      _Filter.all => true,
      _Filter.color => !s.isMono && !s.recordsVideo,
      _Filter.mono => s.isMono,
      _Filter.movie || _Filter.video => s.recordsVideo,
      _Filter.photo => !s.recordsVideo,
    };
  }).toList();

  String _filterName(_Filter f) => switch (f) {
    _Filter.all => _film ? 'All Films' : 'All Cameras',
    _Filter.color => 'Colour Film',
    _Filter.mono => 'Black & White',
    _Filter.movie => 'Movie Film',
    _Filter.photo => 'Photo Cameras',
    _Filter.video => 'Video Cameras',
  };

  void _select(int i) {
    _index = i;
    unawaited(Haptics.selectionClick());
    unawaited(ref.read(selectedCameraProvider.notifier).select(widget.mode, _specs[i].id));
    setState(() {});
  }

  Future<void> _pickFilter() async {
    final options = _film
        ? const [_Filter.all, _Filter.color, _Filter.mono, _Filter.movie]
        : const [_Filter.all, _Filter.photo, _Filter.video];
    final picked = await showUprightSheet<_Filter>(
      context,
      backgroundColor: const Color(0xFF1C1C1C),
      maxWidth: 380,
      builder: (context, {required landscape}) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final f in options)
              ListTile(
                title: Text(_filterName(f), style: const TextStyle(color: Colors.white)),
                trailing: f == _filter ? const Icon(Icons.check, color: Colors.white) : null,
                onTap: () => Navigator.pop(context, f),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == _filter || !mounted) return;
    final current = _specs[_index].id;
    final next = () {
      _filter = picked;
      return _filtered();
    }();
    if (next.isEmpty) return;
    setState(() {
      _specs = next;
      _index = math.max(0, _specs.indexWhere((s) => s.id == current));
    });
    if (_pages.hasClients) _pages.jumpToPage(_index);
    _select(_index);
  }

  // ---- gestures -------------------------------------------------------------
  // One pan handler covers the whole screen. Each drag is locked to an axis
  // once it has moved a little: only a clearly downward drag (within ~30° of
  // vertical) pulls the sheet closed; everything else scrolls the carousel.

  _Axis _axis = _Axis.undecided;
  Offset _travel = Offset.zero;
  Drag? _scroll;

  /// Vertical must beat horizontal by this factor (tan 60°) to count as a
  /// close gesture: the deadzone that keeps sideways swipes from closing.
  static const _verticalBias = 1.7;

  /// The drag began in the phone's back or notification strip: leave it to
  /// the phone.
  bool _systemDrag = false;

  void _onPanStart(DragStartDetails d) {
    _axis = _Axis.undecided;
    _travel = Offset.zero;
    _systemDrag = SystemGestureZones.startsInEdge(context, d.globalPosition);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_systemDrag) return;
    switch (_axis) {
      case _Axis.undecided:
        _travel += d.delta;
        if (_travel.distance < 10) return;
        final vertical = _travel.dy > 0 && _travel.dy.abs() > _travel.dx.abs() * _verticalBias;
        if (vertical) {
          _axis = _Axis.vertical;
          _down = _travel.dy;
        } else if (_pages.hasClients && _specs.length > 1) {
          _axis = _Axis.horizontal;
          _scroll = _pages.position.drag(
            DragStartDetails(globalPosition: d.globalPosition, localPosition: d.localPosition),
            () => _scroll = null,
          );
          _scrollBy(d, _travel.dx);
        }
      case _Axis.horizontal:
        _scrollBy(d, d.delta.dx);
      case _Axis.vertical:
        _down += d.delta.dy;
    }
  }

  void _scrollBy(DragUpdateDetails d, double dx) => _scroll?.update(
    DragUpdateDetails(
      globalPosition: d.globalPosition,
      localPosition: d.localPosition,
      delta: Offset(dx, 0),
      primaryDelta: dx,
    ),
  );

  void _onPanEnd(DragEndDetails d) {
    if (_systemDrag) return;
    switch (_axis) {
      case _Axis.horizontal:
        final vx = d.velocity.pixelsPerSecond.dx;
        _scroll?.end(
          DragEndDetails(
            velocity: Velocity(pixelsPerSecond: Offset(vx, 0)),
            primaryVelocity: vx,
          ),
        );
      case _Axis.vertical:
        final vy = d.velocity.pixelsPerSecond.dy;
        if (_down > 60 || vy > 500) {
          _axis = _Axis.undecided;
          Navigator.of(context).pop();
          return;
        }
      case _Axis.undecided:
        break;
    }
    _axis = _Axis.undecided;
  }

  void _onPanCancel() {
    _scroll?.cancel();
    _axis = _Axis.undecided;
  }

  @override
  Widget build(BuildContext context) {
    final spec = _specs.isEmpty ? null : _specs[_index.clamp(0, _specs.length - 1)];
    final grain = spec?.film == null
        ? GrainStrength.normal
        : ref.watch(cameraSettingsProvider)[spec!.id]?.grain ?? GrainStrength.normal;
    // Held sideways the hero flight from the camera screen would be worked
    // out in the unrotated frame (it flew sideways, then snapped): skip it.
    final upright = uprightQuarterTurns(ref.watch(physicalOrientationProvider)).isEven;

    return Material(
      color: _bg,
      child: SafeArea(
        child: UprightBox(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onPanCancel: _onPanCancel,
            child: HeroMode(
              enabled: upright,
              child: Column(
                children: [
                  // Grab handle.
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Top bar: filter · title · close.
                  SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Filter',
                          onPressed: _pickFilter,
                          icon: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.6),
                            ),
                            child: const Icon(Icons.filter_list, size: 16, color: Colors.white),
                          ),
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: Text(
                              _filterName(_filter),
                              key: ValueKey(_filter),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 32),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Spotlight.
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                radius: 0.62,
                                colors: [Color(0xFF2C2C2C), Color(0x00121212)],
                              ),
                            ),
                          ),
                        ),
                        LayoutBuilder(
                          builder: (context, box) {
                            final itemH = math.min(box.maxHeight * 0.78, 360.0);
                            final frac = (itemH / box.maxWidth * 0.95).clamp(0.24, 0.62);
                            if ((_pages.viewportFraction - frac).abs() > 0.01) {
                              final old = _pages;
                              _pages = PageController(viewportFraction: frac, initialPage: _index);
                              WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
                            }
                            return SizedBox(
                              height: itemH,
                              child: PageView.builder(
                                controller: _pages,
                                physics: const _ExternalDragPhysics(),
                                itemCount: _specs.length,
                                onPageChanged: _select,
                                itemBuilder: (context, i) => _Item(
                                  controller: _pages,
                                  index: i,
                                  onTap: () {
                                    if (i == _index) {
                                      Navigator.of(context).pop();
                                    } else {
                                      _pages.animateToPage(
                                        i,
                                        duration: const Duration(milliseconds: 280),
                                        curve: Curves.easeOutCubic,
                                      );
                                    }
                                  },
                                  child: Hero(
                                    tag: 'artwork-${_specs[i].id}',
                                    child: CameraArtwork(spec: _specs[i]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // Name, description and tags. Every row has a fixed height
                  // so items with and without tags cross-fade in place instead
                  // of the old/new blocks jumping to re-centre.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 26),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                      transitionBuilder: (c, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(a),
                          child: c,
                        ),
                      ),
                      child: Column(
                        key: ValueKey('${spec?.id}$grain'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 38,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                (spec?.name ?? '').toUpperCase(),
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 20,
                            child: Text(
                              spec?.subtitle ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: _muted, fontSize: 15),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 22,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 6,
                              children: [
                                if (spec?.pickerTag case final tag?) _Tag(tag, const Color(0xFFE57373)),
                                if (grain != GrainStrength.normal)
                                  _Tag(
                                    'GRAIN: ${grain.name.toUpperCase()}',
                                    grain == GrainStrength.strong
                                        ? const Color(0xFFFFB74D)
                                        : const Color(0xFF90CAF9),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

/// Small outlined label under the name ("MOVIE", "GRAIN: STRONG").
class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// One carousel slot: full size and bright in the centre, smaller and dimmer
/// as it moves away.
class _Item extends StatelessWidget {
  const _Item({required this.controller, required this.index, required this.onTap, required this.child});

  final PageController controller;
  final int index;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
      builder: (context, child) {
        var page = index.toDouble();
        if (controller.hasClients && controller.position.haveDimensions) {
          page = controller.page ?? page;
        }
        final d = (page - index).abs().clamp(0.0, 1.0);
        return Opacity(
          opacity: 1 - 0.55 * d,
          child: Transform.scale(scale: 1 - 0.32 * d, child: child),
        );
      },
    );
  }
}
