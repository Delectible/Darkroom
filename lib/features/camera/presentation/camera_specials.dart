import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/haptics.dart';
import '../../cameras/domain/camera_spec.dart';
import '../application/capture_controller.dart';
import '../application/multi_exposure_controller.dart';
import '../application/special_controller.dart';
import 'viewport.dart' show CameraNote;

/// What the special's chip shows: lit or not, its text, and whether it's
/// filled (the first exposure is in; the self-timer is running).
@immutable
class SpecialChip {
  const SpecialChip({required this.on, required this.text, required this.fill});

  final bool on;
  final String text;
  final bool fill;

  @override
  bool operator ==(Object other) =>
      other is SpecialChip && other.on == on && other.text == text && other.fill == fill;

  @override
  int get hashCode => Object.hash(on, text, fill);
}

/// The button that changes per camera (film: the viewfinder's top-right
/// chip; digital: the OSD's key): pressing it, and what it shows.
class CameraSpecials {
  CameraSpecials._();

  static SpecialChip chip(WidgetRef ref, CameraSpec spec) {
    final special = spec.special;
    if (special == null) return const SpecialChip(on: false, text: '', fill: false);
    if (special == CameraSpecial.multipleExposure) {
      final me = ref.watch(multiExposureProvider);
      return SpecialChip(on: me.armed, text: special.mark, fill: me.armed && me.holding);
    }
    final mode = ref.watch(specialProvider)[spec.id] ?? 0;
    final countdown = special == CameraSpecial.selfTimer
        ? ref.watch(captureControllerProvider.select((s) => s.countdown))
        : null;
    return SpecialChip(
      on: mode > 0,
      text: countdown != null ? '$countdown' : special.labels[mode],
      fill: countdown != null,
    );
  }

  static void press(WidgetRef ref, CameraSpec spec) {
    final special = spec.special;
    if (special == null) return;
    unawaited(Haptics.lightImpact());
    if (special == CameraSpecial.multipleExposure) {
      final was = ref.read(multiExposureProvider);
      ref.read(multiExposureProvider.notifier).toggle();
      CameraNote.show(
        was.armed
            ? (was.holding ? 'Double exposure cancelled' : 'Multiple exposure off')
            : 'Multiple exposure: the next two shots share a frame',
      );
      return;
    }
    final mode = ref.read(specialProvider.notifier).step(spec);
    if (special == CameraSpecial.selfTimer && mode == 0) {
      ref.read(captureControllerProvider.notifier).cancelTimer();
    }
    CameraNote.show(switch (special) {
      CameraSpecial.lightLeak => mode > 0 ? 'Light leak: light gets into every frame' : 'Light leak off',
      CameraSpecial.selfTimer =>
        mode > 0
            ? 'Self-timer: the shutter fires ${CaptureController.selfTimerSeconds} s after you press it'
            : 'Self-timer off',
      CameraSpecial.fade => mode > 0 ? 'Fade: takes fade in and out' : 'Fade off',
      CameraSpecial.colorFx => const ['Colour', 'Black & white', 'Sepia'][mode],
      CameraSpecial.multipleExposure => '',
    });
  }
}
