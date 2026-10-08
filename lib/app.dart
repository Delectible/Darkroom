import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/diagnostics/debug_flags.dart';
import 'core/device/upright.dart';
import 'core/providers.dart';
import 'core/theme/retro_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Darkroom',
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: ref.watch(perfOverlayProvider),
      theme: RetroPalette.film.toTheme(),
      home: const _Home(),
      // The corkboard and Win98 turn to landscape with the phone.
      navigatorObservers: [UprightApp.observer],
      builder: (context, child) => UprightApp(child: child!),
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
