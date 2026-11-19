import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera_log.dart';
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
    // (the telephoto found: the zoom range keeps below it, or takes it)
    ref.listen(teleProvider, (_, _) => unawaited(_attach(_controller)));
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
      // (which lens it really is shows in its range: pinned lenses differ)
      CameraLog.add('zoom range ${hwMin.toStringAsFixed(2)}-${hwMax.toStringAsFixed(1)}x');
      _hwMin = hwMin;
      // Android: a back camera that zooms below 1x has an ultra-wide behind
      // it (iPhone: the session knows from the list of cameras).
      // (pinned to one lens, there's nothing below 1x: known from the lenses)
      final pinned = _pinned(c);
      if (defaultTargetPlatform == TargetPlatform.android &&
          c.description.lensDirection == CameraLensDirection.back &&
          !pinned) {
        ref.read(ultraWideProvider.notifier).set(hwMin < 1);
      }
      final widest =
          !pinned &&
          c.description.lensDirection == CameraLensDirection.back &&
          _wantsWidest(ref.read(filmLensProvider)) &&
          hwMin < 1;
      // Android's back camera changes to its telephoto by itself at that
      // lens's zoom: the tele converter goes straight there (a touch past,
      // to be sure it's the telephoto); every other lens stays well below,
      // so the phone never changes camera on its own.
      final teleAt = _teleAt(c);
      final tele = teleAt != null && ref.read(filmLensProvider) == LensKind.tele;
      final lo = tele ? math.min(teleAt * 1.04, hwMax) : (widest ? hwMin : math.max(1.0, hwMin));
      // Film bodies (no ZoomSpec) are fixed at 1x, even if the session was
      // left zoomed by a digital body that shared it.
      var hi = zoom == null ? lo : math.max(lo, math.min(zoom.max, hwMax));
      if (teleAt != null && !tele) hi = math.max(lo, math.min(hi, teleAt * 0.9));
      // (the fish-eye doesn't zoom: its circle is the picture)
      if (ref.read(filmLensProvider) == LensKind.fisheye) hi = lo;
      // Film: the same zoom (magnification) as the stock before, if this lens
      // goes that far; else as far as it does (2.1.4).
      final kept = _filmLevel;
      final level = widest || tele ? lo : (zoom?.wideMm != null && kept != null ? kept.clamp(lo, hi) : lo);
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

  /// Android, back camera: the zoom at which it changes to its telephoto
  /// (null: none, or not Android's switching kind of camera).
  double? _teleAt(CameraController c) =>
      defaultTargetPlatform == TargetPlatform.android &&
          c.description.lensDirection == CameraLensDirection.back &&
          !_pinned(c)
      ? ref.read(teleProvider)?.ratio
      : null;

  /// Android's back camera pinned to one physical lens (each lens its own,
  /// from 1x; a lens change restarts the camera rather than zooming).
  bool _pinned(CameraController c) =>
      defaultTargetPlatform == TargetPlatform.android &&
      c.description.lensDirection == CameraLensDirection.back &&
      (ref.read(teleProvider)?.pinnable ?? false);

  /// The lens before the last change (the tele converter on or off).
  LensKind? _lastLens;

  /// Where the ring was before a wide lens went on (back to it after).
  double? _beforeWide;

  void _lensChanged(LensKind lens) {
    lensMove = null;
    final was = _lastLens;
    _lastLens = lens;
    final c0 = _controller;
    // On or off the fish-eye (it doesn't zoom), or the tele converter
    // (Android): the range itself changes.
    if (c0 != null &&
        (lens == LensKind.fisheye ||
            was == LensKind.fisheye ||
            (_teleAt(c0) != null && (lens == LensKind.tele || was == LensKind.tele)))) {
      lensMove = _attach(c0);
      return;
    }
    final min = _hwMin;
    final c = _controller;
    // (pinned: the camera restarts on the new lens; its controller starts afresh)
    if (c != null && _pinned(c)) return;
    if (min == null || min >= 1 || c == null || !c.value.isInitialized) return;
    if (c.description.lensDirection != CameraLensDirection.back) return;
    // (a camera without a zoom stays fixed: at the ultra-wide, or at 1x)
    final fixed = ref.read(activeSpecProvider).zoom == null;
    final wide = _wantsWidest(lens);
    if (wide && state.min > min) {
      _beforeWide = state.level;
      state = state.copyWith(min: min, level: min, max: fixed ? min : null, changedAt: DateTime.now());
    } else if (!wide && state.min < 1) {
      final back = (_beforeWide ?? 1.0).clamp(1.0, fixed ? 1.0 : state.max);
      _beforeWide = null;
      state = state.copyWith(min: 1, level: back, max: fixed ? 1 : null, changedAt: DateTime.now());
    } else {
      return;
    }
    _lastSent = DateTime.now();
    // (awaited: the lens change opens the viewfinder once it's through)
    lensMove = c.setZoomLevel(state.level).catchError((Object _) {});
  }

  /// The zoom a lens change asked for, done once the camera has applied it.
  Future<void>? lensMove;

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
