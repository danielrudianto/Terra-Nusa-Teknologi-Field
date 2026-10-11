package id.co.alphakonstruksi.terrabot_field

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Battery saving and auto-start, for `lib/core/device/device_power.dart`.
 *
 * Xiaomi, Oppo, Vivo and friends stop apps that are not on screen. On those
 * phones the casting reminders (20 minutes, paused pour) and the automatic
 * send in the background never run unless the user lets the app be. Android
 * has no single setting for it, so this opens the right screen per brand and
 * reports whether battery optimisation is still on.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "terrabot/device_power").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(
                    mapOf(
                        "manufacturer" to Build.MANUFACTURER.lowercase(),
                        "ignoringBatteryOptimizations" to ignoringBatteryOptimizations(),
                    ),
                )
                "openAppSettings" -> result.success(openAppSettings())
                "openAutostart" -> result.success(openAutostart())
                else -> result.notImplemented()
            }
        }
    }

    private fun ignoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /** App info page: "Baterai" → "Tanpa batasan" lives here on most phones. */
    private fun openAppSettings(): Boolean = tryStart(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
    )

    /** The brand's own auto-start list; false when this phone has none we know. */
    private fun openAutostart(): Boolean {
        val candidates = listOf(
            // Xiaomi / Redmi / POCO (MIUI, HyperOS)
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            // Oppo / Realme / OnePlus (ColorOS)
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oplus.safecenter" to "com.oplus.safecenter.permission.startup.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            // Vivo / iQOO
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            // Huawei / Honor
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            "com.hihonor.systemmanager" to "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            // Samsung: battery page (no auto-start list; "Aplikasi tidur" is there)
            "com.samsung.android.lool" to "com.samsung.android.sm.ui.battery.BatteryActivity",
        )
        for ((pkg, cls) in candidates) {
            if (tryStart(Intent().setComponent(ComponentName(pkg, cls)))) return true
        }
        return false
    }

    private fun tryStart(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        false
    }
}
