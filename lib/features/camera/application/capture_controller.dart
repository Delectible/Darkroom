import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/physical_orientation.dart';
import '../../../core/processing/capture_processor.dart';
import '../../../core/processing/photo_pipeline.dart';
import '../../../core/providers.dart';
import '../../cameras/domain/camera_spec.dart';
import '../../settings/application/settings_controllers.dart';
import 'camera_session_controller.dart';
import 'camera_ui_state.dart';

@immutable
class CaptureState {
  const CaptureState({
    this.busy = false,
    this.recordingSince,
    this.shutterCount = 0,
    this.flashFired = false,
    this.message,
  });

  /// A still is between shutter press and the file being handed off.
  final bool busy;
  final DateTime? recordingSince;

  /// Increments on every shutter press (drives the blink animation
  /// immediately, before the capture even returns => zero perceived lag).
  final int shutterCount;
  final bool flashFired;
  final String? message;

  bool get isRecording => recordingSince != null;

  CaptureState copyWith({
    bool? busy,
    DateTime? recordingSince,
    bool clearRecording = false,
    int? shutterCount,
    bool? flashFired,
    String? message,
  }) => CaptureState(
    busy: busy ?? this.busy,
    recordingSince: clearRecording ? null : (recordingSince ?? this.recordingSince),
    shutterCount: shutterCount ?? this.shutterCount,
    flashFired: flashFired ?? this.flashFired,
    message: message,
  );
}

class CaptureController extends Notifier<CaptureState> {
  Timer? _maxLengthTimer;
  CaptureContext? _recordingContext;

  @override
  CaptureState build() {
    final session = ref.read(cameraSessionProvider.notifier);
    session.beforeRelease = _finaliseRecordingOn;
    ref.onDispose(() {
      _maxLengthTimer?.cancel();
      session.beforeRelease = null;
    });
    return const CaptureState();
  }

  CaptureContext _context(CameraController c) {
    final spec = ref.read(activeSpecProvider);
    final local = ref.read(activeCameraSettingsProvider);
    return CaptureContext(
      spec: spec,
      aspect: spec.aspectLocked ? spec.defaultAspect : local.aspect,
      previewAspect: c.value.previewSize == null ? 4 / 3 : c.value.aspectRatio,
      flash: ref.read(activeFlashProvider),
      timestamp: spec.supportsTimestamp && local.timestamp,
      global: ref.read(globalSettingsProvider),
      grain: local.grain,
      // Gravity, not c.value.deviceOrientation: with the activity locked to
      // portrait the plugin keeps reporting portraitUp.
      rotationTurns: rotationTurnsFor(
        ref.read(physicalOrientationProvider),
        front: c.description.lensDirection == CameraLensDirection.front,
      ),
    );
  }

  /// Device orientation -> clockwise quarter turns that make the (portrait
  /// locked) capture upright. Front lenses rotate the other way, like the
  /// platforms' own JPEG-orientation formula (sensor -/+ device rotation).
  static int rotationTurnsFor(DeviceOrientation o, {required bool front}) {
    final back = switch (o) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 3, // phone turned CCW => rotate CCW
      DeviceOrientation.portraitDown => 2,
      DeviceOrientation.landscapeRight => 1,
    };
    return front ? (4 - back) % 4 : back;
  }

  CameraController? get _ready {
    final s = ref.read(cameraSessionProvider);
    final c = s.controller;
    if (!s.isReady || c == null || !c.value.isInitialized) return null;
    return c;
  }

  /// Still capture. UI feedback happens synchronously; the slow parts
  /// (sensor readout, file move, processing) are awaited off the gesture.
  /// The one shutter action: the camera style decides the medium.
  Future<void> shutter() => ref.read(activeSpecProvider).recordsVideo ? toggleRecording() : takePhoto();

  Future<void> takePhoto() async {
    final c = _ready;
    if (c == null || state.busy || c.value.isTakingPicture) return;
    if (ref.read(activeSpecProvider).recordsVideo) return;
    final ctx = _context(c);
    unawaited(HapticFeedback.mediumImpact());
    state = state.copyWith(
      busy: true,
      shutterCount: state.shutterCount + 1,
      flashFired: ctx.flash == FlashSetting.on,
    );
    try {
      final file = await c.takePicture();
      // Hand-off: moves the file into our cache + writes the queue row.
      // Processing then continues in the background isolate.
      await ref.read(captureProcessorProvider).enqueuePhoto(file.path, ctx);
      state = state.copyWith(busy: false);
      unawaited(_maybeAskNotificationPermission(ctx));
    } on CameraException catch (e) {
      state = state.copyWith(busy: false, message: 'Capture failed: ${e.description ?? e.code}');
    } catch (e) {
      state = state.copyWith(busy: false, message: 'Capture failed: $e');
    }
  }

  Future<void> startRecording() async {
    final c = _ready;
    if (c == null || state.isRecording || c.value.isRecordingVideo) return;
    final spec = ref.read(activeSpecProvider);
    if (!spec.recordsVideo) return;
    final ctx = _context(c);
    unawaited(HapticFeedback.heavyImpact());
    try {
      await c.prepareForVideoRecording();
      if (ctx.flash == FlashSetting.on) {
        try {
          await c.setFlashMode(FlashMode.torch);
        } on CameraException {
          // no torch on this lens
        }
      }
      await c.startVideoRecording();
      _recordingContext = ctx;
      state = state.copyWith(recordingSince: DateTime.now());
      _maxLengthTimer?.cancel();
      _maxLengthTimer = Timer(Duration(seconds: spec.videoMaxSeconds), stopRecording);
    } on CameraException catch (e) {
      state = state.copyWith(message: 'Could not start recording: ${e.description ?? e.code}');
    }
  }

  Future<void> stopRecording() async {
    final c = _ready;
    if (c == null || !c.value.isRecordingVideo) {
      state = state.copyWith(clearRecording: true);
      return;
    }
    await _finaliseRecordingOn(c);
  }

  Future<void> toggleRecording() => state.isRecording ? stopRecording() : startRecording();

  /// Stops the recording on [c] and queues the clip. Also used by the session
  /// controller when the app is backgrounded mid-recording.
  Future<void> _finaliseRecordingOn(CameraController c) async {
    _maxLengthTimer?.cancel();
    final since = state.recordingSince ?? DateTime.now();
    final ctx = _recordingContext ?? _context(c);
    _recordingContext = null;
    state = state.copyWith(clearRecording: true);
    try {
      final file = await c.stopVideoRecording();
      unawaited(HapticFeedback.lightImpact());
      try {
        await c.setFlashMode(FlashMode.off);
        await c.setFlashMode(switch (ctx.flash) {
          FlashSetting.auto => FlashMode.auto,
          FlashSetting.on => FlashMode.always,
          FlashSetting.off => FlashMode.off,
        });
      } on CameraException {
        // ignore
      }
      await ref
          .read(captureProcessorProvider)
          .enqueueVideo(file.path, ctx, startedAt: since, duration: DateTime.now().difference(since));
      unawaited(_maybeAskNotificationPermission(ctx));
    } on CameraException catch (e) {
      state = state.copyWith(message: 'Recording failed: ${e.description ?? e.code}');
    }
  }

  /// Asks for notification permission in context — the first time a shot
  /// actually goes into the darkroom — rather than on a cold first launch.
  Future<void> _maybeAskNotificationPermission(CaptureContext ctx) async {
    if (ctx.spec.mode != AppMode.film || !ctx.global.darkroomEnabled) return;
    if (!ctx.global.notificationsEnabled) return;
    final db = ref.read(appDatabaseProvider);
    if (await db.getValue('notifications.asked') != null) return;
    await db.setValue('notifications.asked', '1');
    await ref.read(notificationServiceProvider).requestPermission();
  }

  void clearMessage() {
    if (state.message != null) state = state.copyWith();
  }
}

final captureControllerProvider = NotifierProvider<CaptureController, CaptureState>(CaptureController.new);
