import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera_session_controller.dart';
import 'camera_ui_state.dart';

/// Exposure compensation for the camera in hand, in stops (the film
/// viewfinder's exposure scale). It moves the phone's own automatic exposure
/// (the viewfinder and the shot alike); the film's look reads the scene's
/// real brightness back (PhotoJob.exposureComp), so a dark scene stays dark
/// to a slow film. Kept per camera while the app runs; a new launch starts
/// every camera at 0.
final exposureCompProvider = NotifierProvider<ExposureController, double>(ExposureController.new);

class ExposureController extends Notifier<double> {
  final Map<String, double> _byCamera = {};

  @override
  double build() {
    ref.listen<CameraSessionState>(cameraSessionProvider, (prev, next) {
      if (!identical(prev?.controller, next.controller)) unawaited(_apply());
    });
    ref.listen(activeSpecProvider, (_, spec) {
      state = _byCamera[spec.id] ?? 0;
      unawaited(_apply());
    });
    return _byCamera[ref.read(activeSpecProvider).id] ?? 0;
  }

  /// To [stops], on the camera's own steps.
  void set(double stops) {
    final spec = ref.read(activeSpecProvider);
    final range = spec.exposure;
    if (range == null) return;
    final v = range.snap(stops);
    if (v == state) return;
    _byCamera[spec.id] = v;
    state = v;
    unawaited(_apply());
  }

  Future<void> _apply() async {
    final CameraController? c = ref.read(cameraSessionProvider).controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      final lo = await c.getMinExposureOffset(), hi = await c.getMaxExposureOffset();
      await c.setExposureOffset(state.clamp(lo, hi));
    } catch (_) {
      // (closing, or no exposure control on this camera)
    }
  }
}
