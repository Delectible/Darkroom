import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cameras/domain/camera_spec.dart';
import 'camera_ui_state.dart';

/// Which mode each camera's special is in (0: off), kept per camera while
/// the app runs. Multiple exposure keeps its own state
/// (multi_exposure_controller.dart); the rest live here.
final specialProvider = NotifierProvider<SpecialController, Map<String, int>>(SpecialController.new);

class SpecialController extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  int modeOf(String cameraId) => state[cameraId] ?? 0;

  /// The next mode of [spec]'s special (round to off).
  int step(CameraSpec spec) {
    final special = spec.special;
    if (special == null) return 0;
    final next = (modeOf(spec.id) + 1) % special.modes;
    state = {...state, spec.id: next};
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
