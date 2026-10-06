import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera_session_controller.dart';
import 'camera_ui_state.dart';

@immutable
class ZoomState {
  const ZoomState({this.level = 1, this.min = 1, this.max = 1, this.direction = 0, this.changedAt});

  final double level;
  final double min;
  final double max;

  /// -1 zooming out (W), +1 zooming in (T), 0 idle.
  final int direction;

  /// Last time the level moved or a button was pressed (drives the overlay).
  final DateTime? changedAt;

  bool get canZoom => max > min;

  /// 0 at the wide end, 1 at the tele end (log scale, as the motor feels).
  double get fraction => canZoom ? math.log(level / min) / math.log(max / min) : 0;

  ZoomState copyWith({double? level, double? min, double? max, int? direction, DateTime? changedAt}) =>
      ZoomState(
        level: level ?? this.level,
        min: min ?? this.min,
        max: max ?? this.max,
        direction: direction ?? this.direction,
        changedAt: changedAt ?? this.changedAt,
      );
}

/// Motorised zoom: while W or T is held the lens moves at the body's fixed
/// rate ([ZoomSpec.endToEnd] for a full sweep) between 1x and the body's
/// limit (or the phone's, if lower). No pinch: like the real thing. Film
/// bodies have no zoom, so their range is 1-1.
class ZoomController extends Notifier<ZoomState> {
  Timer? _tick;
  DateTime? _lastTick;
  DateTime? _lastSent;

  @override
  ZoomState build() {
    // Every new controller (stock change, lens flip, resume) starts wide.
    ref.listen<CameraSessionState>(cameraSessionProvider, (prev, next) {
      if (!identical(prev?.controller, next.controller)) unawaited(_attach(next.controller));
    });
    // Switching between bodies that share a sensor mode keeps the controller:
    // still start the new body wide, with its own range.
    ref.listen(activeSpecProvider, (_, _) => unawaited(_attach(_controller)));
    ref.onDispose(() => _tick?.cancel());
    Future.microtask(() => _attach(ref.read(cameraSessionProvider).controller));
    return const ZoomState();
  }

  CameraController? get _controller => ref.read(cameraSessionProvider).controller;

  Future<void> _attach(CameraController? c) async {
    _stopTimer();
    state = const ZoomState();
    final zoom = ref.read(activeSpecProvider).zoom;
    if (c == null || !c.value.isInitialized) return;
    try {
      final hwMin = await c.getMinZoomLevel();
      final hwMax = await c.getMaxZoomLevel();
      if (!ref.mounted || !identical(_controller, c)) return;
      final lo = math.max(1.0, hwMin);
      // Film bodies (no ZoomSpec) are fixed at 1x, even if the session was
      // left zoomed by a digital body that shared it.
      final hi = zoom == null ? lo : math.max(lo, math.min(zoom.max, hwMax));
      state = ZoomState(level: lo, min: lo, max: hi);
      await c.setZoomLevel(lo);
    } catch (_) {
      // Lens without zoom support, or the session closed meanwhile: inert.
    }
  }

  /// W (-1) or T (+1) pressed.
  void start(int direction) {
    if (!state.canZoom) return;
    state = state.copyWith(direction: direction, changedAt: DateTime.now());
    _lastTick = DateTime.now();
    _tick ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _step());
  }

  /// Button released.
  void stop() {
    _stopTimer();
    if (state.direction == 0) return;
    state = state.copyWith(direction: 0, changedAt: DateTime.now());
    // The last step may have been throttled: land exactly where the UI is.
    _lastSent = null;
    _send(state.level);
  }

  void _stopTimer() {
    _tick?.cancel();
    _tick = null;
  }

  void _step() {
    final zoom = ref.read(activeSpecProvider).zoom;
    final now = DateTime.now();
    final dt = now.difference(_lastTick ?? now).inMicroseconds / 1e6;
    _lastTick = now;
    if (zoom == null || state.direction == 0 || !state.canZoom) return stop();
    // Constant speed in log space: every second covers the same "feel" of
    // magnification, like a geared zoom motor.
    final perSecond = math.log(state.max / state.min) / (zoom.endToEnd.inMicroseconds / 1e6);
    final next = math
        .exp(math.log(state.level) + state.direction * perSecond * dt)
        .clamp(state.min, state.max);
    state = state.copyWith(level: next, changedAt: now);
    _send(next);
    if (next <= state.min || next >= state.max) stop();
  }

  /// Fire-and-forget at ~30 Hz. CameraX supersedes an in-flight zoom request
  /// with the next one, so there is no queue to drain; awaiting each call
  /// (it completes only once the sensor has applied it, ~3 frames later)
  /// made the motor move in visible ~10 Hz steps.
  void _send(double level) {
    final now = DateTime.now();
    final atEnd = level <= state.min || level >= state.max;
    if (!atEnd && _lastSent != null && now.difference(_lastSent!) < const Duration(milliseconds: 30)) return;
    _lastSent = now;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    c.setZoomLevel(level).catchError((Object _) {}); // session closing: next one starts wide
  }
}

final zoomProvider = NotifierProvider<ZoomController, ZoomState>(ZoomController.new);
