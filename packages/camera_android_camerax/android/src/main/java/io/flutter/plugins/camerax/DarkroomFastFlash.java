// DARKROOM PATCH (packages/camera_android_camerax/DARKROOM.md): the digital
// cameras' fast flash.

package io.flutter.plugins.camerax;

import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.CaptureResult;
import android.hardware.camera2.TotalCaptureResult;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
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

  @Nullable private static MethodChannel channel;
  private static final Handler main = new Handler(Looper.getMainLooper());

  /** A still captured with the fast flash: what the camera says it did, to the app's log. */
  static void report(@NonNull CaptureRequest request, @NonNull TotalCaptureResult result) {
    final String line =
        "asked "
            + name(request.get(CaptureRequest.FLASH_MODE), "OFF", "SINGLE", "TORCH")
            + " (AE "
            + name(request.get(CaptureRequest.CONTROL_AE_MODE), "OFF", "ON", "AUTO_FLASH", "ALWAYS_FLASH", "REDEYE", "EXTERNAL")
            + "), flash "
            + name(result.get(CaptureResult.FLASH_STATE), "UNAVAILABLE", "CHARGING", "READY", "FIRED", "PARTIAL")
            + ", AE "
            + name(result.get(CaptureResult.CONTROL_AE_STATE), "INACTIVE", "SEARCHING", "CONVERGED", "LOCKED", "FLASH_REQUIRED", "PRECAPTURE");
    main.post(
        () -> {
          final MethodChannel c = channel;
          if (c != null) c.invokeMethod("log", line);
        });
  }

  private static String name(@Nullable Integer v, String... names) {
    if (v == null) return "?";
    return v >= 0 && v < names.length ? names[v] : String.valueOf(v);
  }

  static MethodChannel setUp(@NonNull BinaryMessenger messenger) {
    final MethodChannel channel = new MethodChannel(messenger, "darkroom/fast_flash");
    DarkroomFastFlash.channel = channel;
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
