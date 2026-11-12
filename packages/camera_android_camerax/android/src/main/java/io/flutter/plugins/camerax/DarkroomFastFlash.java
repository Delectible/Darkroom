// DARKROOM PATCH (packages/camera_android_camerax/DARKROOM.md): the digital
// cameras' fast flash.

package io.flutter.plugins.camerax;

import androidx.annotation.NonNull;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/**
 * Armed from the app ("darkroom/fast_flash", arm: bool). An ImageCapture built while armed
 * fires the flash on its own still frame (FLASH_MODE_SINGLE, AE on), with CameraX's flash
 * off so there's no pre-flash metering, and captures for the lowest latency. The app then
 * recreates the ImageCapture (setJpegImageQuality) and sets the plugin's flash mode off.
 */
final class DarkroomFastFlash {
  private DarkroomFastFlash() {}

  static volatile boolean armed = false;

  static MethodChannel setUp(@NonNull BinaryMessenger messenger) {
    final MethodChannel channel = new MethodChannel(messenger, "darkroom/fast_flash");
    channel.setMethodCallHandler(
        (call, result) -> {
          if ("arm".equals(call.method)) {
            armed = Boolean.TRUE.equals(call.arguments);
            result.success(null);
          } else {
            result.notImplemented();
          }
        });
    return channel;
  }
}
