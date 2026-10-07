import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sfx.dart';
import '../../../core/device/system_gestures.dart';
import '../../../core/device/volume_keys.dart';
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
import '../../../core/device/haptics.dart';

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

  /// The body as it looked at rest, shown over the live one while it's
  /// dragged or springs back. A shader filter under the toss's 3D transform
  /// only moves its input, so the Super 8 strip's sprocket hole (drawn by
  /// the shader) slid around on its own; a snapshot moves as one piece.
  ui.Image? _moveStill;

  void _snapMoving() {
    if (_moveStill != null) return;
    try {
      final boundary = _bodyKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || boundary.debugNeedsPaint) return;
      _moveStill = boundary.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context) * 0.6);
    } catch (_) {
      _moveStill = null;
    }
  }

  void _dropMoving() {
    _moveStill?.dispose();
    _moveStill = null;
  }

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
    unawaited(Sfx.zoomMotor.preload());
    VolumeKeys.listen(_volume);
  }

  @override
  void dispose() {
    VolumeKeys.listen(null);
    unawaited(VolumeKeys.capture(false));
    unawaited(GestureExclusion.clear());
    _swap.dispose();
    _outgoing?.dispose();
    _moveStill?.dispose();
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
    unawaited(VolumeKeys.capture(true));
  }

  /// Another screen goes on top: the edges and the volume buttons are the
  /// phone's again until it closes.
  void _releaseEdges() {
    _excludedFor = null;
    unawaited(GestureExclusion.clear());
    unawaited(VolumeKeys.capture(false));
  }

  /// Volume buttons: the shutter, or (setting on, digital bodies) the zoom
  /// rocker, held to drive. Only while the camera itself is on screen;
  /// anywhere else they change the volume as usual.
  int _volumeZoomDir = 0;
  void _volume(bool up, bool pressed) {
    if (!pressed) {
      if (_volumeZoomDir != 0) {
        _volumeZoomDir = 0;
        ref.read(zoomProvider.notifier).stop();
      }
      return;
    }
    if (!mounted || _selectorOpen || _swapBusy || ModalRoute.of(context)?.isCurrent != true) return;
    final digital = ref.read(appModeProvider) == AppMode.digital;
    if (digital && ref.read(globalSettingsProvider).volumeZoom) {
      if (ref.read(zoomProvider).canZoom) {
        _volumeZoomDir = up ? 1 : -1;
        ref.read(zoomProvider.notifier).start(_volumeZoomDir);
      }
      return;
    }
    pressShutter(ref);
  }

  /// A body still springing back from a half-hearted swipe can be grabbed
  /// again straight away; only a toss in flight can't.
  bool _canSwap() => !_committing && !_selectorOpen && !ref.read(captureControllerProvider).isRecording;

  void _onDragStart(DragStartDetails d) {
    if (!_canSwap()) return;
    // Back gesture from the sides, notification shade from the top.
    final media = MediaQuery.of(context);
    final allowed = _peekBands(media.size);
    if (SystemGestureZones.startsInEdge(context, d.globalPosition, allowed: allowed)) return;
    // Nor from the home-gesture strip at the bottom (sliding along it
    // switches apps).
    if (d.globalPosition.dy > media.size.height - SystemGestureZones.bottom(media)) return;
    // Catch it mid-spring: carry on from where it is.
    _swap.stop();
    final at = _swap.value;
    _raw = at >= 0 ? at : 0;
    _dragging = true;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    final dir = _dirFor(ref.read(appModeProvider));
    final was = _swap.value;
    _raw = (_raw + (d.primaryDelta ?? 0) * dir / _travel()).clamp(-0.6, 1.15);
    // The way with no camera is the corkboard (film) / explorer (digital)
    // swipe: the body doesn't move at all that way, so nothing twitches
    // before the swipe triggers.
    if (was == 0 && _raw > 0) {
      _snapMoving();
      unawaited(Haptics.selectionClick());
    }
    _swap.value = math.max(0.0, _raw);
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final dir = _dirFor(ref.read(appModeProvider));
    final v = (d.primaryVelocity ?? 0) * dir / _travel();
    if (v > 1.1 || (_swap.value > 0.38 && v > -0.6)) {
      unawaited(_commitSwap(v));
    } else {
      // A clear swipe the way with no camera (right in film, left in
      // digital) brings in the corkboard / the explorer. It doesn't follow
      // the thumb: the swipe triggers it.
      final away = v < -1.1 || (_raw < -0.25 && v < 0.3);
      if (_swap.value != 0) unawaited(_settleBack(v));
      if (away) {
        unawaited(
          _push(ref.read(appModeProvider) == AppMode.film ? const CorkboardScreen() : const ExplorerScreen()),
        );
      }
    }
  }

  Future<void> _settleBack(double velocity) async {
    await _swap.animateWith(SpringSimulation(_spring, _swap.value, 0, velocity));
    // The spring stops within a hair of 0: land exactly, back at rest.
    if (mounted && !_committing) {
      setState(() {
        _swap.value = 0;
        _dropMoving();
      });
    }
  }

  /// Tap on the other camera: toss without a drag.
  void _tossByTap() {
    if (!_canSwap()) return;
    _swap.value = 0;
    _snapMoving();
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
    unawaited(Haptics.mediumImpact());
    setState(() {
      _outgoing?.dispose();
      _outgoing = still;
      _committed = true;
      // Flips the mode synchronously (the save happens after), so this
      // frame already builds the new body in the arriving slot.
      unawaited(ref.read(appModeProvider.notifier).toggle());
    });
    await _swap.animateWith(SpringSimulation(_spring, _swap.value, 1, velocity));
    unawaited(Haptics.lightImpact()); // it lands in your hands
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
      _dropMoving();
    });
  }

  /// Pushes a full-screen route with the camera released for its duration
  /// (saves battery and lets the gallery's video player own the media
  /// pipeline), then re-acquires on return.
  Future<void> _push(Widget page) async {
    final cork = page is CorkboardScreen;
    final session = ref.read(cameraSessionProvider.notifier);
    if (ref.read(captureControllerProvider).isRecording) {
      await ref.read(captureControllerProvider.notifier).stopRecording();
    }
    session.setScreenVisible(false);
    if (!mounted) return;
    _releaseEdges();
    if (cork) {
      Sfx.corkSwoosh.play();
      unawaited(Sfx.corkThud.preload());
    }
    final ModalRoute<void> route = cork
        ? CorkboardScreen.slideIn()
        : page is ExplorerScreen
        ? ExplorerScreen.powerOn()
        : MaterialPageRoute<void>(builder: (_) => page);
    final done = Navigator.of(context).push(route);
    // The framed board lands against the edge with a soft wooden thud
    // (started a beat early: the player takes a moment to start).
    final slide = route.animation;
    if (cork && slide != null) {
      void landed() {
        if (slide.status == AnimationStatus.forward && slide.value >= 0.93) {
          slide.removeListener(landed);
          Sfx.corkThud.play();
          unawaited(Haptics.lightImpact());
        }
      }

      slide.addListener(landed);
    }
    await done;
    if (cork) Sfx.corkSwoosh.play();
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
    // ...and its whir while it runs.
    ref.listen(zoomProvider.select((z) => z.direction), (_, dir) {
      if (dir != 0) {
        Sfx.zoomMotor.play();
      } else {
        Sfx.zoomMotor.stop();
      }
    });

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
                      final moving = _committing || _swap.isAnimating || _swap.value != 0;
                      final other = mode == AppMode.film ? AppMode.digital : AppMode.film;
                      Widget picture(ui.Image? image, AppMode m) =>
                          image == null ? BodyStandIn(mode: m) : RawImage(image: image, fit: BoxFit.fill);
                      // The live body, covered by its at-rest snapshot while it moves.
                      final still = moving ? _moveStill : null;
                      final live = Stack(
                        fit: StackFit.expand,
                        children: [
                          child!,
                          if (still != null) RawImage(image: still, fit: BoxFit.fill),
                        ],
                      );
                      if (!moving) {
                        return SwapStage(
                          progress: 0,
                          dir: _dirFor(mode),
                          leaving: live,
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
                              // Live underneath; while it flies in, its picture
                              // from last time on top (see _moveStill).
                              arriving: Stack(
                                fit: StackFit.expand,
                                children: [
                                  child,
                                  if (_lastLook[mode] case final look?)
                                    RawImage(image: look, fit: BoxFit.fill),
                                ],
                              ),
                              arrivingMode: mode,
                              liveArriving: true,
                            )
                          : SwapStage(
                              progress: _swap.value,
                              dir: _dirFor(mode),
                              leaving: live,
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
                                _TopBar(
                                  onSettings: () async {
                                    _releaseEdges();
                                    await showSettingsSheet(context);
                                    _claimEdges();
                                  },
                                ),
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
                        ],
                      ),
                    ),
                  ),
                  // The other camera's tag floats over the desk, not on the
                  // body: it tucks away as a swap starts and springs back
                  // out once the new body has settled.
                  AnimatedBuilder(
                    animation: _swap,
                    builder: (context, _) => _ModePeek(
                      mode: mode,
                      onSwap: _tossByTap,
                      hidden: _committing || _swap.isAnimating || _swap.value != 0,
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
class _ModePeek extends StatefulWidget {
  const _ModePeek({required this.mode, required this.onSwap, required this.hidden});

  static const topFraction = 0.36;
  static const height = 150.0;

  final AppMode mode;
  final VoidCallback onSwap;

  /// Tucked away off the edge (a swap is under way).
  final bool hidden;

  @override
  State<_ModePeek> createState() => _ModePeekState();
}

class _ModePeekState extends State<_ModePeek> with SingleTickerProviderStateMixin {
  /// 0 = out, 1 = tucked away past the screen edge.
  late final AnimationController _tuck = AnimationController(
    vsync: this,
    value: widget.hidden ? 1 : 0,
    duration: const Duration(milliseconds: 260),
  );

  // Shown for a tag that has tucked away, until it springs out again (the
  // mode flips while it's hidden).
  late AppMode _shownMode = widget.mode;

  @override
  void didUpdateWidget(_ModePeek old) {
    super.didUpdateWidget(old);
    if (widget.hidden && !old.hidden) {
      // A quick tuck, with a little wind-up.
      unawaited(_tuck.animateTo(1, duration: const Duration(milliseconds: 220), curve: Curves.easeInBack));
    } else if (!widget.hidden && old.hidden) {
      setState(() => _shownMode = widget.mode);
      // Out again on a spring: overshoots and settles.
      unawaited(_tuck.animateTo(0, duration: const Duration(milliseconds: 700), curve: Curves.elasticOut));
    } else if (!widget.hidden && widget.mode != _shownMode) {
      _shownMode = widget.mode;
    }
  }

  @override
  void dispose() {
    _tuck.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tuck,
      builder: (context, _) {
        final onRight = _shownMode == AppMode.film;
        // Slides out past its own edge (plus the touch padding).
        // (The spring's overshoot pushes it a little further in.)
        final shift = _tuck.value * 50;
        return Positioned(
          right: onRight ? -shift : null,
          left: onRight ? null : -shift,
          top: MediaQuery.sizeOf(context).height * _ModePeek.topFraction,
          child: IgnorePointer(ignoring: _tuck.value > 0.05, child: _tab(context, onRight)),
        );
      },
    );
  }

  Widget _tab(BuildContext context, bool onRight) {
    final mode = _shownMode;
    final onSwap = widget.onSwap;
    final other = mode == AppMode.film ? AppMode.digital : AppMode.film;
    final p = RetroPalette.forMode(other);
    const w = 30.0, h = _ModePeek.height;
    final radius = onRight
        ? const BorderRadius.horizontal(left: Radius.circular(12))
        : const BorderRadius.horizontal(right: Radius.circular(12));
    return Semantics(
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
    );
  }
}
