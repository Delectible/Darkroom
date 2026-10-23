package com.dingo.darkroom

import android.database.ContentObserver
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Environment
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

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
//  * darkroom/gallery: the names of the files the app saved to a photo
//    album that are still there (deleted ones are offered again).
class MainActivity : FlutterActivity() {
    private var volumeChannel: MethodChannel? = null
    private var captureVolume = false
    private var rotationChannel: MethodChannel? = null
    private var rotationObserver: ContentObserver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The app turns its own screens (they already look landscape when
        // Android rotates), so no rotate animation. Seamless, not jump-cut:
        // a jump cut shows the last portrait frame turned for a frame (the
        // page flickered upright as it landed); seamless keeps showing it
        // as it was until the first landscape frame (full screen windows;
        // else Android cross-fades).
        window.attributes = window.attributes.also {
            it.rotationAnimation = WindowManager.LayoutParams.ROTATION_ANIMATION_SEAMLESS
        }
        refreshRate(fast = true)
    }

    /// Fast: the screen's fastest refresh rate (90/120 Hz; left alone,
    /// Android often keeps an app at 60). Else 60 Hz (performance mode).
    private fun refreshRate(fast: Boolean) {
        @Suppress("DEPRECATION")
        val screen = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay)
            ?: return
        val now = screen.mode
        val modes = screen.supportedModes.filter { m ->
            m.physicalWidth == now.physicalWidth && m.physicalHeight == now.physicalHeight
        }
        val pick = if (fast) modes.maxByOrNull { it.refreshRate } else modes.minByOrNull { abs(it.refreshRate - 60f) }
        pick?.let { m -> window.attributes = window.attributes.also { it.preferredDisplayModeId = m.modeId } }
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
        // darkroom/display: "fast" (bool): full refresh rate, or 60 Hz in
        // performance mode.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "darkroom/display")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "fast" -> {
                        refreshRate(call.arguments == true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
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
        // darkroom/gallery: what's still in one of our albums. Android lists the
        // app's own entries without any permission (deleted or binned ones
        // drop out).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "darkroom/gallery")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "names" -> {
                        val album = call.argument<String>("album") ?: ""
                        Thread {
                            val names = try {
                                albumNames(album)
                            } catch (e: Exception) {
                                null
                            }
                            Handler(Looper.getMainLooper()).post { result.success(names) }
                        }.start()
                    }
                    "access" -> result.success("full")
                    "request" -> result.success(true)
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

    /// File names in Pictures/<album> (where the gallery plugin saves images,
    /// and videos too when given an album), photos and videos; null if
    /// Android won't say.
    private fun albumNames(album: String): List<String>? {
        val dir = Environment.DIRECTORY_PICTURES + "/" + album
        val names = mutableListOf<String>()
        for (uri in listOf(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, MediaStore.Video.Media.EXTERNAL_CONTENT_URI)) {
            val (sel, args) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?" to arrayOf("$dir%")
            } else {
                // (Android 9 and older: by path)
                "${MediaStore.MediaColumns.DATA} LIKE ?" to arrayOf("%/$dir/%")
            }
            val c = contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), sel, args, null)
                ?: return null
            c.use { while (it.moveToNext()) it.getString(0)?.let(names::add) }
        }
        return names
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
