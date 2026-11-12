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
import androidx.camera.camera2.interop.Camera2CameraControl;
import androidx.camera.camera2.interop.CaptureRequestOptions;
import androidx.camera.camera2.interop.ExperimentalCamera2Interop;
import androidx.camera.core.ImageCapture;
import androidx.camera.core.impl.CameraInternal;
import androidx.annotation.OptIn;
import com.google.common.util.concurrent.ListenableFuture;
import java.util.Collections;
import java.util.Set;
import java.util.WeakHashMap;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/**
 * Armed from the app ("darkroom/fast_flash", arm: bool; release when off). An ImageCapture built while armed
 * fires the flash on its own still frame (FLASH_MODE_SINGLE, AE on), with CameraX's flash
 * off so there's no pre-flash metering, and captures for the lowest latency. The app then
 * recreates the ImageCapture (setJpegImageQuality) and sets the plugin's flash mode off.
 */
@OptIn(markerClass = ExperimentalCamera2Interop.class)
final class DarkroomFastFlash {
  private DarkroomFastFlash() {}

  static volatile boolean armed = false;

  /** ImageCaptures built armed. */
  private static final Set<ImageCapture> armedCaptures =
      Collections.synchronizedSet(Collections.newSetFromMap(new WeakHashMap<>()));

  /** The camera control whose repeating requests are kept from flashing. */
  @Nullable private static Camera2CameraControl quieted;

  static void mark(@NonNull ImageCapture capture) {
    armedCaptures.add(capture);
  }

  /**
   * An armed capture's FLASH_MODE_SINGLE reaches the preview's repeating requests too (and fired
   * there). Camera2CameraControl's options override those for repeating requests, while a still's
   * own options still win on the still (CaptureConfigAdapter: single capture options over session
   * options), so FLASH_MODE_OFF set here leaves the flash to the photo. Returns when applied (null:
   * nothing to wait for).
   */
  @Nullable
  static ListenableFuture<Void> quietPreview(@NonNull ImageCapture capture) {
    if (!armedCaptures.contains(capture)) return null;
    try {
      final CameraInternal camera = capture.getCamera();
      if (camera == null) return null;
      final Camera2CameraControl control = Camera2CameraControl.from(camera.getCameraControl());
      if (control == quieted) return null;
      quieted = control;
      return control.addCaptureRequestOptions(
          new CaptureRequestOptions.Builder()
              .setCaptureRequestOption(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF)
              .build());
    } catch (RuntimeException e) {
      return null;
    }
  }

  /** Disarmed: the camera's own requests back as CameraX makes them (its torch, say). */
  private static void unquiet() {
    final Camera2CameraControl control = quieted;
    quieted = null;
    if (control != null) {
      try {
        control.clearCaptureRequestOptions();
      } catch (RuntimeException e) {
        // camera gone
      }
    }
  }

  @Nullable private static MethodChannel channel;
  private static final Handler main = new Handler(Looper.getMainLooper());

  /** A still captured with the fast flash: what the camera says it did, to the app's log. */
  static void report(@NonNull CaptureRequest request, @NonNull TotalCaptureResult result) {
    final Integer intent = request.get(CaptureRequest.CONTROL_CAPTURE_INTENT);
    // (the preview's frames: only the photo itself is worth a line)
    if (intent != null && intent == CaptureRequest.CONTROL_CAPTURE_INTENT_PREVIEW) return;
    final String line =
        name(intent, "CUSTOM", "PREVIEW", "STILL", "RECORD", "SNAPSHOT", "ZSL", "MANUAL", "MOTION")
            + ": asked "
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
          } else if ("release".equals(call.method)) {
            // (off for good, or a camera opening: arm(false) alone only
            // ends an armed build, whose capture stays in use)
            armed = false;
            unquiet();
            result.success(null);
          } else {
            result.notImplemented();
          }
        });
    return channel;
  }
}
