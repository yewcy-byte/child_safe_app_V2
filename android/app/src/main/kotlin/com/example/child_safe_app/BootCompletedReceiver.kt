package com.example.child_safe_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootCompletedReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootCompletedReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val receivedAction = intent?.action ?: return
        if (receivedAction != Intent.ACTION_BOOT_COMPLETED &&
            receivedAction != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            receivedAction != Intent.ACTION_MY_PACKAGE_REPLACED &&
            receivedAction != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        Log.d(TAG, "Received $receivedAction, restoring background protection services")

        try {
            val nativeScanIntent = Intent(context, NativeScanService::class.java).apply {
                this.action = NativeScanService.ACTION_RESTART
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(nativeScanIntent)
            } else {
                context.startService(nativeScanIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start NativeScanService on boot: ${e.message}", e)
        }

        NativeScanWatchdogReceiver.schedule(context, 60_000L)

        try {
            val mediaProjectionIntent = Intent(context, MediaProjectionService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(mediaProjectionIntent)
            } else {
                context.startService(mediaProjectionIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start MediaProjectionService on boot: ${e.message}", e)
        }
    }
}
