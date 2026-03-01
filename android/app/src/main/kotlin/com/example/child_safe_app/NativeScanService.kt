package com.example.child_safe_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.ActivityManager
import android.app.AlarmManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.core.app.NotificationCompat
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import io.github.devzwy.nsfw.NSFWHelper
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class NativeScanService : Service() {
    private enum class UnsafeType {
        NSFW,
        GORE,
        WEAPON,
        APP_BLOCK,
        APP_TIME_LIMIT,
        SCREEN_TIME,
        GENERIC,
    }

    private data class WeaponScanResult(
        val isUnsafe: Boolean,
        val unsafeScore: Float,
        val label: String,
    )

    companion object {
        private const val TAG = "NativeScanService"
        private const val CHANNEL_ID = "native_scan_channel"
        private const val NOTIFICATION_ID = 2026
        @Volatile
        private var serviceRunning: Boolean = false

        fun isScannerRuntimeRunning(): Boolean = serviceRunning

        const val ACTION_SCAN = "com.childsafe.app.ACTION_SCAN"
        const val ACTION_STOP = "com.childsafe.app.ACTION_STOP_NATIVE_SCAN"
        const val ACTION_RESTART = "com.childsafe.app.ACTION_RESTART_NATIVE_SCAN"
        const val ACTION_HIDE_SHIELD = "com.childsafe.app.ACTION_HIDE_NATIVE_SHIELD"
        const val EXTRA_PACKAGE = "packageName"

        private const val PREFS = "childsafe_blocking"
        private const val KEY_SCAN_PORN = "scan_porn_enabled"
        private const val KEY_SCAN_VIOLENCE = "scan_violence_enabled"
        private const val KEY_SCAN_EXCLUDED = "scan_excluded_apps"
        private const val KEY_SCAN_CHILD_ID = "scan_child_id"
        private const val KEY_SCAN_PARENT_ID = "scan_parent_id"
        private const val KEY_SCAN_INTERVAL_SECONDS = "scan_interval_seconds"
        private const val KEY_BLOCKED_APPS = "blocked_packages"
        private const val KEY_NATIVE_SCAN_ENABLED = "native_scan_enabled"
        private const val KEY_DAILY_ALLOWANCE_MINUTES = "daily_screen_time_allowance_minutes"
        private const val KEY_DAILY_BONUS_MINUTES = "daily_screen_time_bonus_minutes"
        private const val KEY_DAILY_DAY_START_MS = "daily_screen_time_day_start_ms"
        private const val KEY_APP_TIME_LIMITS = "app_time_limits_entries"

        private const val NSFW_THRESHOLD = 0.70f
        private const val VIOLENCE_THRESHOLD = 0.995f
        private const val DEFAULT_PERIODIC_SCAN_INTERVAL_MS = 3000L
        private const val MIN_PERIODIC_SCAN_INTERVAL_MS = 1000L
        private const val MAX_PERIODIC_SCAN_INTERVAL_MS = 30000L
        private const val POST_BLOCK_SCAN_COOLDOWN_MS = 3500L
        private const val WATCHDOG_INTERVAL_MS = 60_000L
        private const val BLOCKED_APP_REOPEN_AWAY_MS = 300L
        private const val GENERAL_UNSAFE_COOLDOWN_MS = 4000L
        private const val USAGE_FIRESTORE_SYNC_INTERVAL_MS = 60 * 1000L
        private const val LIMIT_ENFORCER_INTERVAL_MS = 1000L
    }

    private var nsfwInterpreter: Interpreter? = null
    private var weaponInterpreter: Interpreter? = null
    private var nsfwInputSize = 224
    private var weaponInputSize = 320

    private var lastScanAtMillis: Long = 0L
    private var lastUnsafeAtMillis: Long = 0L
    private var lastNotifiedCaptureReady: Boolean? = null
    private var lastRecoveryFlagState: Boolean? = null
    @Volatile
    private var activePackageName: String? = null
    @Volatile
    private var lastWindowPackageName: String? = null
    @Volatile
    private var blockedAppShieldLatchedPackage: String? = null
    @Volatile
    private var blockedAppLastAwayAtMillis: Long = 0L
    @Volatile
    private var appTimeLimitLatchedPackage: String? = null
    @Volatile
    private var appTimeLimitLastAwayAtMillis: Long = 0L
    @Volatile
    private var dailyScreenTimeLatchedPackage: String? = null
    @Volatile
    private var dailyScreenTimeLastAwayAtMillis: Long = 0L
    private var periodicScanner: ScheduledExecutorService? = null
    private var scanWorker: ExecutorService? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var stopRequestedByUser: Boolean = false
    private var shieldView: View? = null
    private var shieldWindowManager: WindowManager? = null
    private var shieldUnsafeType: UnsafeType? = null
    private var lastNativeShieldAtMillis: Long = 0L
    private var cooldownPackageName: String? = null
    private var cooldownUntilMillis: Long = 0L
    private var nsfwHelperInitialized: Boolean = false
    private var lastUsageFirestoreSyncAtMs: Long = 0L
    private var usageSyncInFlight: Boolean = false
    private var exclusionsListener: ListenerRegistration? = null
    private var exclusionsChildId: String? = null
    @Volatile
    private var firestoreExcludedPackages: Set<String> = emptySet()
    private var filterSettingsListener: ListenerRegistration? = null
    private var filterSettingsParentId: String? = null
    private var filterSettingsChildId: String? = null
    private var blockedAppsListener: ListenerRegistration? = null
    private var blockedAppsParentId: String? = null
    private var blockedAppsChildId: String? = null
    private var screenTimeSettingsListener: ListenerRegistration? = null
    private var screenTimeSettingsChildId: String? = null
    private var appTimeLimitsListener: ListenerRegistration? = null
    private var appTimeLimitsParentId: String? = null
    private var appTimeLimitsChildId: String? = null
    private var screenStateReceiver: BroadcastReceiver? = null
    @Volatile
    private var isDeviceInteractive: Boolean = true
    @Volatile
    private var periodicIntervalMs: Long = DEFAULT_PERIODIC_SCAN_INTERVAL_MS
    private var limitEnforcer: ScheduledExecutorService? = null
    private lateinit var usageStatsManager: UsageStatsManager

    override fun onCreate() {
        super.onCreate()
        serviceRunning = true
        Log.w(TAG, "NativeScanService onCreate() called")
        try {
            stopRequestedByUser = false
            createNotificationChannel()
            startForeground(NOTIFICATION_ID, buildNotification(currentScannerStatusText()))
            Log.d(TAG, "NativeScanService started in foreground")
            scanWorker = Executors.newSingleThreadExecutor()
            usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            acquireWakeLock()
            initModels()
            initializeInteractiveState()
            registerScreenStateReceiver()
            refreshPeriodicIntervalFromPrefs()
            ensureExclusionsListener()
            ensureFilterSettingsListener()
            ensureBlockedAppsListener()
            ensureScreenTimeSettingsListener()
            ensureAppTimeLimitsListener()
            startPeriodicScanner()
            startLimitEnforcer()
            scheduleWatchdog()
            Log.w(TAG, "NativeScanService onCreate() completed successfully")
        } catch (e: Exception) {
            Log.e(TAG, "NativeScanService onCreate() failed: ${e.message}", e)
            throw e
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        val packageName = intent?.getStringExtra(EXTRA_PACKAGE)
        Log.w(TAG, "onStartCommand action=$action package=$packageName flags=$flags startId=$startId")
        
        if (action == ACTION_STOP) {
            Log.w(TAG, "ACTION_STOP received - stopping service")
            stopRequestedByUser = true
            serviceRunning = false
            setServiceEnabled(false)
            cancelWatchdog()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        if (action == ACTION_RESTART) {
            Log.w(TAG, "ACTION_RESTART received - clearing stop flag")
            stopRequestedByUser = false
        }

        if (action == ACTION_HIDE_SHIELD) {
            Log.w(TAG, "ACTION_HIDE_SHIELD received - hiding native shield")
            hideNativeShield()
            blockedAppShieldLatchedPackage = null
            blockedAppLastAwayAtMillis = 0L
            return START_STICKY
        }

        setServiceEnabled(true)
        scheduleWatchdog()

        if (action == ACTION_SCAN) {
            val pkg = intent?.getStringExtra(EXTRA_PACKAGE)
            if (!pkg.isNullOrBlank()) {
                Log.d(TAG, "ACTION_SCAN for package: $pkg")

                if (pkg != lastWindowPackageName) {
                    lastWindowPackageName = pkg
                    val latched = blockedAppShieldLatchedPackage
                    if (latched != null) {
                        if (pkg == latched) {
                            blockedAppLastAwayAtMillis = 0L
                        } else if (shouldSkipPackageForLimitEnforcement(pkg)) {
                            if (blockedAppLastAwayAtMillis == 0L) {
                                blockedAppLastAwayAtMillis = System.currentTimeMillis()
                                Log.d(TAG, "Foreground moved to noise package $pkg; preserving latch for $latched")
                            }
                        } else {
                            Log.d(TAG, "Foreground package changed to $pkg; resetting block latch for $latched")
                            blockedAppShieldLatchedPackage = null
                            blockedAppLastAwayAtMillis = 0L
                        }
                    }

                    val appTimeLatched = appTimeLimitLatchedPackage
                    if (appTimeLatched != null) {
                        if (pkg == appTimeLatched) {
                            if (appTimeLimitLastAwayAtMillis > 0L) {
                                Log.d(TAG, "Foreground returned to app-time limited package $pkg; clearing latch to re-enforce")
                                appTimeLimitLatchedPackage = null
                                appTimeLimitLastAwayAtMillis = 0L
                            } else {
                                appTimeLimitLastAwayAtMillis = 0L
                            }
                        } else if (shouldSkipPackageForLimitEnforcement(pkg)) {
                            if (appTimeLimitLastAwayAtMillis == 0L) {
                                appTimeLimitLastAwayAtMillis = System.currentTimeMillis()
                                Log.d(TAG, "Foreground moved to noise package $pkg; preserving app-time latch for $appTimeLatched")
                            }
                        } else {
                            Log.d(TAG, "Foreground package changed to $pkg; resetting app-time latch for $appTimeLatched")
                            appTimeLimitLatchedPackage = null
                            appTimeLimitLastAwayAtMillis = 0L
                        }
                    }

                    val dailyLatched = dailyScreenTimeLatchedPackage
                    if (dailyLatched != null) {
                        if (pkg == dailyLatched) {
                            dailyScreenTimeLastAwayAtMillis = 0L
                        } else if (shouldSkipPackageForLimitEnforcement(pkg)) {
                            if (dailyScreenTimeLastAwayAtMillis == 0L) {
                                dailyScreenTimeLastAwayAtMillis = System.currentTimeMillis()
                                Log.d(TAG, "Foreground moved to noise package $pkg; preserving daily-time latch for $dailyLatched")
                            }
                        } else {
                            Log.d(TAG, "Foreground package changed to $pkg; resetting daily-time latch for $dailyLatched")
                            dailyScreenTimeLatchedPackage = null
                            dailyScreenTimeLastAwayAtMillis = 0L
                        }
                    }
                }

                if (!shouldSkipPackageForLimitEnforcement(pkg)) {
                    activePackageName = pkg
                } else {
                    if (shouldPreserveActivePackageOnSkip(pkg)) {
                        Log.d(TAG, "ACTION_SCAN on noise package; keeping active package=$activePackageName")
                    } else {
                        activePackageName = null
                        Log.d(TAG, "ACTION_SCAN on gaming/excluded package; pausing background scan for pkg=$pkg")
                    }
                }
                refreshPeriodicIntervalFromPrefs()
                ensureExclusionsListener()
                ensureFilterSettingsListener()
                ensureBlockedAppsListener()
                ensureScreenTimeSettingsListener()
                ensureAppTimeLimitsListener()
                dispatchMaybeScan(pkg)
            } else {
                Log.d(TAG, "ACTION_SCAN with null/blank package - using last active")
                val activePkg = activePackageName
                if (activePkg != null) {
                    refreshPeriodicIntervalFromPrefs()
                    ensureExclusionsListener()
                    ensureFilterSettingsListener()
                    ensureBlockedAppsListener()
                    ensureScreenTimeSettingsListener()
                    ensureAppTimeLimitsListener()
                    dispatchMaybeScan(activePkg)
                } else {
                    Log.w(TAG, "No active package name - skipping scan")
                }
            }
        } else if (action == null) {
            Log.w(TAG, "onStartCommand with null action - triggering scan anyway")
            val activePkg = activePackageName
            if (activePkg != null) {
                dispatchMaybeScan(activePkg)
            } else {
                Log.w(TAG, "No active package name - skipping scan")
            }
        }
        
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        serviceRunning = false
        Log.w(TAG, "NativeScanService onDestroy() called, stopRequestedByUser=$stopRequestedByUser")
        stopPeriodicScanner()
        stopLimitEnforcer()
        scanWorker?.shutdownNow()
        scanWorker = null
        exclusionsListener?.remove()
        exclusionsListener = null
        exclusionsChildId = null
        filterSettingsListener?.remove()
        filterSettingsListener = null
        filterSettingsParentId = null
        filterSettingsChildId = null
        blockedAppsListener?.remove()
        blockedAppsListener = null
        blockedAppsParentId = null
        blockedAppsChildId = null
        screenTimeSettingsListener?.remove()
        screenTimeSettingsListener = null
        screenTimeSettingsChildId = null
        appTimeLimitsListener?.remove()
        appTimeLimitsListener = null
        appTimeLimitsParentId = null
        appTimeLimitsChildId = null
        unregisterScreenStateReceiver()
        hideNativeShield()
        releaseWakeLock()
        nsfwInterpreter?.close()
        nsfwInterpreter = null
        weaponInterpreter?.close()
        weaponInterpreter = null

        if (!stopRequestedByUser) {
            Log.w(TAG, "Service destroyed without user request - scheduling restart")
            scheduleSelfRestart("destroy")
            scheduleWatchdog()
        } else {
            Log.w(TAG, "Service destroyed by user request - not restarting")
            cancelWatchdog()
        }

        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.w(TAG, "NativeScanService onTaskRemoved() called, stopRequestedByUser=$stopRequestedByUser")
        if (!stopRequestedByUser) {
            Log.w(TAG, "Task removed without user request - scheduling restart")
            scheduleSelfRestart("task_removed")
            scheduleWatchdog()
        } else {
            Log.w(TAG, "Task removed after user stop - not restarting")
            cancelWatchdog()
        }
        super.onTaskRemoved(rootIntent)
    }

    private fun setServiceEnabled(enabled: Boolean) {
        getPrefs().edit().putBoolean(KEY_NATIVE_SCAN_ENABLED, enabled).apply()
    }

    private fun scheduleWatchdog() {
        NativeScanWatchdogReceiver.schedule(this, WATCHDOG_INTERVAL_MS)
    }

    private fun cancelWatchdog() {
        NativeScanWatchdogReceiver.cancel(this)
    }

    private fun scheduleSelfRestart(reason: String) {
        try {
            val restartIntent = Intent(this, NativeScanRestartReceiver::class.java).apply {
                action = ACTION_RESTART
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                22026,
                restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val triggerAt = SystemClock.elapsedRealtime() + 1500L
            
            try {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAt,
                    pendingIntent,
                )
                Log.w(TAG, "Scheduled exact NativeScanService restart, reason=$reason")
            } catch (securityEx: SecurityException) {
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
                Log.w(TAG, "Scheduled inexact NativeScanService restart (no SCHEDULE_EXACT_ALARM), reason=$reason")
            }
        } catch (e: Exception) {
            Log.e(TAG, "scheduleSelfRestart failed: ${e.message}", e)
        }
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                return
            }
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "child_safe_app:NativeScanWakelock",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            Log.e(TAG, "acquireWakeLock failed: ${e.message}", e)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {
        } finally {
            wakeLock = null
        }
    }

    private fun startPeriodicScanner() {
        if (periodicScanner != null) {
            return
        }

        periodicScanner = Executors.newSingleThreadScheduledExecutor()
        periodicScanner?.scheduleWithFixedDelay(
            {
                reconcileRecoveryFlagWithCaptureState()
                maybeSyncUsageToFirestore()
                val packageName = activePackageName
                if (!packageName.isNullOrBlank() && canScanNow()) {
                    dispatchMaybeScan(packageName)
                }
            },
            periodicIntervalMs,
            periodicIntervalMs,
            TimeUnit.MILLISECONDS,
        )
        Log.d(TAG, "Periodic scanner started with interval=${periodicIntervalMs}ms")
    }

    private fun startLimitEnforcer() {
        if (limitEnforcer != null) {
            return
        }

        limitEnforcer = Executors.newSingleThreadScheduledExecutor()
        limitEnforcer?.scheduleWithFixedDelay(
            {
                if (!canScanNow()) {
                    return@scheduleWithFixedDelay
                }

                var packageName = activePackageName
                if (packageName.isNullOrBlank() || shouldSkipPackageForLimitEnforcement(packageName)) {
                    packageName = resolveForegroundPackageForLimitEnforcement()
                    if (!packageName.isNullOrBlank()) {
                        activePackageName = packageName
                    }
                }

                if (!packageName.isNullOrBlank()) {
                    maybeEnforceUsageLimits(packageName)
                }
            },
            LIMIT_ENFORCER_INTERVAL_MS,
            LIMIT_ENFORCER_INTERVAL_MS,
            TimeUnit.MILLISECONDS,
        )
        Log.d(TAG, "Limit enforcer started with interval=${LIMIT_ENFORCER_INTERVAL_MS}ms")
    }

    private fun resolveForegroundPackageForLimitEnforcement(): String? {
        return try {
            val endMs = System.currentTimeMillis()
            val startMs = endMs - 2 * 60_000L
            val events = usageStatsManager.queryEvents(startMs, endMs)
            val event = UsageEvents.Event()
            var latestPackage: String? = null
            var latestTimestamp = Long.MIN_VALUE

            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.eventType != UsageEvents.Event.MOVE_TO_FOREGROUND &&
                    event.eventType != UsageEvents.Event.ACTIVITY_RESUMED) {
                    continue
                }

                val packageName = event.packageName ?: continue
                if (shouldSkipPackageForLimitEnforcement(packageName)) {
                    continue
                }

                if (event.timeStamp >= latestTimestamp) {
                    latestTimestamp = event.timeStamp
                    latestPackage = packageName
                }
            }

            latestPackage
        } catch (e: Exception) {
            Log.d(TAG, "resolveForegroundPackageForLimitEnforcement failed: ${e.message}")
            null
        }
    }

    private fun dispatchMaybeScan(packageName: String) {
        if (!canScanNow()) {
            return
        }

        val worker = scanWorker
        if (worker == null || worker.isShutdown) {
            maybeScan(packageName)
            return
        }

        worker.execute {
            try {
                maybeScan(packageName)
            } catch (e: Exception) {
                Log.e(TAG, "dispatchMaybeScan failed for $packageName: ${e.message}", e)
            }
        }
    }

    private fun stopPeriodicScanner() {
        periodicScanner?.shutdownNow()
        periodicScanner = null
    }

    private fun stopLimitEnforcer() {
        limitEnforcer?.shutdownNow()
        limitEnforcer = null
    }

    private fun restartPeriodicScannerWithInterval(newIntervalMs: Long) {
        if (periodicIntervalMs == newIntervalMs && periodicScanner != null) {
            return
        }
        periodicIntervalMs = newIntervalMs
        stopPeriodicScanner()
        startPeriodicScanner()
    }

    private fun refreshPeriodicIntervalFromPrefs() {
        val intervalSeconds = getPrefs().getInt(KEY_SCAN_INTERVAL_SECONDS, 3)
        val intervalMs = (intervalSeconds.coerceIn(1, 30) * 1000L)
            .coerceIn(MIN_PERIODIC_SCAN_INTERVAL_MS, MAX_PERIODIC_SCAN_INTERVAL_MS)
        restartPeriodicScannerWithInterval(intervalMs)
    }

    private fun initModels() {
        try {
            val nsfwModel = loadModelFile("assets/nsfw.tflite")
            nsfwInterpreter = Interpreter(nsfwModel, Interpreter.Options().apply { setNumThreads(2) })
            val inputTensor = nsfwInterpreter?.getInputTensor(0)
            val outputTensor = nsfwInterpreter?.getOutputTensor(0)
            nsfwInputSize = inputTensor?.shape()?.getOrNull(1) ?: 224
            Log.w(TAG, "NSFW model: input=${inputTensor?.shape()?.contentToString()}, inputType=${inputTensor?.dataType()}, output=${outputTensor?.shape()?.contentToString()}, outputType=${outputTensor?.dataType()}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to init NSFW model: ${e.message}", e)
        }

        try {
            val weaponModel = loadModelFile("assets/weapon+gore_v2.tflite")
            weaponInterpreter = Interpreter(weaponModel, Interpreter.Options().apply { setNumThreads(2) })
            val inputTensor = weaponInterpreter?.getInputTensor(0)
            val outputTensor = weaponInterpreter?.getOutputTensor(0)
            weaponInputSize = inputTensor?.shape()?.getOrNull(1) ?: 320
            Log.w(TAG, "Weapon model: input=${inputTensor?.shape()?.contentToString()}, inputType=${inputTensor?.dataType()}, output=${outputTensor?.shape()?.contentToString()}, outputType=${outputTensor?.dataType()}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to init weapon model: ${e.message}", e)
        }
    }

    @Synchronized
    private fun maybeScan(packageName: String) {
        if (!canScanNow()) {
            emitScanResult(packageName, false, "DEVICE_IDLE", null, null, null, null)
            return
        }

        refreshNotificationIfNeeded()

        val now = System.currentTimeMillis()
        val blockedPackage = isBlockedPackage(packageName)
        if (!blockedPackage && blockedAppShieldLatchedPackage == packageName) {
            blockedAppShieldLatchedPackage = null
            blockedAppLastAwayAtMillis = 0L
        }

        if (blockedPackage) {
            emitScanResult(packageName, false, "BLOCKED_HANDLED_BY_ACCESSIBILITY", null, null, null, null)
            return
        }

        if (maybeEnforceUsageLimits(packageName)) {
            return
        }

        if (packageName == cooldownPackageName && now < cooldownUntilMillis) {
            emitScanResult(packageName, false, "COOLDOWN", null, null, null, null)
            return
        }

        if (shouldSkipPackage(packageName)) {
            emitScanResult(packageName, false, "SKIP", null, null, null, null)
            return
        }

        if ((now - lastScanAtMillis) < 900L) {
            return
        }
        lastScanAtMillis = now

        val scanPorn = getPrefs().getBoolean(KEY_SCAN_PORN, false)
        val scanViolence = getPrefs().getBoolean(KEY_SCAN_VIOLENCE, false)
        if (!scanPorn && !scanViolence) {
            emitScanResult(packageName, false, "FILTERS_DISABLED", null, null, scanPorn, scanViolence)
            return
        }

        val framePath = captureFreshFramePath() ?: run {
            Log.d(TAG, "No frame available for background scan")
            emitScanResult(packageName, false, "NO_CAPTURE", null, null, null, null)
            publishRecoveryFlag(true, "Capture session unavailable")
            return
        }

        Log.d(TAG, "Background scan frame captured: $framePath")

        publishRecoveryFlag(false, null)

        val frameFile = File(framePath)
        if (!frameFile.exists()) {
            return
        }

        var unsafe = false
        var reason = "SAFE"
        var unsafeType = UnsafeType.GENERIC
        var nsfwScoreForLog: Float? = null
        var violenceScoreForLog: Float? = null
        var violenceUnsafe = false
        var violenceUnsafeType = UnsafeType.GENERIC

        if (scanViolence) {
            val violenceResult = runWeaponScan(frameFile)
            violenceScoreForLog = violenceResult.unsafeScore
            if (violenceResult.isUnsafe && violenceResult.unsafeScore >= VIOLENCE_THRESHOLD) {
                violenceUnsafe = true
                violenceUnsafeType = if (violenceResult.label == "weapon") UnsafeType.WEAPON else UnsafeType.GORE
                Log.d(TAG, "Background violence unsafe score=${violenceResult.unsafeScore} label=${violenceResult.label} package=$packageName")
            } else if (violenceResult.isUnsafe) {
                Log.d(
                    TAG,
                    "Background violence candidate suppressed by threshold: score=${violenceResult.unsafeScore} label=${violenceResult.label} package=$packageName threshold=$VIOLENCE_THRESHOLD",
                )
            }
        }

        if (scanPorn) {
            val nsfwScore = runNsfwScan(frameFile)
            nsfwScoreForLog = nsfwScore
            if (nsfwScore >= NSFW_THRESHOLD) {
                unsafe = true
                reason = "NSFW"
                unsafeType = UnsafeType.NSFW
                Log.d(TAG, "Background nsfw unsafe score=$nsfwScore package=$packageName")
            }
        }

        if (!unsafe && violenceUnsafe) {
            unsafe = true
            reason = "VIOLENCE"
            unsafeType = violenceUnsafeType
        }

        if (!unsafe) {
            Log.d(TAG, "Background scan safe: $packageName")
        }

        emitScanResult(
            packageName = packageName,
            unsafe = unsafe,
            reason = reason,
            nsfwScore = nsfwScoreForLog,
            violenceScore = violenceScoreForLog,
            scanPorn = scanPorn,
            scanViolence = scanViolence,
        )

        frameFile.delete()

        if (unsafe) {
            if (
                unsafeType == UnsafeType.NSFW ||
                unsafeType == UnsafeType.WEAPON ||
                unsafeType == UnsafeType.GORE
            ) {
                logDetectionAndApplyPenalty(
                    packageName = packageName,
                    unsafeType = unsafeType,
                    reason = reason,
                    nsfwScore = nsfwScoreForLog,
                    violenceScore = violenceScoreForLog,
                )
            }
            enforceUnsafeContent(packageName, unsafeType)
        }
    }

    private fun captureFreshFramePath(): String? {
        val first = ProjectionSession.captureFrameToFile() ?: return null
        return try {
            Thread.sleep(180)
            ProjectionSession.captureFrameToFile() ?: first
        } catch (_: Exception) {
            first
        }
    }

    private fun runNsfwScan(file: File): Float {
        return try {
            val helperScore = runNsfwScanWithHelper(file)
            if (helperScore != null) {
                Log.w(TAG, "runNsfwScan: NSFWHelper score=$helperScore")
                return helperScore
            }

            // Lazy init if models not loaded
            if (nsfwInterpreter == null) {
                Log.w(TAG, "runNsfwScan: Interpreter null, initializing models")
                initModels()
            }
            val interpreter = nsfwInterpreter ?: return 0f
            val bitmap = BitmapFactory.decodeFile(file.absolutePath) ?: return 0f
            Log.w(TAG, "runNsfwScan: Original bitmap ${bitmap.width}x${bitmap.height}, config=${bitmap.config}")
            
            val resized = android.graphics.Bitmap.createScaledBitmap(bitmap, nsfwInputSize, nsfwInputSize, true)
            val inputTensor = interpreter.getInputTensor(0)
            val outputTensor = interpreter.getOutputTensor(0)
            val input = createInputBuffer(
                bitmap = resized,
                inputType = inputTensor.dataType(),
                normalize01ForFloat = true,
            )

            val outputShape = outputTensor.shape()
            val outputCols = outputShape.lastOrNull() ?: 2
            val output = createOutputBuffer(outputTensor.dataType(), outputCols)
            interpreter.run(input, output)
            val values = readOutputScores(output, outputTensor.dataType(), outputTensor)
            Log.w(TAG, "runNsfwScan: Output=${values.contentToString()}, dtype=${outputTensor.dataType()}")

            bitmap.recycle()
            resized.recycle()

            val unsafeScore = when {
                values.size >= 2 -> values[1]
                values.isNotEmpty() -> values[0]
                else -> 0f
            }
            if (unsafeScore.isFinite()) unsafeScore else 0f
        } catch (e: Exception) {
            Log.e(TAG, "runNsfwScan failed: ${e.message}", e)
            0f
        }
    }

    private fun runNsfwScanWithHelper(file: File): Float? {
        return try {
            ensureNsfwHelperInitialized()
            if (!nsfwHelperInitialized) {
                return null
            }

            val latch = CountDownLatch(1)
            val scoreRef = AtomicReference<Float?>(null)

            NSFWHelper.getNSFWScore(file) { result ->
                scoreRef.set(result.nsfwScore)
                latch.countDown()
            }

            val completed = latch.await(3000, TimeUnit.MILLISECONDS)
            if (!completed) {
                Log.w(TAG, "runNsfwScanWithHelper: timeout waiting for NSFWHelper")
                return null
            }

            val score = scoreRef.get()
            if (score != null && score.isFinite()) score else null
        } catch (e: Exception) {
            Log.w(TAG, "runNsfwScanWithHelper unavailable, falling back: ${e.message}")
            null
        }
    }

    private fun ensureNsfwHelperInitialized() {
        if (nsfwHelperInitialized) {
            return
        }

        try {
            val modelFile = File(filesDir, "nsfw_native_helper.tflite")
            if (!modelFile.exists() || modelFile.length() == 0L) {
                applicationContext.assets.open("flutter_assets/assets/nsfw.tflite").use { input ->
                    FileOutputStream(modelFile).use { output ->
                        input.copyTo(output)
                        output.flush()
                    }
                }
            }

            NSFWHelper.initHelper(
                context = applicationContext,
                isOpenGPU = false,
                modelPath = modelFile.absolutePath,
                numThreads = 4,
            )
            nsfwHelperInitialized = true
            Log.w(TAG, "NSFWHelper initialized for background scanning")
        } catch (e: Exception) {
            nsfwHelperInitialized = false
            Log.e(TAG, "ensureNsfwHelperInitialized failed: ${e.message}", e)
        }
    }

    private fun runWeaponScan(file: File): WeaponScanResult {
        return try {
            // Lazy init if models not loaded
            if (weaponInterpreter == null) {
                Log.w(TAG, "runWeaponScan: Interpreter null, initializing models")
                initModels()
            }
            val interpreter = weaponInterpreter ?: return WeaponScanResult(false, 0f, "safe")
            val bitmap = BitmapFactory.decodeFile(file.absolutePath) ?: return WeaponScanResult(false, 0f, "safe")
            Log.w(TAG, "runWeaponScan: Original bitmap ${bitmap.width}x${bitmap.height}, config=${bitmap.config}")

            val size = kotlin.math.min(bitmap.width, bitmap.height)
            val x = (bitmap.width - size) / 2
            val y = (bitmap.height - size) / 2
            val cropped = android.graphics.Bitmap.createBitmap(bitmap, x, y, size, size)
            val resized = android.graphics.Bitmap.createScaledBitmap(cropped, weaponInputSize, weaponInputSize, true)
            val inputTensor = interpreter.getInputTensor(0)
            val outputTensor = interpreter.getOutputTensor(0)
            val input = createInputBuffer(
                bitmap = resized,
                inputType = inputTensor.dataType(),
                normalize01ForFloat = false,
            )

            val outputCols = outputTensor.shape().lastOrNull() ?: 3
            val output = createOutputBuffer(outputTensor.dataType(), outputCols)
            interpreter.run(input, output)
            val scores = readOutputScores(output, outputTensor.dataType(), outputTensor)

            bitmap.recycle()
            cropped.recycle()
            resized.recycle()

            val blood = scores.getOrElse(0) { 0f }
            val weapon = scores.getOrElse(1) { 0f }
            val safe = scores.getOrElse(2) { 0f }

            val unsafeScore = kotlin.math.max(blood, weapon)
            val winner = when {
                blood >= weapon && blood >= safe -> 0
                weapon >= blood && weapon >= safe -> 1
                else -> 2
            }
            val isUnsafe = winner != 2
            val label = when (winner) {
                0 -> "gore"
                1 -> "weapon"
                else -> "safe"
            }

            Log.w(
                TAG,
                "runWeaponScan: blood=$blood weapon=$weapon safe=$safe => unsafe=$isUnsafe label=$label, dtype=${outputTensor.dataType()}",
            )

            WeaponScanResult(isUnsafe, unsafeScore, label)
        } catch (e: Exception) {
            Log.e(TAG, "runWeaponScan failed: ${e.message}", e)
            WeaponScanResult(false, 0f, "safe")
        }
    }

    private fun createInputBuffer(
        bitmap: android.graphics.Bitmap,
        inputType: DataType,
        normalize01ForFloat: Boolean,
    ): ByteBuffer {
        val width = bitmap.width
        val height = bitmap.height
        val pixelSize = if (inputType == DataType.UINT8) 1 else 4
        val buffer = ByteBuffer.allocateDirect(pixelSize * width * height * 3).order(ByteOrder.nativeOrder())

        var sampleR = 0
        var sampleG = 0
        var sampleB = 0
        
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = bitmap.getPixel(x, y)
                val r = (pixel shr 16 and 0xFF)
                val g = (pixel shr 8 and 0xFF)
                val b = (pixel and 0xFF)
                
                // Sample center pixel for debugging
                if (x == width / 2 && y == height / 2) {
                    sampleR = r
                    sampleG = g
                    sampleB = b
                }
                
                if (inputType == DataType.UINT8) {
                    buffer.put(r.toByte())
                    buffer.put(g.toByte())
                    buffer.put(b.toByte())
                } else {
                    if (normalize01ForFloat) {
                        buffer.putFloat(r / 255f)
                        buffer.putFloat(g / 255f)
                        buffer.putFloat(b / 255f)
                    } else {
                        buffer.putFloat(r.toFloat())
                        buffer.putFloat(g.toFloat())
                        buffer.putFloat(b.toFloat())
                    }
                }
            }
        }

        buffer.rewind()
        Log.d(TAG, "Created inputBuffer: size=${buffer.capacity()}, dtype=$inputType, normalize=$normalize01ForFloat, centerPixel=($sampleR,$sampleG,$sampleB)")
        return buffer
    }

    private fun createOutputBuffer(outputType: DataType, outputCols: Int): Any {
        val safeCols = if (outputCols < 1) 1 else outputCols
        return if (outputType == DataType.UINT8) {
            Array(1) { ByteArray(safeCols) }
        } else {
            Array(1) { FloatArray(safeCols) }
        }
    }

    private fun readOutputScores(output: Any, outputType: DataType, outputTensor: org.tensorflow.lite.Tensor): FloatArray {
        return if (outputType == DataType.UINT8) {
            val raw = (output as Array<ByteArray>)[0]
            val quant = outputTensor.quantizationParams()
            val scale = quant.scale
            val zero = quant.zeroPoint
            FloatArray(raw.size) { idx ->
                val asInt = raw[idx].toInt() and 0xFF
                ((asInt - zero) * scale)
            }
        } else {
            (output as Array<FloatArray>)[0]
        }
    }

    private fun enforceUnsafeContent(packageName: String, unsafeType: UnsafeType) {
        val now = System.currentTimeMillis()
        val cooldownMs = if (
            unsafeType == UnsafeType.APP_BLOCK ||
            unsafeType == UnsafeType.APP_TIME_LIMIT ||
            unsafeType == UnsafeType.SCREEN_TIME
        ) {
            0L
        } else {
            GENERAL_UNSAFE_COOLDOWN_MS
        }
        if ((now - lastUnsafeAtMillis) < cooldownMs) {
            return
        }
        lastUnsafeAtMillis = now
        if (unsafeType == UnsafeType.APP_BLOCK) {
            cooldownPackageName = null
            cooldownUntilMillis = 0L
        } else {
            cooldownPackageName = packageName
            cooldownUntilMillis = now + POST_BLOCK_SCAN_COOLDOWN_MS
        }

        showNativeShield(unsafeType)

        try {
            val goHome = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            startActivity(goHome)
            Log.d(TAG, "Background scanner redirected unsafe app to home: $packageName")
        } catch (e: Exception) {
            Log.e(TAG, "enforceUnsafeContent failed: ${e.message}", e)
        }
    }

    private fun showNativeShield(unsafeType: UnsafeType) {
        val now = System.currentTimeMillis()
        if ((now - lastNativeShieldAtMillis) < 2000L) {
            return
        }
        lastNativeShieldAtMillis = now

        Handler(Looper.getMainLooper()).post {
            if (shieldView != null) {
                return@post
            }

            try {
                val wm = getSystemService(WINDOW_SERVICE) as WindowManager
                shieldWindowManager = wm

                val root = FrameLayout(this)

                val imageView = ImageView(this).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    )
                    scaleType = ImageView.ScaleType.FIT_XY

                    val assetCandidates = fallbackAssetCandidatesForUnsafeType(unsafeType)
                    val bitmap: Bitmap? = loadFirstAvailableBitmapFromAssets(assetCandidates)
                    if (bitmap != null) {
                        setImageBitmap(bitmap)
                    } else {
                        Log.e(TAG, "Failed to load native shield image from candidates: $assetCandidates")
                        setBackgroundColor(Color.BLACK)
                    }
                }

                val button = Button(this).apply {
                    text = "Exit To Home Screen"
                    setTextColor(Color.WHITE)
                    textSize = 18f
                    try {
                        typeface = Typeface.createFromAsset(
                            applicationContext.assets,
                            "flutter_assets/assets/fonts/ComicNeueSansID.ttf",
                        )
                    } catch (_: Exception) {
                    }
                    setPadding(60, 30, 60, 30)
                    background = android.graphics.drawable.GradientDrawable().apply {
                        setColor(Color.parseColor("#8ac1ff"))
                        cornerRadius = 24f
                    }
                    var isExitProcessing = false
                    setOnClickListener {
                        if (isExitProcessing) {
                            return@setOnClickListener
                        }
                        isExitProcessing = true
                        hideNativeShield()
                        try {
                            val goHome = Intent(Intent.ACTION_MAIN).apply {
                                addCategory(Intent.CATEGORY_HOME)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                            }
                            startActivity(goHome)
                        } catch (_: Exception) {
                        } finally {
                            Handler(Looper.getMainLooper()).postDelayed({
                                isExitProcessing = false
                            }, 600)
                        }
                    }
                }

                val buttonParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
                ).apply {
                    bottomMargin = 100
                }

                root.addView(imageView)
                if (unsafeType != UnsafeType.SCREEN_TIME) {
                    root.addView(button, buttonParams)
                }

                val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    WindowManager.LayoutParams.TYPE_PHONE
                }

                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    overlayType,
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                    PixelFormat.TRANSLUCENT,
                )

                wm.addView(root, params)
                shieldView = root
                shieldUnsafeType = unsafeType
            } catch (e: Exception) {
                Log.e(TAG, "showNativeShield failed: ${e.message}", e)
                shieldView = null
                shieldUnsafeType = null
            }
        }
    }

    private fun hideNativeShield() {
        Handler(Looper.getMainLooper()).post {
            val view = shieldView ?: return@post
            val wm = shieldWindowManager ?: return@post
            try {
                wm.removeView(view)
            } catch (_: Exception) {
            } finally {
                shieldView = null
                shieldWindowManager = null
                shieldUnsafeType = null
            }
        }
    }

    private fun fallbackAssetCandidatesForUnsafeType(unsafeType: UnsafeType): List<String> {
        val primary = when (unsafeType) {
            UnsafeType.WEAPON -> "assets/images/noWeapons.png"
            UnsafeType.GORE -> "assets/images/noGore.jpg"
            UnsafeType.NSFW -> "assets/images/noNSFW.png"
            UnsafeType.APP_BLOCK -> "assets/images/blockApp.png"
            UnsafeType.APP_TIME_LIMIT -> "assets/images/appLimit.png"
            UnsafeType.SCREEN_TIME -> "assets/images/screenTimeExceeded.png"
            UnsafeType.GENERIC -> "assets/images/noNSFW.png"
        }

        val candidates = mutableListOf(
            "flutter_assets/$primary",
            primary,
        )

        if (unsafeType == UnsafeType.APP_TIME_LIMIT) {
            candidates.add("flutter_assets/assets/images/blockApp.png")
            candidates.add("assets/images/blockApp.png")
        }

        return candidates
    }

    private fun loadFirstAvailableBitmapFromAssets(paths: List<String>): Bitmap? {
        for (path in paths) {
            try {
                applicationContext.assets.open(path).use { stream ->
                    val bitmap = BitmapFactory.decodeStream(stream)
                    if (bitmap != null) {
                        Log.d(TAG, "Native shield asset loaded from path: $path")
                        return bitmap
                    }
                    Log.w(TAG, "Native shield asset decode returned null for path: $path")
                }
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun isChildSafeAppForeground(): Boolean {
        return try {
            val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val processes = manager.runningAppProcesses ?: return false
            processes.any {
                it.processName == packageName &&
                    it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun shouldSkipPackage(packageName: String): Boolean {
        val lower = packageName.lowercase()
        if (lower == "com.example.child_safe_app" ||
            lower == "com.android.systemui" ||
            lower == "com.android.launcher3" ||
            lower == "com.google.android.gms" ||
            lower.startsWith("com.google.android.gms") ||
            lower.contains("keyboard") ||
            lower.contains("swiftkey") ||
            lower.contains("inputmethod")
        ) {
            return true
        }

        if (isLikelyGamingPackage(lower)) {
            return true
        }

        val excluded = getPrefs().getStringSet(KEY_SCAN_EXCLUDED, emptySet()) ?: emptySet()
        if (excluded.contains(packageName)) {
            Log.d(TAG, "Skipping scan: package excluded via prefs: $packageName")
            return true
        }

        if (firestoreExcludedPackages.contains(packageName)) {
            Log.d(TAG, "Skipping scan: package excluded via Firestore: $packageName")
            return true
        }

        return false
    }

    private fun shouldSkipPackageForLimitEnforcement(packageName: String): Boolean {
        val lower = packageName.lowercase()
        return lower == "com.example.child_safe_app" ||
            lower == "com.android.systemui" ||
            lower == "com.google.android.gms" ||
            lower.startsWith("com.google.android.gms") ||
            lower.contains("keyboard") ||
            lower.contains("swiftkey") ||
            lower.contains("inputmethod")
    }

    private fun initializeInteractiveState() {
        isDeviceInteractive = isInteractiveNow()
        Log.d(TAG, "Initial interactive state: $isDeviceInteractive")
    }

    private fun registerScreenStateReceiver() {
        if (screenStateReceiver != null) {
            return
        }

        screenStateReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> {
                        isDeviceInteractive = false
                        Log.d(TAG, "Screen turned off; pausing background scans")
                    }

                    Intent.ACTION_SCREEN_ON,
                    Intent.ACTION_USER_PRESENT -> {
                        isDeviceInteractive = isInteractiveNow()
                        Log.d(TAG, "Screen active event received; interactive=$isDeviceInteractive")

                        val packageName = activePackageName
                        if (isDeviceInteractive && !packageName.isNullOrBlank()) {
                            dispatchMaybeScan(packageName)
                        }
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenStateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenStateReceiver, filter)
        }
    }

    private fun unregisterScreenStateReceiver() {
        val receiver = screenStateReceiver ?: return
        try {
            unregisterReceiver(receiver)
        } catch (_: Exception) {
        } finally {
            screenStateReceiver = null
        }
    }

    private fun canScanNow(): Boolean {
        val nativeScanEnabled = getPrefs().getBoolean(KEY_NATIVE_SCAN_ENABLED, true)
        if (!nativeScanEnabled) {
            return false
        }

        if (!isDeviceInteractive) {
            return false
        }

        return isInteractiveNow()
    }

    private fun isInteractiveNow(): Boolean {
        return try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isInteractive
        } catch (_: Exception) {
            true
        }
    }

    private fun getTodayStartMs(): Long {
        val now = java.util.Calendar.getInstance()
        now.set(java.util.Calendar.HOUR_OF_DAY, 0)
        now.set(java.util.Calendar.MINUTE, 0)
        now.set(java.util.Calendar.SECOND, 0)
        now.set(java.util.Calendar.MILLISECOND, 0)
        return now.timeInMillis
    }

    private fun getTodayUsageSecondsForPackage(packageName: String): Long {
        return try {
            val startMs = getTodayStartMs()
            val endMs = System.currentTimeMillis()
            val totalMs = collectUsageByPackageFromEvents(startMs, endMs)[packageName]?.totalMs ?: 0L

            totalMs / 1000L
        } catch (_: Exception) {
            0L
        }
    }

    private fun getTodayTotalUsageSeconds(): Long {
        return try {
            val startMs = getTodayStartMs()
            val endMs = System.currentTimeMillis()
            val totalMs = collectUsageByPackageFromEvents(startMs, endMs)
                .values
                .sumOf { it.totalMs }

            totalMs / 1000L
        } catch (_: Exception) {
            0L
        }
    }

    private fun maybeSyncUsageToFirestore() {
        val nowMs = System.currentTimeMillis()
        if ((nowMs - lastUsageFirestoreSyncAtMs) < USAGE_FIRESTORE_SYNC_INTERVAL_MS) {
            return
        }

        if (usageSyncInFlight) {
            return
        }

        if (!isInteractiveNow()) {
            return
        }

        val childId = getPrefs().getString(KEY_SCAN_CHILD_ID, null)
        if (childId.isNullOrBlank()) {
            return
        }

        usageSyncInFlight = true

        val todayStartMs = getTodayStartMs()
        val weekStartMs = java.util.Calendar.getInstance().apply {
            add(java.util.Calendar.DAY_OF_MONTH, -6)
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }.timeInMillis

        try {
            val db = FirebaseFirestore.getInstance()

            val todayUsage = collectUsageByPackageFromEvents(todayStartMs, nowMs)
            val weekUsage = collectUsageByPackageFromEvents(weekStartMs, nowMs)

            val appsPayload = todayUsage.entries
                .sortedByDescending { it.value.totalMs }
                .take(20)
                .map { entry ->
                    val packageName = entry.key
                    val todayMinutes = (entry.value.totalMs / 60000L).toInt()
                    val weeklyTotalMinutes = ((weekUsage[packageName]?.totalMs ?: entry.value.totalMs) / 60000L).toInt()
                    val weeklyAverageMinutes = weeklyTotalMinutes / 7.0

                    mapOf(
                        "packageName" to packageName,
                        "appName" to packageName,
                        "minutesToday" to todayMinutes,
                        "minutesYesterday" to 0,
                        "weeklyAverage" to weeklyAverageMinutes,
                        "weeklyTotalMinutes" to weeklyTotalMinutes,
                        "iconUrl" to null,
                    )
                }

            val totalTodayMinutes = (getTodayTotalUsageSeconds() / 60L).toInt()
            val last7Days = mutableListOf<Map<String, Any>>()
            var totalLast7Minutes = 0

            for (i in 6 downTo 0) {
                val dayStartCal = java.util.Calendar.getInstance().apply {
                    add(java.util.Calendar.DAY_OF_MONTH, -i)
                    set(java.util.Calendar.HOUR_OF_DAY, 0)
                    set(java.util.Calendar.MINUTE, 0)
                    set(java.util.Calendar.SECOND, 0)
                    set(java.util.Calendar.MILLISECOND, 0)
                }
                val dayEndCal = (dayStartCal.clone() as java.util.Calendar).apply {
                    add(java.util.Calendar.DAY_OF_MONTH, 1)
                }

                val dayStart = dayStartCal.timeInMillis
                val dayEnd = minOf(dayEndCal.timeInMillis, nowMs)
                val dayMinutes = if (dayEnd > dayStart) {
                    (collectUsageByPackageFromEvents(dayStart, dayEnd).values.sumOf { it.totalMs } / 60000L).toInt()
                } else {
                    0
                }

                totalLast7Minutes += dayMinutes
                val dayLabel = String.format(
                    "%04d-%02d-%02d",
                    dayStartCal.get(java.util.Calendar.YEAR),
                    dayStartCal.get(java.util.Calendar.MONTH) + 1,
                    dayStartCal.get(java.util.Calendar.DAY_OF_MONTH),
                )
                last7Days.add(
                    mapOf(
                        "date" to dayLabel,
                        "minutes" to dayMinutes,
                    ),
                )
            }

            val dailyAverage = totalLast7Minutes / 7.0

            val appUsageRef = db
                .collection("users")
                .document(childId)
                .collection("appUsage")
                .document("current")

            val screenTimeRef = db
                .collection("users")
                .document(childId)
                .collection("screenTime")
                .document("current")

            val batch = db.batch()
            batch.set(
                appUsageRef,
                mapOf(
                    "apps" to appsPayload,
                    "lastUpdated" to FieldValue.serverTimestamp(),
                ),
            )
            batch.set(
                screenTimeRef,
                mapOf(
                    "last7Days" to last7Days,
                    "dailyAverage" to dailyAverage,
                    "totalToday" to totalTodayMinutes,
                    "lastUpdated" to FieldValue.serverTimestamp(),
                ),
            )
            batch.commit()
                .addOnSuccessListener {
                    lastUsageFirestoreSyncAtMs = System.currentTimeMillis()
                    usageSyncInFlight = false
                }
                .addOnFailureListener { e ->
                    usageSyncInFlight = false
                    Log.e(TAG, "Native usage Firestore sync failed: ${e.message}", e)
                }
        } catch (e: Exception) {
            usageSyncInFlight = false
            Log.e(TAG, "maybeSyncUsageToFirestore failed: ${e.message}", e)
        }
    }

    private fun maybeEnforceUsageLimits(packageName: String): Boolean {
        val appTimeLimitExceeded = isAppTimeLimitExceeded(packageName)
        if (appTimeLimitExceeded) {
            if (appTimeLimitLatchedPackage == packageName) {
                emitScanResult(packageName, true, "APP_TIME_LIMIT_LATCHED", null, null, null, null)
                return true
            }

            appTimeLimitLatchedPackage = packageName
            appTimeLimitLastAwayAtMillis = 0L
            emitScanResult(packageName, true, "APP_TIME_LIMIT", null, null, null, null)
            enforceUnsafeContent(packageName, UnsafeType.APP_TIME_LIMIT)
            return true
        }

        if (isDailyScreenTimeLimitExceeded()) {
            if (dailyScreenTimeLatchedPackage == packageName) {
                emitScanResult(packageName, true, "SCREEN_TIME_LIMIT_LATCHED", null, null, null, null)
                return true
            }

            dailyScreenTimeLatchedPackage = packageName
            dailyScreenTimeLastAwayAtMillis = 0L
            emitScanResult(packageName, true, "SCREEN_TIME_LIMIT", null, null, null, null)
            enforceUnsafeContent(packageName, UnsafeType.SCREEN_TIME)
            return true
        }

        maybeClearDailyScreenTimeShieldIfResolved()

        return false
    }

    private fun maybeClearDailyScreenTimeShieldIfResolved() {
        if (isDailyScreenTimeLimitExceeded()) {
            return
        }

        val hadDailyLatch = !dailyScreenTimeLatchedPackage.isNullOrBlank()
        if (!hadDailyLatch) {
            return
        }

        dailyScreenTimeLatchedPackage = null
        dailyScreenTimeLastAwayAtMillis = 0L
        Log.d(TAG, "Daily screen-time limit resolved; cleared daily latch")

        val canHideAsDailyShield = shieldUnsafeType == UnsafeType.SCREEN_TIME || shieldUnsafeType == null
        if (shieldView != null && canHideAsDailyShield) {
            hideNativeShield()
        }
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
            if (shouldExcludePackageFromUsage(packageName)) {
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

    private data class UsageWindowStats(
        val totalMs: Long,
        val lastUsedMs: Long,
    )

    private fun shouldExcludePackageFromUsage(packageName: String?): Boolean {
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

    private fun getAppTimeLimitSeconds(packageName: String): Long {
        val entries = getPrefs().getStringSet(KEY_APP_TIME_LIMITS, emptySet()) ?: emptySet()
        val prefix = "$packageName="
        val entry = entries.firstOrNull { it.startsWith(prefix) } ?: return 0L
        return entry.substringAfter("=", "0").toLongOrNull() ?: 0L
    }

    private fun isAppTimeLimitExceeded(packageName: String): Boolean {
        val perAppLimitSeconds = getAppTimeLimitSeconds(packageName)
        if (perAppLimitSeconds > 0L) {
            val usedForAppSeconds = getTodayUsageSecondsForPackage(packageName)
            if (usedForAppSeconds >= perAppLimitSeconds) {
                return true
            }
        }

        return false
    }

    private fun isDailyScreenTimeLimitExceeded(): Boolean {
        val allowanceMinutes = getPrefs().getFloat(KEY_DAILY_ALLOWANCE_MINUTES, 0f).toDouble()
        val bonusMinutes = getPrefs().getFloat(KEY_DAILY_BONUS_MINUTES, 0f).toDouble()
        val totalAllowedSeconds = ((allowanceMinutes + bonusMinutes) * 60.0).toLong()
        if (totalAllowedSeconds <= 0L) {
            return false
        }

        val dayStartMs = getPrefs().getLong(KEY_DAILY_DAY_START_MS, 0L)
        if (dayStartMs <= 0L) {
            return false
        }

        val usedTodaySeconds = getTodayTotalUsageSeconds()
        return usedTodaySeconds >= totalAllowedSeconds
    }

    private fun shouldPreserveActivePackageOnSkip(packageName: String): Boolean {
        val lower = packageName.lowercase()
        return lower == "com.android.systemui" ||
            lower == "com.android.launcher3" ||
            lower.contains("keyboard") ||
            lower.contains("swiftkey") ||
            lower.contains("inputmethod")
    }

    private fun isLikelyGamingPackage(lowerPackageName: String): Boolean {
        if (lowerPackageName.contains(".game") || lowerPackageName.contains("gaming")) {
            return true
        }

        val knownGamingPrefixes = listOf(
            "com.supercell",
            "com.riotgames",
            "com.epicgames",
            "com.gameloft",
            "com.mojang",
            "com.ea.",
            "com.activision",
            "com.roblox",
            "com.king.",
            "com.tencent.tmgp",
            "com.miHoYo",
            "com.habby",
            "com.playrix",
            "com.zeptolab",
            "com.miniclip",
        )

        return knownGamingPrefixes.any { prefix ->
            lowerPackageName.startsWith(prefix.lowercase())
        }
    }

    private fun ensureExclusionsListener() {
        val childId = getPrefs().getString(KEY_SCAN_CHILD_ID, null)

        if (childId.isNullOrBlank()) {
            exclusionsListener?.remove()
            exclusionsListener = null
            exclusionsChildId = null
            firestoreExcludedPackages = emptySet()
            return
        }

        if (exclusionsListener != null && exclusionsChildId == childId) {
            return
        }

        exclusionsListener?.remove()
        exclusionsListener = null
        exclusionsChildId = childId

        exclusionsListener = FirebaseFirestore.getInstance()
            .collection("users")
            .document(childId)
            .collection("scanSettings")
            .document("exclusions")
            .collection("apps")
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.e(TAG, "ensureExclusionsListener error: ${error.message}", error)
                    return@addSnapshotListener
                }

                val packages = snapshot?.documents
                    ?.mapNotNull { it.getString("packageName")?.takeIf { name -> name.isNotBlank() } }
                    ?.toSet()
                    ?: emptySet()

                firestoreExcludedPackages = packages
                Log.d(TAG, "Native exclusions synced from Firestore: ${packages.size} apps")
            }
    }

    private fun ensureFilterSettingsListener() {
        val childId = getPrefs().getString(KEY_SCAN_CHILD_ID, null)
        val parentId = getPrefs().getString(KEY_SCAN_PARENT_ID, null)

        if (childId.isNullOrBlank() || parentId.isNullOrBlank()) {
            filterSettingsListener?.remove()
            filterSettingsListener = null
            filterSettingsParentId = null
            filterSettingsChildId = null
            return
        }

        if (
            filterSettingsListener != null &&
            filterSettingsParentId == parentId &&
            filterSettingsChildId == childId
        ) {
            return
        }

        filterSettingsListener?.remove()
        filterSettingsListener = null
        filterSettingsParentId = parentId
        filterSettingsChildId = childId

        filterSettingsListener = FirebaseFirestore.getInstance()
            .collection("users")
            .document(parentId)
            .collection("children")
            .document(childId)
            .collection("settings")
            .document("filter_settings")
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.e(TAG, "ensureFilterSettingsListener error: ${error.message}", error)
                    return@addSnapshotListener
                }

                val data = snapshot?.data ?: return@addSnapshotListener

                val pornEnabled = data["pornFilterEnabled"] as? Boolean ?: false
                val violenceEnabled = data["violenceFilterEnabled"] as? Boolean ?: false
                val intervalSecondsRaw = (data["scanIntervalSeconds"] as? Number)?.toInt() ?: 3
                val intervalSeconds = intervalSecondsRaw.coerceIn(1, 30)

                getPrefs().edit()
                    .putBoolean(KEY_SCAN_PORN, pornEnabled)
                    .putBoolean(KEY_SCAN_VIOLENCE, violenceEnabled)
                    .putInt(KEY_SCAN_INTERVAL_SECONDS, intervalSeconds)
                    .putBoolean(KEY_NATIVE_SCAN_ENABLED, true)
                    .apply()

                val intervalMs = (intervalSeconds * 1000L)
                    .coerceIn(MIN_PERIODIC_SCAN_INTERVAL_MS, MAX_PERIODIC_SCAN_INTERVAL_MS)
                restartPeriodicScannerWithInterval(intervalMs)

                Log.d(
                    TAG,
                    "Native filter settings synced: porn=$pornEnabled violence=$violenceEnabled interval=${intervalSeconds}s",
                )
            }
    }

    private fun ensureBlockedAppsListener() {
        val childId = getPrefs().getString(KEY_SCAN_CHILD_ID, null)
        val parentId = getPrefs().getString(KEY_SCAN_PARENT_ID, null)

        if (childId.isNullOrBlank() || parentId.isNullOrBlank()) {
            blockedAppsListener?.remove()
            blockedAppsListener = null
            blockedAppsParentId = null
            blockedAppsChildId = null
            return
        }

        if (
            blockedAppsListener != null &&
            blockedAppsParentId == parentId &&
            blockedAppsChildId == childId
        ) {
            return
        }

        blockedAppsListener?.remove()
        blockedAppsListener = null
        blockedAppsParentId = parentId
        blockedAppsChildId = childId

        blockedAppsListener = FirebaseFirestore.getInstance()
            .collection("users")
            .document(parentId)
            .collection("blocked_apps")
            .whereEqualTo("childId", childId)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.e(TAG, "ensureBlockedAppsListener error: ${error.message}", error)
                    return@addSnapshotListener
                }

                val nowMs = System.currentTimeMillis()
                val blockedPackages = snapshot?.documents
                    ?.mapNotNull { doc ->
                        val packageName = doc.getString("packageName")?.takeIf { it.isNotBlank() }
                            ?: return@mapNotNull null
                        val blockedUntil = doc.getTimestamp("blockedUntil")
                        val isActive = blockedUntil == null || blockedUntil.toDate().time > nowMs
                        if (isActive) packageName else null
                    }
                    ?.toSet()
                    ?: emptySet()

                getPrefs().edit()
                    .putStringSet(KEY_BLOCKED_APPS, blockedPackages)
                    .apply()

                Log.d(TAG, "Native blocked apps synced from Firestore: ${blockedPackages.size} active packages")

                val currentPackage = activePackageName
                if (!currentPackage.isNullOrBlank() && blockedPackages.contains(currentPackage)) {
                    blockedAppShieldLatchedPackage = currentPackage
                    blockedAppLastAwayAtMillis = 0L
                    enforceUnsafeContent(currentPackage, UnsafeType.APP_BLOCK)
                }
            }
    }

    private fun ensureScreenTimeSettingsListener() {
        val childId = getPrefs().getString(KEY_SCAN_CHILD_ID, null)

        if (childId.isNullOrBlank()) {
            screenTimeSettingsListener?.remove()
            screenTimeSettingsListener = null
            screenTimeSettingsChildId = null
            getPrefs().edit()
                .remove(KEY_DAILY_ALLOWANCE_MINUTES)
                .remove(KEY_DAILY_BONUS_MINUTES)
                .remove(KEY_DAILY_DAY_START_MS)
                .apply()
            return
        }

        if (screenTimeSettingsListener != null && screenTimeSettingsChildId == childId) {
            return
        }

        screenTimeSettingsListener?.remove()
        screenTimeSettingsListener = null
        screenTimeSettingsChildId = childId

        screenTimeSettingsListener = FirebaseFirestore.getInstance()
            .collection("users")
            .document(childId)
            .collection("gamification")
            .document("tomatoPlant")
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.e(TAG, "ensureScreenTimeSettingsListener error: ${error.message}", error)
                    return@addSnapshotListener
                }

                val data = snapshot?.data
                val allowanceMinutes = (data?.get("screenTimeAllowanceMinutes") as? Number)?.toFloat() ?: 0f
                val bonusMinutes = (data?.get("bonusMinutes") as? Number)?.toFloat() ?: 0f
                val dayStartMs = (data?.get("dayStart") as? com.google.firebase.Timestamp)?.toDate()?.time ?: 0L

                getPrefs().edit()
                    .putFloat(KEY_DAILY_ALLOWANCE_MINUTES, allowanceMinutes)
                    .putFloat(KEY_DAILY_BONUS_MINUTES, bonusMinutes)
                    .putLong(KEY_DAILY_DAY_START_MS, dayStartMs)
                    .apply()

                Log.d(
                    TAG,
                    "Native screen-time settings synced: allowance=${allowanceMinutes}m bonus=${bonusMinutes}m dayStartMs=$dayStartMs",
                )

                maybeClearDailyScreenTimeShieldIfResolved()

                val currentPackage = activePackageName
                if (!currentPackage.isNullOrBlank()) {
                    if (isAppTimeLimitExceeded(currentPackage)) {
                        if (appTimeLimitLatchedPackage != currentPackage) {
                            appTimeLimitLatchedPackage = currentPackage
                            appTimeLimitLastAwayAtMillis = 0L
                            enforceUnsafeContent(currentPackage, UnsafeType.APP_TIME_LIMIT)
                        }
                    } else if (isDailyScreenTimeLimitExceeded()) {
                        if (dailyScreenTimeLatchedPackage != currentPackage) {
                            dailyScreenTimeLatchedPackage = currentPackage
                            dailyScreenTimeLastAwayAtMillis = 0L
                            enforceUnsafeContent(currentPackage, UnsafeType.SCREEN_TIME)
                        }
                    }
                }
            }
    }

    private fun ensureAppTimeLimitsListener() {
        val childId = getPrefs().getString(KEY_SCAN_CHILD_ID, null)
        val parentId = getPrefs().getString(KEY_SCAN_PARENT_ID, null)

        if (childId.isNullOrBlank() || parentId.isNullOrBlank()) {
            appTimeLimitsListener?.remove()
            appTimeLimitsListener = null
            appTimeLimitsParentId = null
            appTimeLimitsChildId = null
            getPrefs().edit().remove(KEY_APP_TIME_LIMITS).apply()
            return
        }

        if (
            appTimeLimitsListener != null &&
            appTimeLimitsParentId == parentId &&
            appTimeLimitsChildId == childId
        ) {
            return
        }

        appTimeLimitsListener?.remove()
        appTimeLimitsListener = null
        appTimeLimitsParentId = parentId
        appTimeLimitsChildId = childId

        appTimeLimitsListener = FirebaseFirestore.getInstance()
            .collection("users")
            .document(parentId)
            .collection("children")
            .document(childId)
            .collection("appTimeLimits")
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.e(TAG, "ensureAppTimeLimitsListener error: ${error.message}", error)
                    return@addSnapshotListener
                }

                val limits = snapshot?.documents
                    ?.mapNotNull { doc ->
                        val packageName = doc.getString("packageName")?.takeIf { it.isNotBlank() }
                            ?: return@mapNotNull null
                        val totalSecondsLimit = (doc.get("totalSecondsLimit") as? Number)?.toLong()
                        val minutesLimit = (doc.get("minutesLimit") as? Number)?.toLong() ?: 0L
                        val secondsLimit = (doc.get("secondsLimit") as? Number)?.toLong() ?: 0L

                        val computedSeconds = when {
                            totalSecondsLimit != null -> totalSecondsLimit
                            else -> (minutesLimit * 60L) + secondsLimit
                        }

                        if (computedSeconds > 0L) "$packageName=$computedSeconds" else null
                    }
                    ?.toSet()
                    ?: emptySet()

                getPrefs().edit()
                    .putStringSet(KEY_APP_TIME_LIMITS, limits)
                    .apply()

                Log.d(TAG, "Native app time limits synced: ${limits.size} active limits")

                val currentPackage = activePackageName
                if (!currentPackage.isNullOrBlank()) {
                    if (isAppTimeLimitExceeded(currentPackage)) {
                        if (appTimeLimitLatchedPackage != currentPackage) {
                            appTimeLimitLatchedPackage = currentPackage
                            appTimeLimitLastAwayAtMillis = 0L
                            enforceUnsafeContent(currentPackage, UnsafeType.APP_TIME_LIMIT)
                        }
                    } else if (isDailyScreenTimeLimitExceeded()) {
                        if (dailyScreenTimeLatchedPackage != currentPackage) {
                            dailyScreenTimeLatchedPackage = currentPackage
                            dailyScreenTimeLastAwayAtMillis = 0L
                            enforceUnsafeContent(currentPackage, UnsafeType.SCREEN_TIME)
                        }
                    }
                }
            }
    }

    private fun isBlockedPackage(packageName: String): Boolean {
        val blocked = getPrefs().getStringSet(KEY_BLOCKED_APPS, emptySet()) ?: emptySet()
        return blocked.contains(packageName)
    }

    private fun logDetectionAndApplyPenalty(
        packageName: String,
        unsafeType: UnsafeType,
        reason: String,
        nsfwScore: Float?,
        violenceScore: Float?,
    ) {
        val childId = getPrefs().getString(KEY_SCAN_CHILD_ID, null)
        if (childId.isNullOrBlank()) {
            return
        }

        val detectionType = when (unsafeType) {
            UnsafeType.NSFW -> "nsfw"
            UnsafeType.WEAPON -> "gun"
            UnsafeType.GORE -> "gore"
            else -> null
        } ?: return

        val confidenceScore = when (unsafeType) {
            UnsafeType.NSFW -> (nsfwScore ?: 1f).toDouble()
            UnsafeType.WEAPON,
            UnsafeType.GORE,
            -> (violenceScore ?: 1f).toDouble()
            else -> 1.0
        }

        val metadata = mutableMapOf<String, Any>(
            "source" to "native_background_scanner",
            "reason" to reason,
        )
        if (nsfwScore != null) {
            metadata["nsfwScore"] = nsfwScore.toDouble()
        }
        if (violenceScore != null) {
            metadata["violenceScore"] = violenceScore.toDouble()
        }

        FirebaseFirestore.getInstance()
            .collection("users")
            .document(childId)
            .collection("detections")
            .add(
                mapOf(
                    "packageName" to packageName,
                    "appName" to packageName,
                    "detectionType" to detectionType,
                    "confidenceScore" to confidenceScore,
                    "timestamp" to FieldValue.serverTimestamp(),
                    "metadata" to metadata,
                ),
            )
            .addOnFailureListener { e ->
                Log.e(TAG, "Native detection logging failed: ${e.message}", e)
            }

        deductTomatoWaterNative(childId, 3)
    }

    private fun deductTomatoWaterNative(childId: String, points: Int) {
        val safePoints = if (points <= 0) 0 else points
        if (safePoints <= 0) {
            return
        }

        val db = FirebaseFirestore.getInstance()
        val docRef = db
            .collection("users")
            .document(childId)
            .collection("gamification")
            .document("tomatoPlant")

        db.runTransaction { transaction ->
            val snapshot = transaction.get(docRef)
            val data = snapshot.data ?: emptyMap<String, Any>()

            val now = java.util.Date()
            val calendar = java.util.Calendar.getInstance().apply {
                time = now
                set(java.util.Calendar.HOUR_OF_DAY, 0)
                set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
            }
            val todayStart = calendar.time

            var level = (data["level"] as? Number)?.toInt() ?: 1
            var growthPoints = (data["growthPoints"] as? Number)?.toInt() ?: 0
            var dailyPenaltyPoints = (data["dailyPenaltyPoints"] as? Number)?.toInt() ?: 0

            val dayStartDate = when (val dayStartRaw = data["dayStart"]) {
                is com.google.firebase.Timestamp -> dayStartRaw.toDate()
                is java.util.Date -> dayStartRaw
                else -> todayStart
            }

            val stateDayStart = java.util.Calendar.getInstance().apply {
                time = dayStartDate
                set(java.util.Calendar.HOUR_OF_DAY, 0)
                set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
            }.time

            if (todayStart.after(stateDayStart)) {
                val firstDayWater = (24 - dailyPenaltyPoints).coerceIn(0, 24)
                var updatedGrowth = growthPoints + firstDayWater
                var updatedLevel = level

                if (updatedLevel < 5 && updatedGrowth >= 100) {
                    updatedLevel += 1
                    updatedGrowth = 0
                }

                level = updatedLevel.coerceAtMost(5)
                growthPoints = if (level >= 5) updatedGrowth.coerceIn(0, 100) else updatedGrowth
                dailyPenaltyPoints = 0
            }

            val remainingWaterCapacity = (24 - dailyPenaltyPoints).coerceIn(0, 24)
            val waterPenalty = safePoints.coerceIn(0, remainingWaterCapacity)
            var growthPenalty = safePoints - waterPenalty

            val updatedPenalty = (dailyPenaltyPoints + waterPenalty).coerceIn(0, 24)

            var updatedLevel = level
            var updatedGrowth = growthPoints

            while (growthPenalty > 0) {
                if (updatedGrowth > 0) {
                    val applied = minOf(growthPenalty, updatedGrowth)
                    updatedGrowth -= applied
                    growthPenalty -= applied
                    continue
                }

                if (updatedLevel <= 1) {
                    break
                }

                updatedLevel -= 1
                updatedGrowth = 100
            }

            val update = mutableMapOf<String, Any>(
                "level" to updatedLevel,
                "growthPoints" to updatedGrowth,
                "dailyPenaltyPoints" to updatedPenalty,
                "lastUpdated" to FieldValue.serverTimestamp(),
            )

            if (!snapshot.exists()) {
                update["tomatoes"] = 0
                update["screenTimeAllowanceMinutes"] = 0.0
                update["bonusMinutes"] = 0.0
                update["lastHarvestDate"] = com.google.firebase.Timestamp(java.util.Date(0))
            }

            update["dayStart"] = com.google.firebase.Timestamp(todayStart)

            transaction.set(docRef, update, com.google.firebase.firestore.SetOptions.merge())
            null
        }.addOnFailureListener { e ->
            Log.e(TAG, "Native tomato deduction failed: ${e.message}", e)
        }
    }

    private fun getPrefs() = getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun emitScanResult(
        packageName: String,
        unsafe: Boolean,
        reason: String,
        nsfwScore: Float?,
        violenceScore: Float?,
        scanPorn: Boolean?,
        scanViolence: Boolean?,
    ) {
        val nsfwText = nsfwScore?.let { String.format("%.3f", it) } ?: "-"
        val violenceText = violenceScore?.let { String.format("%.3f", it) } ?: "-"
        val pornEnabledText = scanPorn?.toString() ?: "-"
        val violenceEnabledText = scanViolence?.toString() ?: "-"

        Log.i(
            TAG,
            "SCAN_RESULT package=$packageName unsafe=$unsafe reason=$reason nsfw=$nsfwText violence=$violenceText scanPorn=$pornEnabledText scanViolence=$violenceEnabledText",
        )
    }

    private fun publishRecoveryFlag(requiresRecovery: Boolean, reason: String?) {
        if (lastRecoveryFlagState == requiresRecovery) {
            return
        }
        lastRecoveryFlagState = requiresRecovery

        val childId = getPrefs().getString(KEY_SCAN_CHILD_ID, null)
        if (childId.isNullOrBlank()) {
            return
        }

        val payload = mutableMapOf<String, Any>(
            "requiresRecovery" to requiresRecovery,
            "updatedAt" to FieldValue.serverTimestamp(),
        )

        if (requiresRecovery) {
            payload["reason"] = reason ?: "Native capture unavailable"
        } else {
            payload["reason"] = ""
        }

        FirebaseFirestore.getInstance()
            .collection("users")
            .document(childId)
            .collection("systemHealth")
            .document("nativeScanRecovery")
            .set(payload)
            .addOnFailureListener { e ->
                Log.e(TAG, "publishRecoveryFlag failed: ${e.message}", e)
            }
    }

    private fun loadModelFile(assetName: String): ByteBuffer {
        // Flutter assets are stored in flutter_assets/ directory
        val flutterAssetPath = "flutter_assets/$assetName"
        val afd = applicationContext.assets.openFd(flutterAssetPath)
        FileInputStream(afd.fileDescriptor).use { inputStream ->
            val fileChannel = inputStream.channel
            return fileChannel.map(FileChannel.MapMode.READ_ONLY, afd.startOffset, afd.declaredLength)
        }
    }

    private fun buildNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Child Safe Background Scan")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setOngoing(true)
            .build()
    }

    private fun currentScannerStatusText(): String {
        return if (!ProjectionSession.hasActiveProjection() || ProjectionSession.imageReader == null) {
            "Waiting for capture session (open app once after reboot)"
        } else {
            "Background content scan active"
        }
    }

    private fun refreshNotificationIfNeeded() {
        val ready = ProjectionSession.hasActiveProjection() && ProjectionSession.imageReader != null
        if (lastNotifiedCaptureReady == ready) {
            return
        }
        lastNotifiedCaptureReady = ready

        val notification = buildNotification(currentScannerStatusText())
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun reconcileRecoveryFlagWithCaptureState() {
        val ready = ProjectionSession.hasActiveProjection() && ProjectionSession.imageReader != null
        if (ready) {
            publishRecoveryFlag(false, null)
        } else {
            publishRecoveryFlag(true, "Capture session unavailable")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Background Scan",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }
}
