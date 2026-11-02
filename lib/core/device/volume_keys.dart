import 'dart:io';

import 'package:flutter/services.dart';

/// The phone's volume buttons as camera buttons. Android: MainActivity
/// takes them before anything else sees them, but only while [capture] is
/// on, so everywhere else they still change the volume (Flutter's own key
/// events for them didn't arrive reliably, hence the native route). iOS
/// 17.2+: AppDelegate's capture-event interaction (volume down and the
/// iPhone 16's Camera Control press = down, volume up = up).
class VolumeKeys {
  VolumeKeys._();

  static const _channel = MethodChannel('darkroom/volume');
  static void Function(bool up, bool pressed)? _onKey;

  /// [onKey] gets (volume up?, pressed down / released) while captured.
  static void listen(void Function(bool up, bool pressed)? onKey) {
    _onKey = onKey;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'key') {
        final a = call.arguments as Map;
        _onKey?.call(a['up'] == true, a['down'] == true);
      }
    });
  }

  static Future<void> capture(bool on) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('capture', on);
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }
}
