import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/diagnostics/debug_flags.dart';
import 'core/diagnostics/fps_meter.dart';
import 'core/diagnostics/launch_timer.dart';
import 'core/diagnostics/lag_watch.dart';
import 'core/device/upright.dart';
import 'core/navigation.dart';
import 'core/providers.dart';
import 'core/shaders/shader_library.dart';
import 'core/startup/launch_curtain.dart';
import 'core/theme/retro_theme.dart';
import 'features/camera/application/camera_session_controller.dart';
import 'features/camera/application/camera_ui_state.dart';
import 'features/camera/presentation/camera_screen.dart';
import 'features/camera/presentation/whole_body.dart';
import 'features/settings/application/settings_controllers.dart';
import 'features/help/how_it_works_screen.dart';
import 'features/onboarding/onboarding_screen.dart';

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

  DateTime? _liveSince;

  /// Lift the curtain once the camera is open with its look loaded (or
  /// won't open: no permission, no camera), or something else is on top
  /// (the tour, a shortcut's screen).
  bool _ready() {
    if (ref.read(sharedPrefsProvider).getBool(PrefKeys.onboarded) != true) return true;
    if (appNavigatorKey.currentState?.canPop() ?? false) return true;
    final status = ref.read(cameraSessionProvider).status;
    switch (status) {
      case SessionStatus.permissionDenied || SessionStatus.noCamera || SessionStatus.error:
        return true;
      case SessionStatus.idle || SessionStatus.initializing:
        return false;
      case SessionStatus.ready:
        // The stream's first frames take a moment to arrive after it
        // opens: counted from now, while the rest below still loads.
        _liveSince ??= DateTime.now();
        LaunchTimer.once('camera open');
    }
    var ready = true;
    if (ref.read(shaderProgramsProvider).value == null) {
      ready = false;
    } else {
      final spec = ref.read(activeSpecProvider);
      if (spec.film != null &&
          (ref.read(filmLutImageProvider(spec.id)).value == null ||
              ref.read(grainImageProvider).value == null)) {
        ready = false;
      } else {
        LaunchTimer.once('film look loaded');
      }
    }
    // With Fancy graphics, the 3D camera in hand (loading since main.dart).
    if (ref.read(globalSettingsProvider).controls3d) {
      final art = ref.read(wholeArtProvider);
      if (art.isLoading || !(art.value?.isReady(ref.read(appModeProvider)) ?? true)) ready = false;
    }
    if (!ready) return false;
    LaunchTimer.once('all loaded');
    return DateTime.now().difference(_liveSince!) > const Duration(milliseconds: 450);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Darkroom',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: ref.watch(perfOverlayProvider),
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
          child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: UprightApp(child: child!)),
        );
        if (!ref.watch(fpsMeterProvider)) return app;
        // Debug > FPS Counter: bottom left, clear of the frame graphs (top).
        return Stack(
          fit: StackFit.expand,
          children: [
            app,
            Positioned(
              left: 10,
              bottom: MediaQuery.paddingOf(context).bottom + 70,
              child: const Directionality(textDirection: TextDirection.ltr, child: FpsMeter()),
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
    if (prefs.getBool(PrefKeys.tourSkipped) != true) return;
    unawaited(prefs.remove(PrefKeys.tourSkipped));
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          // Goes by itself after 8 s (an action would keep it up), or the X.
          persist: false,
          showCloseIcon: true,
          content: const Text("New here? Here's how it works."),
          action: SnackBarAction(
            label: 'Show me',
            onPressed: () => appNavigatorKey.currentState?.push(HowItWorksScreen.route()),
          ),
        ),
      );
    });
  }
}
