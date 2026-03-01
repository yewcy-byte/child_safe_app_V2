package com.example.child_safe_app

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log

class NativeScanWatchdogReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "NativeScanWatchdog"
        private const val PREFS = "childsafe_blocking"
        private const val KEY_NATIVE_SCAN_ENABLED = "native_scan_enabled"
        private const val REQUEST_CODE_WATCHDOG = 32026
        private const val ACTION_WATCHDOG_TICK = "com.childsafe.app.ACTION_NATIVE_SCAN_WATCHDOG"

        fun schedule(context: Context, intervalMs: Long) {
            try {
                val intent = Intent(context, NativeScanWatchdogReceiver::class.java).apply {
                    action = ACTION_WATCHDOG_TICK
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    REQUEST_CODE_WATCHDOG,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )

                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val triggerAt = SystemClock.elapsedRealtime() + intervalMs
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pendingIntent,
                    )
                } else {
                    alarmManager.set(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pendingIntent,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to schedule watchdog: ${e.message}", e)
            }
        }

        fun cancel(context: Context) {
            try {
                val intent = Intent(context, NativeScanWatchdogReceiver::class.java).apply {
                    action = ACTION_WATCHDOG_TICK
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    REQUEST_CODE_WATCHDOG,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to cancel watchdog: ${e.message}", e)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_WATCHDOG_TICK) {
            return
        }

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val shouldRun = prefs.getBoolean(KEY_NATIVE_SCAN_ENABLED, true)

        if (shouldRun && !isNativeScanServiceRunning(context)) {
            try {
                val serviceIntent = Intent(context, NativeScanService::class.java).apply {
                    action = NativeScanService.ACTION_RESTART
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
                Log.w(TAG, "Watchdog restarted NativeScanService")
            } catch (e: Exception) {
                Log.e(TAG, "Watchdog failed to restart NativeScanService: ${e.message}", e)
            }
        }

        schedule(context, 60_000L)
    }

    @Suppress("DEPRECATION")
    private fun isNativeScanServiceRunning(context: Context): Boolean {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            activityManager.getRunningServices(Int.MAX_VALUE).any {
                it.service.className == NativeScanService::class.java.name
            }
        } catch (_: Exception) {
            false
        }
    }
}
