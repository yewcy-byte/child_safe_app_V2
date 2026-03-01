package com.example.child_safe_app

import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import java.util.concurrent.TimeUnit
import android.os.Handler
import android.os.Looper
import java.util.Calendar
import java.text.SimpleDateFormat

/**
 * Service that tracks screen time and app usage using system UsageStatsManager
 */
class UsageTrackingService : Service() {

    companion object {
        private const val TAG = "UsageTrackingService"
        private const val SYNC_INTERVAL_MS = 15 * 60 * 1000L
        private const val SCREEN_TIME_PREFS = "screen_time_prefs"
        private const val LAST_SYNC_KEY = "last_sync_time"
        
        fun startService(context: Context) {
            val intent = Intent(context, UsageTrackingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, UsageTrackingService::class.java)
            context.stopService(intent)
        }
    }

    private lateinit var usageStatsManager: UsageStatsManager
    private val handler = Handler(Looper.getMainLooper())
    private val syncRunnable = Runnable { syncData() }
    private val dayFormat = SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "UsageTrackingService created")
        
        usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        scheduleSync()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "UsageTrackingService started")
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notification = createNotification()
            startForeground(2, notification)
        }
        
        Log.d(TAG, "Collecting initial data...")
        syncData()
        
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "UsageTrackingService destroyed")
        handler.removeCallbacks(syncRunnable)
    }

    private fun scheduleSync() {
        handler.removeCallbacks(syncRunnable)
        handler.postDelayed(syncRunnable, SYNC_INTERVAL_MS)
        Log.d(TAG, "Next sync scheduled in ${SYNC_INTERVAL_MS/60000} minutes")
    }

    private fun syncData() {
        Log.d(TAG, "Starting data sync...")
        
        collectUsageStats()
        
        val prefs = getSharedPreferences(SCREEN_TIME_PREFS, Context.MODE_PRIVATE)
        prefs.edit().putLong(LAST_SYNC_KEY, System.currentTimeMillis()).apply()
        
        scheduleSync()
    }

    private fun collectUsageStats() {
        val endTime = System.currentTimeMillis()
        val startTime = endTime - TimeUnit.DAYS.toMillis(7)
        
        Log.d(TAG, "Querying usage stats from $startTime to $endTime")
        
        // Check permission
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        } else {
            appOps.checkOpNoThrow(
                android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        }
        
        Log.d(TAG, "Usage stats permission mode: $mode")
        
        try {
            Log.d(TAG, "Rebuilding usage data via UsageEvents sessions")
            
            // Calculate screen time per day and store (all 7 days via exact day windows)
            calculateScreenTimePerDay()
            
            // Process app usage (today only)
            processTodayAppUsage(endTime)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error: ${e.message}", e)
        }
    }

    private fun calculateScreenTimePerDay() {
        val prefs = getSharedPreferences(SCREEN_TIME_PREFS, Context.MODE_PRIVATE)
        val editor = prefs.edit()

        val now = System.currentTimeMillis()
        val calendar = Calendar.getInstance()
        val dailyTotals = mutableMapOf<String, Long>()

        // Compute each day's total from an exact day window.
        // This avoids mis-assigning records based on UsageStats timestamps.
        for (i in 6 downTo 0) {
            val dayStartCal = calendar.clone() as Calendar
            dayStartCal.add(Calendar.DAY_OF_MONTH, -i)
            dayStartCal.set(Calendar.HOUR_OF_DAY, 0)
            dayStartCal.set(Calendar.MINUTE, 0)
            dayStartCal.set(Calendar.SECOND, 0)
            dayStartCal.set(Calendar.MILLISECOND, 0)

            val dayEndCal = dayStartCal.clone() as Calendar
            dayEndCal.add(Calendar.DAY_OF_MONTH, 1)

            val dayStartMs = dayStartCal.timeInMillis
            val dayEndMs = minOf(dayEndCal.timeInMillis, now)
            val dayKey = dayFormat.format(dayStartCal.time)

            val rawTotalMs = queryForegroundMsForRange(dayStartMs, dayEndMs)
            val maxPossibleMs = (dayEndMs - dayStartMs).coerceAtLeast(0L)
            val boundedTotalMs = rawTotalMs.coerceIn(0L, maxPossibleMs)
            dailyTotals[dayKey] = boundedTotalMs
        }

        // Store each day's screen time
        var totalWeekMs: Long = 0
        for ((dayKey, ms) in dailyTotals) {
            editor.putLong(dayKey, ms)
            totalWeekMs += ms
            Log.d(TAG, "Day $dayKey: ${ms / 60000} min")
        }
        
        editor.apply()
        Log.d(TAG, "Total week: ${totalWeekMs / 60000} min")
    }

    private fun queryForegroundMsForRange(startMs: Long, endMs: Long): Long {
        if (endMs <= startMs) {
            return 0L
        }

        val usageByPackage = collectUsageByPackageFromEvents(startMs, endMs)
        return usageByPackage.values.sumOf { it.totalMs }
    }

    private fun processTodayAppUsage(endTime: Long) {
        val todayStart = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        val weekStart = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_MONTH, -6)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        val usageStats = collectUsageByPackageFromEvents(todayStart, endTime)
        val weeklyUsageStats = collectUsageByPackageFromEvents(weekStart, endTime)

        val appUsageMap = mutableMapOf<String, AppUsageInfo>()
        
        for ((packageName, stats) in usageStats) {
            val totalTime = stats.totalMs
            if (totalTime > 0) {
                val weekTotalTime = weeklyUsageStats[packageName]?.totalMs
                    ?.coerceAtLeast(totalTime) ?: totalTime
                val info = appUsageMap.getOrPut(packageName) {
                    AppUsageInfo(packageName)
                }
                info.totalTime = totalTime
                info.weekTotalTime = weekTotalTime
                info.lastUsed = maxOf(info.lastUsed, stats.lastUsedMs)
            }
        }
        
        val sortedApps = appUsageMap.values.sortedByDescending { it.totalTime }
        Log.d(TAG, "Apps today: ${sortedApps.size}")
        
        storeAppUsageData(sortedApps)
    }

    private fun storeAppUsageData(apps: List<AppUsageInfo>) {
        val prefs = getSharedPreferences(SCREEN_TIME_PREFS, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        val today = getDateKey(Calendar.getInstance())
        
        val topApps = apps.take(20)
        val appsString = topApps.joinToString(";") { 
            "${it.packageName},${it.totalTime},${it.lastUsed},${it.weekTotalTime}" 
        }
        
        editor.putString("${today}_apps", appsString)
        editor.apply()
        
        Log.d(TAG, "Stored ${topApps.size} apps")
    }

    private fun shouldExcludeFromScreenTime(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) {
            return true
        }

        val lower = packageName.lowercase()
        return lower == "com.android.systemui" ||
            lower.startsWith("com.android.launcher") ||
            lower.contains("inputmethod") ||
            lower.contains("keyboard") ||
            lower.contains("permissioncontroller")
    }

    private fun collectUsageByPackageFromEvents(
        startMs: Long,
        endMs: Long,
    ): Map<String, UsageWindowStats> {
        if (endMs <= startMs) {
            return emptyMap()
        }

        val events = usageStatsManager.queryEvents(startMs, endMs)
        val event = UsageEvents.Event()
        val activeSessions = mutableMapOf<String, Long>()
        val totals = mutableMapOf<String, Long>()
        val lastUsed = mutableMapOf<String, Long>()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val packageName = event.packageName ?: continue
            if (shouldExcludeFromScreenTime(packageName)) {
                continue
            }

            val timestamp = event.timeStamp.coerceIn(startMs, endMs)
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND,
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    val iterator = activeSessions.entries.iterator()
                    while (iterator.hasNext()) {
                        val activeEntry = iterator.next()
                        if (activeEntry.key == packageName) {
                            continue
                        }
                        val startedAt = activeEntry.value
                        if (timestamp > startedAt) {
                            totals[activeEntry.key] =
                                (totals[activeEntry.key] ?: 0L) + (timestamp - startedAt)
                        }
                        iterator.remove()
                    }

                    if (!activeSessions.containsKey(packageName)) {
                        activeSessions[packageName] = timestamp
                    }
                    val prevLastUsed = lastUsed[packageName] ?: 0L
                    if (timestamp > prevLastUsed) {
                        lastUsed[packageName] = timestamp
                    }
                }

                UsageEvents.Event.MOVE_TO_BACKGROUND,
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    val startedAt = activeSessions.remove(packageName) ?: continue
                    if (timestamp > startedAt) {
                        totals[packageName] = (totals[packageName] ?: 0L) + (timestamp - startedAt)
                    }
                }
            }
        }

        // Close open sessions at end boundary.
        for ((packageName, startedAt) in activeSessions) {
            if (endMs > startedAt) {
                totals[packageName] = (totals[packageName] ?: 0L) + (endMs - startedAt)
            }
        }

        val result = mutableMapOf<String, UsageWindowStats>()
        for ((packageName, totalMs) in totals) {
            if (totalMs <= 0L) {
                continue
            }
            result[packageName] = UsageWindowStats(
                totalMs = totalMs,
                lastUsedMs = lastUsed[packageName] ?: 0L,
            )
        }
        return result
    }

    private fun getDateKey(calendar: Calendar): String {
        return String.format("%04d-%02d-%02d", 
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH) + 1,
            calendar.get(Calendar.DAY_OF_MONTH)
        )
    }

    private fun createNotification(): android.app.Notification {
        val channelId = "usage_tracking_channel"
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                channelId,
                "Usage Tracking",
                android.app.NotificationManager.IMPORTANCE_LOW
            )
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            nm.createNotificationChannel(channel)
        }
        
        return android.app.Notification.Builder(this, channelId)
            .setContentTitle("Child Safe")
            .setContentText("Monitoring screen time and app usage")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .build()
    }

    data class AppUsageInfo(
        val packageName: String,
        var totalTime: Long = 0,
        var lastUsed: Long = 0,
        var weekTotalTime: Long = 0,
    )

    data class UsageWindowStats(
        val totalMs: Long,
        val lastUsedMs: Long,
    )
}
