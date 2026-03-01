package com.example.child_safe_app

import android.app.*
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class MediaProjectionService : Service() {
    private val TAG = "MediaProjectionService"
    private val CHANNEL_ID = "ScreenCaptureServiceChannel"

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "MediaProjectionService onCreate()")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "MediaProjectionService onStartCommand()")
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Child Safe Protection")
            .setContentText("Screen protection is active")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .build()

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            Log.d(TAG, "Starting foreground with MEDIA_PROJECTION type")
            startForeground(1, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            Log.d(TAG, "Starting foreground (legacy)")
            startForeground(1, notification)
        }
        
        Log.d(TAG, "MediaProjectionService is now in foreground")
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "MediaProjectionService destroyed")
    }

    private fun createNotificationChannel() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Screen Capture Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps screen protection running"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }
}
