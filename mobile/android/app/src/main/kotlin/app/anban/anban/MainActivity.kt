package app.anban.anban

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.os.PowerManager
import android.app.ActivityManager
import android.content.Intent
import android.net.Uri
import android.provider.Settings

class MainActivity : FlutterActivity() {
    private var reminderChannel: MethodChannel? = null
    private var reminderLinkPending = false

    private fun isReminderLink(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_VIEW && intent.data?.scheme == "anban" && intent.data?.host == "reminders"

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (isReminderLink(intent)) {
            reminderLinkPending = true
            reminderChannel?.invokeMethod("reminderLink", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        reminderLinkPending = reminderLinkPending || isReminderLink(intent)
        reminderChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.anban.anban/reminders")
        reminderChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeReminderLink" -> {
                        result.success(reminderLinkPending)
                        reminderLinkPending = false
                    }
                    "getBackgroundStatus" -> {
                        val power = getSystemService(POWER_SERVICE) as PowerManager
                        val activity = getSystemService(ACTIVITY_SERVICE) as ActivityManager
                        result.success(mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "androidVersion" to Build.VERSION.RELEASE,
                            "ignoringBatteryOptimizations" to power.isIgnoringBatteryOptimizations(packageName),
                            "powerSaveMode" to power.isPowerSaveMode,
                            "backgroundRestricted" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && activity.isBackgroundRestricted)
                        ))
                    }
                    "openBatterySettings", "openAppSettings" -> {
                        val details = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        try {
                            val intent = if (call.method == "openBatterySettings") {
                                val power = getSystemService(POWER_SERVICE) as PowerManager
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !power.isIgnoringBatteryOptimizations(packageName)) {
                                    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
                                } else {
                                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                }
                            } else details
                            startActivity(intent)
                            result.success(null)
                        } catch (_: Exception) {
                            try {
                                startActivity(details)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("settings_unavailable", "无法打开系统设置", e.message)
                            }
                        }
                    }
                    "startKeepAlive" -> {
                        val text = call.argument<String>("text")
                        KeepAliveService.start(this, text)
                        result.success(true)
                    }
                    "stopKeepAlive" -> {
                        KeepAliveService.stop(this)
                        result.success(true)
                    }
                    "isKeepAliveRunning" -> {
                        result.success(KeepAliveService.isRunning)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.anban.anban/version")
            .setMethodCallHandler { call, result ->
                if (call.method != "getVersion") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                @Suppress("DEPRECATION")
                val info = packageManager.getPackageInfo(packageName, 0)
                @Suppress("DEPRECATION")
                val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    info.longVersionCode
                } else {
                    info.versionCode.toLong()
                }
                result.success(mapOf("versionCode" to code, "versionName" to info.versionName))
            }
    }
}
