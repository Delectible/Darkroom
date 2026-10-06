import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/upright.dart';
import '../../../core/processing/film/film_profile.dart';
import '../../camera/application/camera_ui_state.dart';
import '../../settings/application/settings_controllers.dart';
import '../domain/camera_catalog.dart';
import '../domain/camera_spec.dart';
import 'artwork/camera_artwork.dart';

/// Opens the full-screen film / camera picker (slides up; swipe down or the
/// chevron closes it).
Future<void> showStockSelector(BuildContext context, AppMode mode) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => StockSelectorScreen(mode: mode),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
        child: child,
      ),
    ),
  );
}

enum _Filter { all, color, mono, movie, photo, video }

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

class _StockSelectorScreenState extends ConsumerState<StockSelectorScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFF121212);
  static const _muted = Color(0xFF9A9A9A);

  _Filter _filter = _Filter.all;
  late List<CameraSpec> _specs;
  late PageController _pages;
  late int _index;

  /// Swipe-down-to-close offset.
  double _drag = 0;
  late final AnimationController _settle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..addListener(
        () => setState(() => _drag = _dragFrom * (1 - Curves.easeOutCubic.transform(_settle.value))),
      );
  double _dragFrom = 0;

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
    _settle.dispose();
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
    unawaited(HapticFeedback.selectionClick());
    unawaited(ref.read(selectedCameraProvider.notifier).select(widget.mode, _specs[i].id));
    setState(() {});
  }

  Future<void> _pickFilter() async {
    final options = _film
        ? const [_Filter.all, _Filter.color, _Filter.mono, _Filter.movie]
        : const [_Filter.all, _Filter.photo, _Filter.video];
    final picked = await showModalBottomSheet<_Filter>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => SafeArea(
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

  void _onDragUpdate(DragUpdateDetails d) {
    _settle.stop();
    setState(() => _drag = math.max(0, _drag + d.primaryDelta!));
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_drag > 140 || v > 700) {
      Navigator.of(context).pop();
      return;
    }
    _dragFrom = _drag;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final spec = _specs.isEmpty ? null : _specs[_index.clamp(0, _specs.length - 1)];
    final grain = spec?.film == null
        ? GrainStrength.normal
        : ref.watch(cameraSettingsProvider)[spec!.id]?.grain ?? GrainStrength.normal;
    final fade = (1 - _drag / 600).clamp(0.0, 1.0);

    return Material(
      color: _bg.withValues(alpha: fade),
      child: SafeArea(
        child: UprightBox(
          child: GestureDetector(
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: Transform.translate(
              offset: Offset(0, _drag),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 26),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (c, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a),
                          child: c,
                        ),
                      ),
                      child: Column(
                        key: ValueKey('${spec?.id}$grain'),
                        children: [
                          Text(
                            (spec?.name ?? '').toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            spec?.subtitle ?? '',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: _muted, fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            alignment: WrapAlignment.center,
                            children: [
                              if (spec != null && spec.recordsVideo)
                                _Tag(spec.isFilm ? 'MOVIE · 18 FPS' : 'VIDEO', const Color(0xFFE57373)),
                              if (grain != GrainStrength.normal)
                                _Tag(
                                  'GRAIN: ${grain.name.toUpperCase()}',
                                  grain == GrainStrength.strong
                                      ? const Color(0xFFFFB74D)
                                      : const Color(0xFF90CAF9),
                                ),
                            ],
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
