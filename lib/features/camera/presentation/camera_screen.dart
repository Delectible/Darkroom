import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'viewport.dart';
import 'widgets/camera_controls.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
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
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    session.setScreenVisible(true);
  }

  bool _selectorOpen = false;

  /// Film stock / camera picker. The camera is released while it is open and
  /// re-opened afterwards (with a new sensor mode if the body needs one).
  Future<void> _openSelector() async {
    if (_selectorOpen || ref.read(captureControllerProvider).isRecording) return;
    _selectorOpen = true;
    final session = ref.read(cameraSessionProvider.notifier);
    session.setScreenVisible(false);
    await showStockSelector(context, ref.read(appModeProvider));
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

    return AnimatedTheme(
      data: palette.toTheme(),
      duration: const Duration(milliseconds: 350),
      child: Builder(
        builder: (context) {
          // Swipe up anywhere on the camera body to open the picker.
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -350) unawaited(_openSelector());
            },
            child: Scaffold(
              body: Stack(
                children: [
                  // Target palette, not the animating one: the texture tile is
                  // rendered once per palette, never per animation frame.
                  // Cross-fades leatherette <-> brushed metal with the theme.
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: SurfaceTexture(
                        key: ValueKey(mode),
                        leather: mode == AppMode.film,
                        base: mode == AppMode.film ? palette.body : palette.bodyHighlight,
                        light: palette.bodyHighlight,
                        dark: palette.bodyShadow,
                      ),
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
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                          child: Row(
                            children: [
                              Expanded(child: StockLabel(onOpen: _openSelector)),
                              const SizedBox(width: 12),
                              const ModeSwitch(),
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
            BodyButton(
              tooltip: 'Switch camera',
              enabled: !ref.watch(captureControllerProvider).isRecording,
              onTap: () => ref.read(lensProvider.notifier).toggle(),
              child: const Upright(child: Icon(Icons.cameraswitch_outlined)),
            ),
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

class _DarkroomBannerOverlay extends ConsumerWidget {
  const _DarkroomBannerOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banner = ref.watch(darkroomControllerProvider);
    final visible = banner != null;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -1.6),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
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
                    banner?.text ?? '',
                    style: const TextStyle(color: Color(0xFFFFCDD2), fontWeight: FontWeight.w600),
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
