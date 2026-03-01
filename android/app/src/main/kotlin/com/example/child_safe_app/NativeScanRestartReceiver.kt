package com.example.child_safe_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class NativeScanRestartReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "NativeScanRestartReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != NativeScanService.ACTION_RESTART) {
            return
        }

        try {
            val serviceIntent = Intent(context, NativeScanService::class.java).apply {
                action = NativeScanService.ACTION_RESTART
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            Log.w(TAG, "NativeScanService restart requested by receiver")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restart NativeScanService: ${e.message}", e)
        }
    }
}
