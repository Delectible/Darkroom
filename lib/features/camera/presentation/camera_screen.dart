import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sfx.dart';
import '../../../core/device/system_gestures.dart';
import '../../../core/device/upright.dart';
import '../../../core/providers.dart';
import '../../../core/theme/retro_theme.dart';
import '../../../core/theme/surfaces.dart';
import '../../cameras/domain/camera_spec.dart';
import '../../cameras/presentation/stock_selector_screen.dart';
import '../../corkboard/presentation/corkboard_screen.dart';
import '../../darkroom/application/darkroom_controller.dart';
import '../../sd_card/presentation/win98/explorer_screen.dart';
import '../../settings/application/settings_controllers.dart';
import '../../settings/presentation/settings_sheet.dart';
import '../application/camera_session_controller.dart';
import '../application/camera_ui_state.dart';
import '../application/capture_controller.dart';
import '../application/zoom_controller.dart';
import 'body_swap.dart';
import 'viewport.dart';
import 'widgets/camera_controls.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> with SingleTickerProviderStateMixin {
  // ---- Film <-> Digital: toss one camera aside, grab the other -------------
  //
  // Drag the body sideways (or tap the other camera peeking in from the
  // edge): it follows the thumb, and a flick or a long enough drag tosses it
  // off while the other body comes in on the same motion (SwapStage). Until
  // the toss commits, the live UI is the leaving body and the arriving one
  // is a picture of it from last time; on commit the leaving body becomes a
  // picture and the live UI switches mode in the arriving slot.

  final _bodyKey = GlobalKey();

  /// Swap progress: 0 = current body in hand, 1 = the other one.
  late final AnimationController _swap = AnimationController.unbounded(vsync: this);

  /// Physical feel of the settle: a little overshoot, no wobble.
  static const _spring = SpringDescription(mass: 1, stiffness: 170, damping: 21);

  /// Picture of the body that is leaving, once the toss has committed.
  ui.Image? _outgoing;

  /// Last picture of each body, slid in as the other camera while dragging.
  final Map<AppMode, ui.Image> _lastLook = {};

  bool _dragging = false;

  /// A toss is under way (taking the picture, then flying).
  bool _committing = false;

  /// The live UI has switched to the arriving body.
  bool _committed = false;
  double _raw = 0;

  bool get _swapBusy => _committing || _swap.isAnimating;

  /// Film keeps the digital body to its right (film leaves to the left);
  /// digital keeps the film body to its left.
  int _dirFor(AppMode mode) => mode == AppMode.film ? -1 : 1;

  double _travel() => SwapGeometry(MediaQuery.sizeOf(context).width).travel;

  @override
  void initState() {
    super.initState();
    unawaited(Sfx.cameraSwap.preload());
  }

  @override
  void dispose() {
    unawaited(GestureExclusion.clear());
    _swap.dispose();
    _outgoing?.dispose();
    for (final image in _lastLook.values) {
      image.dispose();
    }
    super.dispose();
  }

  /// Strips of both side edges, level with the peeking camera, that Android
  /// keeps its back gesture off so the other camera can be pulled in from
  /// the very edge. Elsewhere the edges stay the phone's.
  List<Rect> _peekBands(Size size) {
    final top = size.height * _ModePeek.topFraction - 20;
    const height = _ModePeek.height + 40;
    return [Rect.fromLTWH(0, top, 48, height), Rect.fromLTWH(size.width - 48, top, 48, height)];
  }

  Size? _excludedFor;

  /// Hands the peek strips to the camera screen (again after any screen on
  /// top of it, which gets the whole edge back).
  void _claimEdges() {
    if (!mounted) return;
    final media = MediaQuery.of(context);
    _excludedFor = media.size;
    unawaited(GestureExclusion.set(_peekBands(media.size), media.devicePixelRatio));
  }

  void _releaseEdges() {
    _excludedFor = null;
    unawaited(GestureExclusion.clear());
  }

  bool _canSwap() => !_swapBusy && !_selectorOpen && !ref.read(captureControllerProvider).isRecording;

  void _onDragStart(DragStartDetails d) {
    if (!_canSwap()) return;
    // Back gesture from the sides, notification shade from the top.
    final allowed = _peekBands(MediaQuery.sizeOf(context));
    if (SystemGestureZones.startsInEdge(context, d.globalPosition, allowed: allowed)) return;
    _raw = 0;
    _swap.value = 0;
    setState(() => _dragging = true);
    unawaited(HapticFeedback.selectionClick());
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    final dir = _dirFor(ref.read(appModeProvider));
    _raw = (_raw + (d.primaryDelta ?? 0) * dir / _travel()).clamp(-0.6, 1.15);
    // The wrong way only gives a little: the other camera isn't there.
    _swap.value = _raw >= 0 ? _raw : _raw * 0.25;
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final dir = _dirFor(ref.read(appModeProvider));
    final v = (d.primaryVelocity ?? 0) * dir / _travel();
    if (v > 1.1 || (_swap.value > 0.38 && v > -0.6)) {
      unawaited(_commitSwap(v));
    } else {
      unawaited(_settleBack(v));
    }
  }

  Future<void> _settleBack(double velocity) async {
    await _swap.animateWith(SpringSimulation(_spring, _swap.value, 0, velocity));
    // The spring stops within a hair of 0: land exactly, back at rest.
    if (mounted && !_committing) setState(() => _swap.value = 0);
  }

  /// Tap on the other camera: toss without a drag.
  void _tossByTap() {
    if (!_canSwap()) return;
    _swap.value = 0;
    setState(() => _dragging = false);
    unawaited(_commitSwap(2.4));
  }

  Future<void> _commitSwap(double velocity) async {
    if (_committing) return;
    _committing = true;
    _swap.stop();
    final from = ref.read(appModeProvider);
    final boundary = _bodyKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    ui.Image? still;
    try {
      // Lower resolution is plenty for something moving this fast.
      still = await boundary?.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context) * 0.6);
    } catch (_) {
      still = null;
    }
    if (!mounted) {
      still?.dispose();
      return;
    }
    Sfx.cameraSwap.play();
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _outgoing?.dispose();
      _outgoing = still;
      _committed = true;
      // Flips the mode synchronously (the save happens after), so this
      // frame already builds the new body in the arriving slot.
      unawaited(ref.read(appModeProvider.notifier).toggle());
    });
    await _swap.animateWith(SpringSimulation(_spring, _swap.value, 1, velocity));
    unawaited(HapticFeedback.lightImpact()); // it lands in your hands
    if (!mounted) return;
    setState(() {
      final shot = _outgoing;
      _outgoing = null;
      if (shot != null) {
        _lastLook.remove(from)?.dispose();
        _lastLook[from] = shot;
      }
      _committed = false;
      _committing = false;
      _swap.value = 0;
    });
  }

  /// Pushes a full-screen route with the camera released for its duration
  /// (saves battery and lets the gallery's video player own the media
  /// pipeline), then re-acquires on return.
  Future<void> _push(Widget page) async {
    final session = ref.read(cameraSessionProvider.notifier);
    if (ref.read(captureControllerProvider).isRecording) {
      await ref.read(captureControllerProvider.notifier).stopRecording();
    }
    session.setScreenVisible(false);
    if (!mounted) return;
    _releaseEdges();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    _claimEdges();
    session.setScreenVisible(true);
  }

  bool _selectorOpen = false;
  bool _swipeFromEdge = false;
  double _swipeStartY = 0;

  /// Film stock / camera picker. The camera is released while it is open and
  /// re-opened afterwards (with a new sensor mode if the body needs one).
  Future<void> _openSelector() async {
    if (_selectorOpen || ref.read(captureControllerProvider).isRecording) return;
    _selectorOpen = true;
    final session = ref.read(cameraSessionProvider.notifier);
    session.setScreenVisible(false);
    _releaseEdges();
    await showStockSelector(context, ref.read(appModeProvider));
    _claimEdges();
    _selectorOpen = false;
    session.setScreenVisible(true);
  }

  void _openGallery() {
    final mode = ref.read(appModeProvider);
    unawaited(_push(mode == AppMode.film ? const CorkboardScreen() : const ExplorerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    // Keep the session + darkroom clock alive while the camera screen exists.
    ref.watch(cameraSessionProvider);
    ref.watch(darkroomControllerProvider);
    // Keep the zoom motor alive (and resetting with each body) without
    // rebuilding the whole screen on every zoom step.
    ref.listen(zoomProvider, (_, _) {});

    ref.listen<String?>(pendingRouteProvider, (_, route) {
      if (route == 'corkboard') {
        ref.read(pendingRouteProvider.notifier).consume();
        unawaited(ref.read(appModeProvider.notifier).set(AppMode.film));
        unawaited(_push(const CorkboardScreen()));
      }
    });
    ref.listen<CaptureState>(captureControllerProvider, (prev, next) {
      final msg = next.message;
      if (msg != null && msg != prev?.message) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        ref.read(captureControllerProvider.notifier).clearMessage();
      }
    });

    final mode = ref.watch(appModeProvider);
    final palette = RetroPalette.forMode(mode);
    final screenSize = MediaQuery.sizeOf(context);
    if (_excludedFor != screenSize && !_selectorOpen && ModalRoute.of(context)?.isCurrent != false) {
      _excludedFor = screenSize;
      WidgetsBinding.instance.addPostFrameCallback((_) => _claimEdges());
    }

    // Instant theme: the new body slides in already in its own colours.
    return Theme(
      data: palette.toTheme(),
      child: Builder(
        builder: (context) {
          // Swipe up anywhere on the camera body to open the picker, except
          // from the bottom edge: that's the system "go home" gesture, and
          // the picker used to flash open as the app closed.
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (d) {
              final media = MediaQuery.of(context);
              final y = d.globalPosition.dy;
              // Home gesture at the bottom, notification shade at the top.
              _swipeFromEdge =
                  y > media.size.height - SystemGestureZones.bottom(media) ||
                  y < SystemGestureZones.top(media);
              _swipeStartY = d.globalPosition.dy;
            },
            onVerticalDragEnd: (d) {
              final travelled = _swipeStartY - (d.globalPosition.dy);
              if (_swipeFromEdge || travelled < 60) return;
              if ((d.primaryVelocity ?? 0) < -350) unawaited(_openSelector());
            },
            // Sideways: toss this camera aside for the other one.
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onHorizontalDragCancel: () {
              if (_dragging) _onDragEnd(DragEndDetails(primaryVelocity: 0));
            },
            child: Scaffold(
              body: Stack(
                children: [
                  // The desk the cameras rest on (seen between them mid-swap).
                  const Positioned.fill(child: ColoredBox(color: Color(0xFF0C0B0A))),
                  AnimatedBuilder(
                    animation: _swap,
                    builder: (context, child) {
                      final moving = _dragging || _committing || _swap.isAnimating || _swap.value != 0;
                      final other = mode == AppMode.film ? AppMode.digital : AppMode.film;
                      Widget picture(ui.Image? image, AppMode m) =>
                          image == null ? BodyStandIn(mode: m) : RawImage(image: image, fit: BoxFit.fill);
                      if (!moving) {
                        return SwapStage(
                          progress: 0,
                          dir: _dirFor(mode),
                          leaving: child!,
                          leavingMode: mode,
                          arriving: null,
                          arrivingMode: other,
                          liveArriving: false,
                        );
                      }
                      // After the commit, `mode` is already the arriving body.
                      return _committed
                          ? SwapStage(
                              progress: _swap.value,
                              dir: _dirFor(other),
                              leaving: picture(_outgoing, other),
                              leavingMode: other,
                              arriving: child,
                              arrivingMode: mode,
                              liveArriving: true,
                            )
                          : SwapStage(
                              progress: _swap.value,
                              dir: _dirFor(mode),
                              leaving: child!,
                              leavingMode: mode,
                              arriving: picture(_lastLook[other], other),
                              arrivingMode: other,
                              liveArriving: false,
                            );
                    },
                    child: RepaintBoundary(
                      key: _bodyKey,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Leatherette or brushed metal; the texture tile is rendered
                          // once per body. No cross-fade: the new body slides in whole.
                          Positioned.fill(
                            child: SurfaceTexture(
                              key: ValueKey(mode),
                              leather: mode == AppMode.film,
                              base: mode == AppMode.film ? palette.body : palette.bodyHighlight,
                              light: palette.bodyHighlight,
                              dark: palette.bodyShadow,
                            ),
                          ),
                          SafeArea(
                            child: Column(
                              children: [
                                _TopBar(onSettings: () => showSettingsSheet(context)),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                                    child: _ViewportBezel(mode: mode, child: const CameraViewport()),
                                  ),
                                ),
                                PickerCaret(onOpen: _openSelector),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                                  child: Row(
                                    children: [
                                      Expanded(child: StockLabel(onOpen: _openSelector)),
                                      // Every digital body has the same W|T rocker, so
                                      // nothing pops in or out when switching bodies.
                                      // Film bodies have no zoom at all.
                                      if (mode == AppMode.digital) ...[
                                        const SizedBox(width: 12),
                                        const ZoomRocker(),
                                      ],
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      GalleryButton(onOpen: _openGallery),
                                      const ShutterButton(),
                                      StockButton(onOpen: _openSelector),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _ModePeek(mode: mode, onSwap: _tossByTap),
                        ],
                      ),
                    ),
                  ),
                  const _DarkroomBannerOverlay(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(cameraSessionProvider);
    final spec = ref.watch(activeSpecProvider);
    final processing = ref.watch(captureProcessorProvider).pending;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          const FlashButton(),
          const SizedBox(width: 8),
          AspectButton(
            onCycle: () => unawaited(ref.read(cameraSettingsProvider.notifier).cycleAspect(spec.id)),
          ),
          const Spacer(),
          ValueListenableBuilder<int>(
            valueListenable: processing,
            // Only build the spinner while something is processing: an
            // invisible-but-mounted progress indicator keeps ticking and
            // forces a full-screen redraw on every vsync.
            builder: (context, n, _) => n == 0
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: RetroPalette.of(context).accent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('$n', style: TextStyle(color: RetroPalette.of(context).textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
          ),
          if (session.hasFrontCamera) ...[
            LensFlipButton(enabled: !ref.watch(captureControllerProvider).isRecording),
            const SizedBox(width: 8),
          ],
          BodyButton(
            tooltip: 'Settings',
            onTap: onSettings,
            child: const Upright(child: Icon(Icons.tune)),
          ),
        ],
      ),
    );
  }
}

/// Physical surround of the viewfinder: brass-edged eyepiece for film, LCD
/// bezel for digital.
class _ViewportBezel extends StatelessWidget {
  const _ViewportBezel({required this.mode, required this.child});

  final AppMode mode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.of(context);
    final film = mode == AppMode.film;
    return Container(
      padding: EdgeInsets.all(film ? 8 : 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(film ? 14 : 8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: film
              ? [p.metal, p.metalDark, p.metal.withValues(alpha: 0.8)]
              : [const Color(0xFF3A3F46), const Color(0xFF1A1D21)],
        ),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Container(
        decoration: BoxDecoration(color: p.screen, borderRadius: BorderRadius.circular(film ? 8 : 4)),
        child: child,
      ),
    );
  }
}

/// "Prints ready" banner. Hidden, it used to sit only just above the safe
/// area with no text, so an empty red box peeked out by the camera cutout.
/// It now parks well off-screen and keeps its last text while sliding away.
class _DarkroomBannerOverlay extends ConsumerStatefulWidget {
  const _DarkroomBannerOverlay();

  @override
  ConsumerState<_DarkroomBannerOverlay> createState() => _DarkroomBannerOverlayState();
}

class _DarkroomBannerOverlayState extends ConsumerState<_DarkroomBannerOverlay> {
  String _text = '';

  @override
  Widget build(BuildContext context) {
    final banner = ref.watch(darkroomControllerProvider);
    final visible = banner != null;
    if (visible) _text = banner.text;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -3),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: !visible,
            child: GestureDetector(
              onTap: () {
                ref.read(darkroomControllerProvider.notifier).dismissBanner();
                ref.read(pendingRouteProvider.notifier).request('corkboard');
              },
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A0B0B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFB71C1C)),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.light, color: Color(0xFFFF5252), size: 18),
                    const SizedBox(width: 10),
                    Text(
                      _text,
                      style: const TextStyle(color: Color(0xFFFFCDD2), fontWeight: FontWeight.w600),
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

/// The other camera, peeking in from the edge of the screen: a slice of its
/// body (leatherette or brushed metal) with its name. Tap it, or pull it in,
/// to swap cameras. Film keeps the digital one to its right; digital keeps
/// the film one to its left (the way the bodies slide).
class _ModePeek extends StatelessWidget {
  const _ModePeek({required this.mode, required this.onSwap});

  static const topFraction = 0.36;
  static const height = 150.0;

  final AppMode mode;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final other = mode == AppMode.film ? AppMode.digital : AppMode.film;
    final p = RetroPalette.forMode(other);
    final onRight = mode == AppMode.film;
    const w = 30.0, h = height;
    final radius = onRight
        ? const BorderRadius.horizontal(left: Radius.circular(12))
        : const BorderRadius.horizontal(right: Radius.circular(12));
    return Positioned(
      right: onRight ? 0 : null,
      left: onRight ? null : 0,
      top: MediaQuery.sizeOf(context).height * topFraction,
      child: Semantics(
        button: true,
        label: other == AppMode.film ? 'Switch to the film camera' : 'Switch to the digital camera',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Pulling it in is the body's own sideways drag (CameraScreen).
          onTap: onSwap,
          child: Padding(
            // Generous, invisible touch area around the slim tab.
            padding: EdgeInsets.only(left: onRight ? 14 : 0, right: onRight ? 0 : 14),
            child: Container(
              width: w,
              height: h,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SurfaceTexture(
                    leather: other == AppMode.film,
                    base: other == AppMode.film ? p.body : p.bodyHighlight,
                    light: p.bodyHighlight,
                    dark: p.bodyShadow,
                  ),
                  // Edge of the body catching the light.
                  Align(
                    alignment: onRight ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(width: 2, color: p.bodyHighlight.withValues(alpha: 0.7)),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(onRight ? Icons.chevron_left : Icons.chevron_right, size: 16, color: p.accent),
                      const SizedBox(height: 4),
                      RotatedBox(
                        quarterTurns: onRight ? 3 : 1,
                        child: Text(
                          other == AppMode.film ? 'FILM' : 'DIGITAL',
                          style: TextStyle(
                            color: p.text,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
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
