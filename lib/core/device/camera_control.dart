import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether this iPhone has the Camera Control button (iOS 18's capture
/// session supports on-device controls only there; AppDelegate). Read once
/// at launch. With it, the volume buttons are only ever the shutter, as the
/// Camera Control is: iOS reports its press as volume-down, so volume zoom
/// would have swallowed it (the setting is hidden).
class CameraControl {
  CameraControl._();

  static const _channel = MethodChannel('darkroom/device');

  static bool present = false;

  static Future<void> read() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      present = await _channel.invokeMethod<bool>('cameraControl') ?? false;
    } catch (_) {
      present = false;
    }
  }
}
