import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cameras/domain/camera_spec.dart';
import 'camera_ui_state.dart';
import 'lens_controller.dart' show Remembered;

/// Which mode each camera's special is in (0: off), kept per camera while
/// the app runs. Multiple exposure keeps its own state
/// (multi_exposure_controller.dart); the rest live here.
final specialProvider = NotifierProvider<SpecialController, Map<String, int>>(SpecialController.new);

class SpecialController extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    unawaited(_restore());
    return const {};
  }

  /// Settings > keep lens and special: the specials from last time.
  Future<void> _restore() async {
    final kept = await Remembered.read(ref, Remembered.specialKey);
    if (kept.isEmpty || !ref.mounted) return;
    state = {...state, for (final e in kept.entries) if (e.value is int) e.key: e.value! as int};
  }

  int modeOf(String cameraId) => state[cameraId] ?? 0;

  /// The next mode of [spec]'s special (round to off).
  int step(CameraSpec spec) {
    final special = spec.special;
    if (special == null) return 0;
    final next = (modeOf(spec.id) + 1) % special.modes;
    state = {...state, spec.id: next};
    Remembered.write(ref, Remembered.specialKey, state);
    return next;
  }
}

/// The camera in hand's special mode (0: off).
final activeSpecialModeProvider = Provider<int>((ref) {
  final spec = ref.watch(activeSpecProvider);
  return ref.watch(specialProvider)[spec.id] ?? 0;
});

/// The camera in hand's colour effect (digital stills).
final activeColorFxProvider = Provider<ColorFx>((ref) {
  final spec = ref.watch(activeSpecProvider);
  if (spec.special != CameraSpecial.colorFx) return ColorFx.none;
  return ColorFx.values[ref.watch(activeSpecialModeProvider).clamp(0, ColorFx.values.length - 1)];
});
