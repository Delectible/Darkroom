import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera_session_controller.dart';
import 'camera_ui_state.dart';
import 'lens_controller.dart';
import '../../cameras/domain/camera_spec.dart';

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
    // Wide and fish-eye lenses take the phone's widest camera (below 1x, where
    // the phone switches to its ultra-wide itself); others go back.
    ref.listen(filmLensProvider, (_, lens) => _lensChanged(lens));
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
      _hwMin = hwMin;
      final widest = zoom?.wideMm != null && _wantsWidest(ref.read(filmLensProvider)) && hwMin < 1;
      final lo = widest ? hwMin : math.max(1.0, hwMin);
      // Film bodies (no ZoomSpec) are fixed at 1x, even if the session was
      // left zoomed by a digital body that shared it.
      final hi = zoom == null ? lo : math.max(lo, math.min(zoom.max, hwMax));
      // Film: the same zoom (magnification) as the stock before, if this lens
      // goes that far; else as far as it does (2.1.4).
      final kept = _filmLevel;
      final level = widest ? lo : (zoom?.wideMm != null && kept != null ? kept.clamp(lo, hi) : lo);
      state = ZoomState(level: level, min: lo, max: hi);
      await c.setZoomLevel(level);
    } catch (_) {
      // Lens without zoom support, or the session closed meanwhile: inert.
    }
  }

  /// The zoom the film ring was last set to, kept across stocks.
  double? _filmLevel;

  /// The phone's own widest zoom (below 1: its ultra-wide camera).
  double? _hwMin;

  static bool _wantsWidest(LensKind l) => l == LensKind.wide || l == LensKind.fisheye;

  /// Where the ring was before a wide lens went on (back to it after).
  double? _beforeWide;

  void _lensChanged(LensKind lens) {
    final min = _hwMin;
    final c = _controller;
    if (min == null || min >= 1 || c == null || !c.value.isInitialized) return;
    if (ref.read(activeSpecProvider).zoom?.wideMm == null) return;
    final wide = _wantsWidest(lens);
    if (wide && state.min > min) {
      _beforeWide = state.level;
      state = state.copyWith(min: min, level: min, changedAt: DateTime.now());
    } else if (!wide && state.min < 1) {
      final back = (_beforeWide ?? 1.0).clamp(1.0, state.max);
      _beforeWide = null;
      state = state.copyWith(min: 1, level: back, changedAt: DateTime.now());
    } else {
      return;
    }
    _lastSent = null;
    _send(state.level);
  }

  /// The film zoom ring: straight to [level] (clamped), as the finger turns it.
  void setLevel(double level) {
    if (!state.canZoom) return;
    final next = level.clamp(state.min, state.max);
    // (the widest the wide lenses reach isn't carried to the next stock)
    if (ref.read(activeSpecProvider).zoom?.wideMm != null && next >= 1) _filmLevel = next;
    if (next == state.level) return;
    state = state.copyWith(level: next, changedAt: DateTime.now());
    _send(next);
  }

  /// The ring let go: land the sensor exactly where it rests.
  void settle() {
    _lastSent = null;
    _send(state.level);
  }

  /// W (-1) or T (+1) pressed.
  void start(int direction) {
    if (!state.canZoom) return;
    // Already at the end of travel that way: nothing to drive (no blip of
    // motor and haptics every time a held finger twitches).
    if (direction > 0 ? state.level >= state.max : state.level <= state.min) return;
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
