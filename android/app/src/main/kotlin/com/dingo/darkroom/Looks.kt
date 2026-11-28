package com.dingo.darkroom

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

// The app icon people can pick (Darkroom 98 > User Profile, or the welcome
// tour's "Want a different look?"; lib/core/brand/app_look.dart).
//
// Each icon is its own launcher entry: MainActivity (the original rabbit)
// and three subclasses declared in the manifest, disabled until picked,
// each with its own icon and its own launch theme (Android draws the splash
// from the entry that was tapped, before any of our code runs, so the
// splash follows the pick as well). Exactly one is enabled at a time.
//
// The pick lives in its own small preferences file, the only thing Android's
// backup keeps (res/xml/backup_rules.xml, data_extraction_rules.xml): after
// a reinstall it comes back with the backup, and the first launch puts the
// icon right again (ensure). Once someone leaves the original, nothing in
// the app or an update ever brings it back unless they pick it.

/// The rabbit with no face.
class LookEyeless : MainActivity()

/// A plain instant camera.
class LookInstant : MainActivity()

/// A lens, head-on.
class LookLens : MainActivity()

object Looks {
    private const val FILE = "darkroom_look"
    private const val KEY = "look"
    const val CLASSIC = "classic"

    /// Every look and its launcher entry.
    private val entries = linkedMapOf(
        CLASSIC to MainActivity::class.java,
        "eyeless" to LookEyeless::class.java,
        "instant" to LookInstant::class.java,
        "lens" to LookLens::class.java,
    )

    fun isLook(name: String?) = name != null && entries.containsKey(name)

    /// The saved pick (the original rabbit if none).
    fun current(context: Context): String {
        val v = context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getString(KEY, null)
        return if (isLook(v)) v!! else CLASSIC
    }

    /// Saves the pick. The launcher entries change separately (swap), once
    /// the app is out of sight: changing them in front closed the app on
    /// some phones.
    fun save(context: Context, look: String) {
        if (!isLook(look)) return
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putString(KEY, look).commit()
        // Ask Android to back it up soon (it decides when).
        try {
            android.app.backup.BackupManager(context).dataChanged()
        } catch (e: Exception) {
            // (no backup service: kept on the phone as usual)
        }
    }

    /// Whether the launcher already shows the saved pick.
    fun isShown(context: Context): Boolean {
        val want = current(context)
        return entries.all { (name, cls) -> enabled(context, cls) == (name == want) }
    }

    /// Makes the saved pick the one launcher entry. The new entry is
    /// switched on before the old one goes, so there is never none.
    fun swap(context: Context) {
        val want = current(context)
        val pm = context.packageManager
        val target = entries[want] ?: return
        try {
            if (!enabled(context, target)) set(pm, context, target, true)
            for ((name, cls) in entries) {
                if (name != want && enabled(context, cls)) set(pm, context, cls, false)
            }
        } catch (e: Exception) {
            // (left as it was; tried again next time)
        }
    }

    private fun set(pm: PackageManager, context: Context, cls: Class<*>, on: Boolean) {
        pm.setComponentEnabledSetting(
            ComponentName(context, cls),
            if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun enabled(context: Context, cls: Class<*>): Boolean {
        val component = ComponentName(context, cls)
        return when (context.packageManager.getComponentEnabledSetting(component)) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT ->
                // As the manifest has it: only MainActivity starts enabled.
                cls == MainActivity::class.java
            else -> false
        }
    }
}
