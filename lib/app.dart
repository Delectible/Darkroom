import 'core/device/screen_flash.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/note_box.dart';

import 'core/device/upright.dart';
import 'core/diagnostics/fps_meter.dart';
import 'core/diagnostics/lag_watch.dart';
import 'core/diagnostics/launch_timer.dart';
import 'core/diagnostics/speed_test_run.dart';
import 'core/navigation.dart';
import 'core/providers.dart';
import 'core/startup/launch_curtain.dart';
import 'core/theme/retro_theme.dart';
import 'features/camera/application/camera_ui_state.dart';
import 'features/camera/presentation/camera_screen.dart';
import 'features/camera/presentation/launch_picture.dart';
import 'features/camera/presentation/whole_body.dart';
import 'features/help/how_it_works_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/settings/application/settings_controllers.dart';

class DarkroomApp extends ConsumerStatefulWidget {
  const DarkroomApp({super.key});

  @override
  ConsumerState<DarkroomApp> createState() => _DarkroomAppState();
}

class _DarkroomAppState extends ConsumerState<DarkroomApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Single source of truth for lifecycle: the camera session and the
    // darkroom clock both react to this provider.
    _lifecycle = AppLifecycleListener(onStateChange: (s) => ref.read(appLifecycleProvider.notifier).set(s));
    _lag.start();
  }

  /// Offers once to turn Fancy graphics off if the phone can't keep up.
  late final _lag = LagWatch(ref);

  @override
  void dispose() {
    _lifecycle.dispose();
    _lag.stop();
    super.dispose();
  }

  /// The launch curtain's line: a different one from last time.
  late final int _line = () {
    final prefs = ref.read(sharedPrefsProvider);
    final n = LaunchCurtain.lines.length;
    final last = prefs.getInt(PrefKeys.launchLine) ?? -1;
    final line = (last + 1 + math.Random().nextInt(n - 1)) % n;
    unawaited(prefs.setInt(PrefKeys.launchLine, line));
    return line;
  }();

  /// Lift the curtain once the camera is open with its look loaded (or
  /// won't open: no permission, no camera), or something else is on top
  /// (the tour, a shortcut's screen).
  bool _ready() {
    if (ref.read(sharedPrefsProvider).getBool(PrefKeys.onboarded) != true) return true;
    if (appNavigatorKey.currentState?.canPop() ?? false) return true;
    // (2.1: the camera itself isn't waited for: the curtain lifts onto its
    // viewfinder shut, which opens once the picture and its look are in,
    // like a camera powering up; camera_screen.dart, _checkLive)
    var ready = true;
    // With Fancy graphics, the 3D camera in hand (loading since main.dart),
    // or the launch picture of it standing in (the camera's own picture and
    // controls are live over it; the model takes over when it lands).
    if (ref.read(globalSettingsProvider).controls3d) {
      final art = ref.read(wholeArtProvider);
      final mode = ref.read(appModeProvider);
      final waiting = art.isLoading || !(art.value?.isReady(mode) ?? true);
      final poses = ref.read(wholeBodyProvider(mode))?.poses ?? '';
      if (waiting && !(art.value != null && LaunchPicture.liftOn(poses))) ready = false;
    }
    if (!ready) return false;
    LaunchTimer.once('all loaded');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Darkroom',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: RetroPalette.film.toTheme(),
      // The camera is portrait-only, even under a screen turned to landscape.
      home: const PortraitLock(child: _Home()),
      // The corkboard and Win98 turn to landscape with the phone.
      navigatorObservers: [UprightApp.observer],
      // Bigger system text is honoured up to 1.3x: past that the camera's
      // printed labels and the sheets' layouts break.
      // The launch screen stays up (with a line of chatter) until the camera
      // is live, then fades away.
      builder: (context, child) {
        final app = LaunchCurtain(
          isReady: _ready,
          line: _line,
          // (2.0.9: no time to read the line, a short fade: launches 0.6 s
          // quicker, nothing lost)
          minimum: const Duration(milliseconds: 300),
          // (2.0.15: gentler again, now the wait before it is short)
          fade: const Duration(milliseconds: 550),
          child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: UprightApp(child: child!)),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            app,
            // Debug > FPS Counter: bottom left.
            if (ref.watch(fpsMeterProvider))
              Positioned(
                left: 10,
                bottom: MediaQuery.paddingOf(context).bottom + 70,
                child: const Directionality(textDirection: TextDirection.ltr, child: FpsMeter()),
              ),
            // The front camera's flash (ScreenFlash): over everything.
            const Positioned.fill(child: ScreenFlashLight()),
            // Debug > Run Speed Tests: what's running; a tap stops it.
            Positioned(
              left: 12,
              right: 12,
              top: MediaQuery.paddingOf(context).top + 8,
              child: const SpeedTestBanner(),
            ),
          ],
        );
      },
    );
  }
}

/// The first-run tour once, then the camera.
class _Home extends ConsumerStatefulWidget {
  const _Home();

  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> {
  late bool _tour = ref.read(sharedPrefsProvider).getBool(PrefKeys.onboarded) != true;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: _tour
          ? OnboardingScreen(key: const ValueKey('tour'), onDone: _toured)
          : const CameraScreen(key: ValueKey('camera')),
    );
  }

  /// Skipped the moves: once the camera is up, a quiet "New here?".
  Future<void> _toured() async {
    // The 3D cameras have been loading since the tour opened: let them land
    // first so the camera comes up whole (rarely a wait).
    if (ref.read(globalSettingsProvider).controls3d) {
      try {
        await ref.read(wholeArtProvider.future).timeout(const Duration(seconds: 8));
      } catch (_) {
        // slow: the classic body shows until they land
      }
      if (!mounted) return;
    }
    setState(() => _tour = false);
    final prefs = ref.read(sharedPrefsProvider);
    if (prefs.getBool(PrefKeys.lowGraphicsNote) == true) {
      unawaited(prefs.remove(PrefKeys.lowGraphicsNote));
      Future<void>.delayed(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        Notes.show(
          'Simpler graphics to keep things smooth on this phone. Settings > Fancy graphics.',
          duration: const Duration(seconds: 8),
        );
      });
    }
    if (prefs.getBool(PrefKeys.tourSkipped) != true) return;
    unawaited(prefs.remove(PrefKeys.tourSkipped));
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      Notes.show(
        "New here? Here's how it works.",
        action: 'Show me',
        duration: const Duration(seconds: 8),
        onAction: () => appNavigatorKey.currentState?.push(HowItWorksScreen.route()),
      );
    });
  }
}
