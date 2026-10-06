import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/retro_theme.dart';
import 'features/camera/presentation/camera_screen.dart';

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
      theme: RetroPalette.film.toTheme(),
      home: const CameraScreen(),
    );
  }
}
