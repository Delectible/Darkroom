import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/processing/photo_pipeline.dart';
import '../../../core/providers.dart';
import 'camera_log.dart';
import 'camera_ui_state.dart';

enum SessionStatus { idle, initializing, ready, permissionDenied, noCamera, error }

@immutable
class CameraSessionState {
  const CameraSessionState({
    this.status = SessionStatus.idle,
    this.controller,
    this.message,
    this.hasFrontCamera = false,
    this.audioEnabled = true,
  });

  final SessionStatus status;

  /// Non-null only while [status] is ready. Widgets must never cache it.
  final CameraController? controller;
  final String? message;
  final bool hasFrontCamera;
  final bool audioEnabled;

  bool get isReady => status == SessionStatus.ready && controller != null;

  CameraSessionState copyWith({
    SessionStatus? status,
    CameraController? controller,
    bool clearController = false,
    String? message,
    bool? hasFrontCamera,
    bool? audioEnabled,
  }) => CameraSessionState(
    status: status ?? this.status,
    controller: clearController ? null : (controller ?? this.controller),
    message: message,
    hasFrontCamera: hasFrontCamera ?? this.hasFrontCamera,
    audioEnabled: audioEnabled ?? this.audioEnabled,
  );
}

@immutable
class _Config {
  const _Config(this.lens, this.preset);

  final CameraLensDirection lens;
  final ResolutionPreset preset;

  @override
  bool operator ==(Object other) => other is _Config && other.lens == lens && other.preset == preset;

  @override
  int get hashCode => Object.hash(lens, preset);
}

/// Owns the one-and-only [CameraController].
///
/// "Camera is already in use" on Android happens when a second controller
/// opens the device before the first has fully released it — typically a
/// resume racing a pending dispose, a lens/preset switch during init, or an
/// init that completes after the app already went to the background.
///
/// This controller makes that impossible by construction:
///  * Callers never touch the CameraController lifecycle. They only change
///    the *desired* state (visible? which lens? which preset?).
///  * A single-flight reconcile loop drives the *actual* state towards the
///    desired one, one awaited step at a time. Bursts of lifecycle events
///    collapse into one final pass ([_dirty]).
///  * Release always (1) unmounts the preview, (2) finalises any recording,
///    (3) awaits dispose — before anything new is opened.
///  * An init that finishes after the target changed is disposed immediately.
///  * Transient failures (device still held by the previous session or
///    another app) are retried with exponential back-off; permission errors
///    are not retried until the user returns from Settings or taps retry.
class CameraSessionController extends Notifier<CameraSessionState> {
  CameraController? _controller;
  _Config? _controllerConfig;
  List<CameraDescription>? _cameras;

  bool _screenVisible = true;
  bool _appVisible = true;
  bool _permissionBlocked = false;
  bool _wasBackgrounded = false;
  bool _audioDenied = false;

  bool _looping = false;
  bool _dirty = false;
  bool _errorPending = false;

  /// Called with the outgoing controller right before it is disposed, so an
  /// in-progress recording can be stopped and kept (see CaptureController).
  Future<void> Function(CameraController controller)? beforeRelease;

  @override
  CameraSessionState build() {
    ref.listen<AppLifecycleState>(appLifecycleProvider, (_, next) => _onLifecycle(next));
    // Re-open with a different sensor mode / lens when the selection changes.
    ref.listen(activeSpecProvider, (_, _) => _kick());
    ref.listen(lensProvider, (_, _) => _kick());
    ref.listen(activeFlashProvider, (_, next) => _applyFlash(_controller, next));
    ref.onDispose(() {
      _screenVisible = false;
      final c = _controller;
      _controller = null;
      if (c != null) unawaited(_safeDispose(c));
    });
    _appVisible =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) == AppLifecycleState.resumed;
    Future.microtask(_kick);
    return const CameraSessionState();
  }

  // ---- desired-state inputs --------------------------------------------------

  /// The camera screen is (not) the top-most route.
  void setScreenVisible(bool visible) {
    if (visible != _screenVisible) CameraLog.add(visible ? 'screen shown' : 'screen covered');
    _screenVisible = visible;
    _kick();
  }

  /// "Grant access" button.
  void retry() {
    _permissionBlocked = false;
    _kick();
  }

  void _onLifecycle(AppLifecycleState s) {
    CameraLog.add('app ${s.name}');
    switch (s) {
      case AppLifecycleState.resumed:
        _appVisible = true;
        // Coming back from the background (e.g. from the Settings app) is
        // the moment to try again after a permission denial. A mere
        // inactive->resumed blip (the permission dialog itself) is not.
        if (_wasBackgrounded) _permissionBlocked = false;
        _wasBackgrounded = false;
      case AppLifecycleState.inactive:
        // Not a reason to close the camera: Android reports "inactive" for
        // any focus blip (notification shade, system dialogs, the camera
        // privacy chip...), and closing/reopening on each one made the
        // viewfinder drop out over and over on a Pixel 9 Pro. Only a real
        // background (hidden / paused) releases it.
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _appVisible = false;
        _wasBackgrounded = true;
    }
    _kick();
  }

  bool get _wantActive => _screenVisible && _appVisible && !_permissionBlocked;

  _Config get _wantConfig {
    final spec = ref.read(activeSpecProvider);
    return _Config(ref.read(lensProvider), presetFor(spec.quality));
  }

  // ---- reconcile loop --------------------------------------------------------

  void _kick() {
    if (_looping) {
      _dirty = true;
      return;
    }
    _looping = true;
    unawaited(_loop());
  }

  Future<void> _loop() async {
    try {
      do {
        _dirty = false;
        await _reconcile();
      } while (_dirty && ref.mounted);
    } catch (e, st) {
      debugPrint('Camera reconcile failed: $e\n$st');
    } finally {
      _looping = false;
    }
  }

  Future<void> _reconcile() async {
    if (!ref.mounted) return;
    if (!_wantActive) {
      await _release();
      return;
    }
    final want = _wantConfig;
    final c = _controller;
    if (c != null && _controllerConfig == want && c.value.isInitialized && !c.value.hasError) {
      return;
    }
    await _release();
    if (_dirty) return; // target moved while releasing; loop again
    await _acquire(want);
  }

  Future<void> _acquire(_Config cfg) async {
    state = state.copyWith(status: SessionStatus.initializing, clearController: true);
    try {
      _cameras ??= await availableCameras();
    } on CameraException catch (e) {
      state = state.copyWith(status: SessionStatus.error, message: e.description);
      return;
    }
    final cams = _cameras!;
    if (cams.isEmpty) {
      state = state.copyWith(status: SessionStatus.noCamera, message: 'No camera found');
      return;
    }
    final desc = cams.firstWhere((c) => c.lensDirection == cfg.lens, orElse: () => cams.first);
    CameraLog.add('open ${cfg.lens.name} ${cfg.preset.name}');
    final hasFront = cams.any((c) => c.lensDirection == CameraLensDirection.front);

    const maxAttempts = 4;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!ref.mounted || _dirty || !_wantActive) return;
      final c = CameraController(desc, cfg.preset, enableAudio: !_audioDenied);
      try {
        await c.initialize();
      } on CameraException catch (e) {
        CameraLog.add('open failed: ${e.code} ${e.description ?? ''}');
        await _safeDispose(c);
        if (_isCameraPermissionError(e.code)) {
          _permissionBlocked = true;
          state = state.copyWith(
            status: SessionStatus.permissionDenied,
            message: 'Camera access is off. Allow it in Settings to start shooting.',
          );
          return;
        }
        if (_isAudioPermissionError(e.code) && !_audioDenied) {
          // Keep shooting: videos will simply be silent.
          _audioDenied = true;
          continue;
        }
        if (attempt < maxAttempts - 1) {
          // Most likely the HAL hasn't released the previous session yet.
          await Future<void>.delayed(Duration(milliseconds: 250 * (1 << attempt)));
          continue;
        }
        state = state.copyWith(status: SessionStatus.error, message: e.description ?? e.code);
        return;
      }

      // The world may have changed while we were awaiting initialize().
      if (!ref.mounted || !_wantActive || _wantConfig != cfg) {
        CameraLog.add('opened, but no longer wanted');
        await _safeDispose(c);
        _dirty = true;
        return;
      }
      // Keep the sensor output portrait no matter how the phone is held: our
      // UI never rotates, and an unlocked iOS session would rotate the
      // preview buffer itself. Landscape shots are re-oriented in processing
      // from CameraValue.deviceOrientation (see CaptureController).
      try {
        await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } on CameraException {
        // Not fatal: the processing pipeline also handles landscape buffers.
      }
      _controller = c;
      _controllerConfig = cfg;
      CameraLog.add('ready');
      c.addListener(_onControllerValue);
      await _applyFlash(c, ref.read(activeFlashProvider));
      state = CameraSessionState(
        status: SessionStatus.ready,
        controller: c,
        hasFrontCamera: hasFront,
        audioEnabled: !_audioDenied,
      );
      return;
    }
  }

  Future<void> _release() async {
    final c = _controller;
    if (c == null) {
      if (state.status == SessionStatus.ready || state.status == SessionStatus.initializing) {
        state = state.copyWith(status: SessionStatus.idle, clearController: true);
      }
      return;
    }
    _controller = null;
    _controllerConfig = null;
    c.removeListener(_onControllerValue);
    CameraLog.add('close');

    // 1. Unmount the preview so nothing builds a disposed controller. When
    //    the app is backgrounded no frame may come, so don't wait forever.
    state = state.copyWith(status: SessionStatus.idle, clearController: true);
    await WidgetsBinding.instance.endOfFrame.timeout(const Duration(milliseconds: 120), onTimeout: () {});

    // 2. Keep an in-progress recording instead of losing it.
    if (c.value.isRecordingVideo) {
      try {
        await beforeRelease?.call(c);
      } catch (e) {
        debugPrint('Finalising recording failed: $e');
      }
    }

    // 3. Fully release the hardware before anyone may open it again.
    await _safeDispose(c);
  }

  void _onControllerValue() {
    final c = _controller;
    if (c == null) return;
    // Device evicted us (another app grabbed the camera, HAL error...).
    if (c.value.hasError && !c.value.isRecordingVideo && !_errorPending) {
      debugPrint('Camera error: ${c.value.errorDescription}');
      CameraLog.add('camera error: ${c.value.errorDescription}');
      // Give the device a moment before reopening, so an error storm can't
      // turn into an open/close loop.
      _errorPending = true;
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        _errorPending = false;
        if (ref.mounted) _kick();
      });
    }
  }

  Future<void> _applyFlash(CameraController? c, FlashSetting flash) async {
    if (c == null || !c.value.isInitialized || c.value.isRecordingVideo) return;
    try {
      await c.setFlashMode(switch (flash) {
        FlashSetting.auto => FlashMode.auto,
        FlashSetting.on => FlashMode.always,
        FlashSetting.off => FlashMode.off,
      });
    } on CameraException {
      // Front cameras usually have no flash unit; the simulated flash grade
      // still applies in processing.
    }
  }

  static Future<void> _safeDispose(CameraController c) async {
    try {
      await c.dispose();
    } catch (e) {
      debugPrint('Camera dispose: $e');
    }
  }

  static bool _isCameraPermissionError(String code) => const {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
    'cameraPermission',
  }.contains(code);

  static bool _isAudioPermissionError(String code) =>
      const {'AudioAccessDenied', 'AudioAccessDeniedWithoutPrompt', 'AudioAccessRestricted'}.contains(code);
}

final cameraSessionProvider = NotifierProvider<CameraSessionController, CameraSessionState>(
  CameraSessionController.new,
);
