import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/diagnostics/debug_flags.dart';
import 'core/diagnostics/fps_meter.dart';
import 'core/device/upright.dart';
import 'core/navigation.dart';
import 'core/providers.dart';
import 'core/shaders/shader_library.dart';
import 'core/startup/launch_curtain.dart';
import 'core/theme/retro_theme.dart';
import 'features/camera/application/camera_session_controller.dart';
import 'features/camera/application/camera_ui_state.dart';
import 'features/camera/presentation/camera_screen.dart';
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
  }

  @override
  void dispose() {
    _lifecycle.dispose();
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
    switch (ref.read(cameraSessionProvider).status) {
      case SessionStatus.permissionDenied || SessionStatus.noCamera || SessionStatus.error:
        return true;
      case SessionStatus.idle || SessionStatus.initializing:
        return false;
      case SessionStatus.ready:
        break;
    }
    if (ref.read(shaderProgramsProvider).value == null) return false;
    final spec = ref.read(activeSpecProvider);
    if (spec.film != null &&
        (ref.read(filmLutImageProvider(spec.id)).value == null ||
            ref.read(grainImageProvider).value == null)) {
      return false;
    }
    // The stream's first frames take a moment to arrive after it opens.
    final since = _liveSince ??= DateTime.now();
    return DateTime.now().difference(since) > const Duration(milliseconds: 450);
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
          ? OnboardingScreen(key: const ValueKey('tour'), onDone: () => setState(() => _tour = false))
          : const CameraScreen(key: ValueKey('camera')),
    );
  }
}
