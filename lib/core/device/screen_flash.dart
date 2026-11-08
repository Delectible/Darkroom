import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The front camera's flash: the screen lights up warm white at full
/// brightness for the shot (no flash unit faces the user), as phones do.
class ScreenFlash {
  ScreenFlash._();

  /// The light on screen, 0..1 ([ScreenFlashLight] draws it).
  static final light = ValueNotifier<double>(0);

  // (Android: MainActivity's display channel; iPhone: AppDelegate's device one)
  static final _channel = MethodChannel(Platform.isIOS ? 'darkroom/device' : 'darkroom/display');

  /// Long enough for the screen to come up and the camera's exposure to
  /// settle on the lit face.
  static const settle = Duration(milliseconds: 420);

  /// Lights the screen, waits for it to [settle], runs [shot], then lets
  /// the screen go back to how it was.
  static Future<T> during<T>(Future<T> Function() shot) async {
    light.value = 1;
    unawaited(_brightness(1));
    try {
      await Future<void>.delayed(settle);
      return await shot();
    } finally {
      light.value = 0;
      unawaited(_brightness(-1));
    }
  }

  static Future<void> _brightness(double v) async {
    try {
      await _channel.invokeMethod<void>('brightness', v);
    } catch (_) {
      // (tests, desktop: the light alone)
    }
  }
}

/// Over the whole app: the front flash's light.
class ScreenFlashLight extends StatelessWidget {
  const ScreenFlashLight({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ValueListenableBuilder<double>(
      valueListenable: ScreenFlash.light,
      builder: (context, v, _) => AnimatedOpacity(
        opacity: v,
        // (on at once, off with a short fall, like a lamp)
        duration: Duration(milliseconds: v > 0 ? 60 : 260),
        curve: Curves.easeOut,
        child: const ColoredBox(color: Color(0xFFFFF3E2), child: SizedBox.expand()),
      ),
    ),
  );
}
