import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';

import '../../../core/processing/photo_pipeline.dart' show FlashSetting;
import '../../cameras/domain/camera_spec.dart';
import 'camera_log.dart';

/// The digital cameras' flash on Android, the way a 2000s digicam fired:
/// at once, no metering pre-flash, at the exposure the preview had (the
/// phone's own sequence took about 2 s from press to capture on a Pixel).
///
/// Our copy of the camera plugin's Android side does it
/// (packages/camera_android_camerax/DARKROOM.md): armed, the next photo
/// capture it builds fires the flash on its own frame. Arming rebuilds that
/// capture (setJpegImageQuality) and the plugin's own flash is set off.
///
/// A camera opening builds a capture too, so it's disarmed before every
/// open ([beforeOpen]) and armed after, as the camera in hand needs.
class FastFlash {
  FastFlash._();

  static const _channel = MethodChannel('darkroom/fast_flash');

  /// The plugin answered (false: our copy isn't there, the phone's flash).
  static bool _available = true;

  /// Armed for this camera (by its id).
  static int? _armedFor;

  /// The capture's JPEG quality (the pipeline re-encodes it anyway).
  static const _quality = 95;

  /// Whether [spec]'s flash, set to [flash], fires this way on [lens].
  static bool applies(CameraSpec spec, CameraLensDirection lens, FlashSetting flash) =>
      Platform.isAndroid &&
      _available &&
      spec.mode == AppMode.digital &&
      !spec.recordsVideo &&
      lens == CameraLensDirection.back &&
      flash == FlashSetting.on;

  /// Armed for [c] now?
  static bool armedFor(CameraController c) => _armedFor == c.cameraId;

  /// Before a camera opens: its capture is built unarmed.
  static Future<void> beforeOpen() async {
    _armedFor = null;
    await _arm(false);
  }

  /// Arms or disarms [c]'s capture (rebuilding it if that changes).
  static Future<void> set(CameraController c, bool on) async {
    if (!Platform.isAndroid || on == armedFor(c)) return;
    if (!await _arm(on)) return;
    try {
      await CameraPlatform.instance.setJpegImageQuality(c.cameraId, _quality);
      _armedFor = on ? c.cameraId : null;
      CameraLog.add(on ? 'fast flash on' : 'fast flash off');
    } catch (e) {
      CameraLog.add('fast flash: $e');
      _armedFor = null;
      await _arm(false);
    } finally {
      // (only builds made just now are armed)
      if (on) await _arm(false);
    }
  }

  static Future<bool> _arm(bool on) async {
    if (!Platform.isAndroid || !_available) return false;
    try {
      await _channel.invokeMethod<void>('arm', on);
      return true;
    } on MissingPluginException {
      _available = false;
      return false;
    } on PlatformException {
      return false;
    }
  }
}
