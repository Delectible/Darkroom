package com.dingo.darkroom

import android.database.ContentObserver
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Kept in the repo (flutter create only fills in a plain one) for its
// channels:
//  * darkroom/gestures: the camera screen asks Android to keep its back
//    gesture off the strip of edge where the other camera peeks in, so it
//    can be pulled in from the very edge.
//  * darkroom/volume: while the camera is on screen the volume buttons are
//    camera buttons (shutter / zoom); they're taken here, before Android
//    turns them into a volume change, and passed to Dart.
//  * darkroom/crash: Android's record of recent crashes / freezes.
//  * darkroom/battery: the phone's battery level.
//  * darkroom/rotation: whether the phone's auto-rotate is on (and when it
//    changes): the landscape screens only turn when it is.
class MainActivity : FlutterActivity() {
    private var volumeChannel: MethodChannel? = null
    private var captureVolume = false
    private var rotationChannel: MethodChannel? = null
    private var rotationObserver: ContentObserver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The app turns its own screens (they already look landscape when
        // Android rotates): cut straight to the new orientation instead of
        // Android's rotate animation.
        window.attributes = window.attributes.also {
            it.rotationAnimation = WindowManager.LayoutParams.ROTATION_ANIMATION_JUMPCUT
        }
    }

    override fun onDestroy() {
        rotationObserver?.let { contentResolver.unregisterContentObserver(it) }
        super.onDestroy()
    }

    private fun autoRotate(): Boolean =
        Settings.System.getInt(contentResolver, Settings.System.ACCELEROMETER_ROTATION, 0) == 1

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val code = event.keyCode
        if (captureVolume && (code == KeyEvent.KEYCODE_VOLUME_UP || code == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            val down = event.action == KeyEvent.ACTION_DOWN
            if (event.repeatCount == 0 && (down || event.action == KeyEvent.ACTION_UP)) {
                volumeChannel?.invokeMethod("key", mapOf("up" to (code == KeyEvent.KEYCODE_VOLUME_UP), "down" to down))
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        volumeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "darkroom/volume").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "capture" -> {
                        captureVolume = call.arguments == true
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        rotationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "darkroom/rotation").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "autoRotate" -> result.success(autoRotate())
                    else -> result.notImplemented()
                }
            }
        }
        rotationObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                rotationChannel?.invokeMethod("autoRotate", autoRotate())
            }
        }.also {
            contentResolver.registerContentObserver(
                Settings.System.getUriFor(Settings.System.ACCELEROMETER_ROTATION), false, it,
            )
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "darkroom/gestures")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Flat list of left, top, right, bottom in physical pixels;
                    // empty clears. Android 10+ only (older phones have no
                    // back gesture to fight with).
                    "exclude" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val v = (call.arguments as? List<*>)?.map { (it as Number).toInt() } ?: emptyList()
                            window.decorView.setSystemGestureExclusionRects(
                                v.chunked(4).filter { it.size == 4 }.map { Rect(it[0], it[1], it[2], it[3]) },
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // darkroom/battery: the phone's charge, for the digital bodies' battery
        // gauges (and the camcorder's burned-in OSD).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "darkroom/battery")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "level" -> {
                        val bm = getSystemService(BATTERY_SERVICE) as android.os.BatteryManager
                        result.success(bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY))
                    }
                    else -> result.notImplemented()
                }
            }
        // darkroom/crash: the crashes / freezes Android recorded for this app
        // (Android 11+), for Help > Crash Reports. Kept on the phone.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "darkroom/crash")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "exits" -> result.success(recentExits())
                    else -> result.notImplemented()
                }
            }
    }

    private fun recentExits(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
        return try {
            am.getHistoricalProcessExitReasons(packageName, 0, 10).mapNotNull { e ->
                val reason = when (e.reason) {
                    android.app.ApplicationExitInfo.REASON_CRASH -> "Crash"
                    android.app.ApplicationExitInfo.REASON_CRASH_NATIVE -> "Native crash"
                    android.app.ApplicationExitInfo.REASON_ANR -> "Not responding"
                    else -> null
                } ?: return@mapNotNull null
                // ANR traces are text; native ones are binary tombstones.
                val trace = if (e.reason == android.app.ApplicationExitInfo.REASON_ANR) {
                    try {
                        e.traceInputStream?.bufferedReader()?.use { it.readText().take(8000) }
                    } catch (_: Exception) {
                        null
                    }
                } else {
                    null
                }
                mapOf(
                    "reason" to reason,
                    "description" to e.description,
                    "time" to e.timestamp,
                    "pid" to e.pid,
                    "trace" to trace,
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
