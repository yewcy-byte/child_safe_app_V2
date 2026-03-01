package com.example.child_safe_app

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.RenderEffect
import android.graphics.Shader
import android.graphics.Typeface
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import android.util.DisplayMetrics
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityManager
import android.accessibilityservice.AccessibilityServiceInfo
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import pl.droidsonroids.gif.GifDrawable
import kotlinx.coroutines.Dispatchers
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {

    private val TAG = "MainActivity"
    private val CHANNEL = "com.childsafe.app/screen_capture"
    private val DETECTOR_CHANNEL = "com.safetyapp/detector"
    private val LOCATION_CHANNEL = "com.childsafe.app/location"
    private val REQUEST_CODE = 100
    private val REQUEST_CODE_BACKGROUND_LOCATION = 101
    private val scanPrefsName = "childsafe_blocking"
    private val scanPornKey = "scan_porn_enabled"
    private val scanViolenceKey = "scan_violence_enabled"
    private val scanIntervalSecondsKey = "scan_interval_seconds"
    private val scanExcludedKey = "scan_excluded_apps"
    private val groomingEnabledPackagesKey = "grooming_enabled_packages"
    private val scanChildIdKey = "scan_child_id"
    private val scanParentIdKey = "scan_parent_id"
    private val scanEnabledKey = "native_scan_enabled"

    private var appChangeReceiver: BroadcastReceiver? = null
    private var chatTextReceiver: BroadcastReceiver? = null
    private var detectedAppPackage: String? = null
    private lateinit var projectionManager: MediaProjectionManager
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var lastStartServiceRequestAtElapsedMs: Long = 0L
    private var lastProjectionPermissionPromptAtElapsedMs: Long = 0L
    private var isProjectionPermissionInFlight: Boolean = false
    private var deferredStopRequested: Boolean = false
    private var shieldView: View? = null
    private var lastShieldDismissedAtMillis: Long = 0L
    private var shieldIsHiding: Boolean = false
    private var pendingShieldShowType: String? = null
    private var pendingShieldShowImageBase64: String? = null
    private val blockedPrefsName = "childsafe_blocking"
    private val blockedPackagesKey = "blocked_packages"
    private val projectionPermissionPromptCooldownMs = 8_000L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        setupAccessibilityServiceListener()

        projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        Log.d(TAG, "startService called")
                        lastStartServiceRequestAtElapsedMs = SystemClock.elapsedRealtime()
                        deferredStopRequested = false
                        setNativeScanEnabled(true)
                        if (isProjectionPermissionInFlight) {
                            Log.d(TAG, "Media projection permission request already in-flight")
                            result.success(true)
                            return@setMethodCallHandler
                        }

                        // Reuse existing projection session if available to avoid repeated permission requests.
                        val existingProjection = ProjectionSession.mediaProjection
                        if (existingProjection != null) {
                            mediaProjection = existingProjection
                            if (virtualDisplay == null || imageReader == null) {
                                setupVirtualDisplay()
                            }
                            Log.d(TAG, "Reusing existing media projection session")
                            isProjectionPermissionInFlight = false
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        
                        Log.d(TAG, "Requesting media projection permission")
                        // Start foreground service FIRST before requesting permission
                        try {
                            val intent = Intent(this, MediaProjectionService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            Log.d(TAG, "MediaProjectionService started")
                            
                            // Give service time to start foreground
                            Handler(Looper.getMainLooper()).postDelayed({
                                if (ProjectionSession.hasActiveProjection() || mediaProjection != null) {
                                    isProjectionPermissionInFlight = false
                                    Log.d(TAG, "Projection already active at prompt time; skipping dialog")
                                    if (virtualDisplay == null || imageReader == null) {
                                        setupVirtualDisplay()
                                    }
                                    return@postDelayed
                                }

                                val nowElapsed = SystemClock.elapsedRealtime()
                                if ((nowElapsed - lastProjectionPermissionPromptAtElapsedMs) < projectionPermissionPromptCooldownMs) {
                                    isProjectionPermissionInFlight = false
                                    Log.w(TAG, "Suppressing duplicate media projection dialog (cooldown active)")
                                    return@postDelayed
                                }

                                // Only request permission if we don't already have it
                                if (mediaProjection == null) {
                                    lastProjectionPermissionPromptAtElapsedMs = nowElapsed
                                    startActivityForResult(
                                        projectionManager.createScreenCaptureIntent(),
                                        REQUEST_CODE
                                    )
                                    Log.d(TAG, "Media projection permission dialog shown")
                                } else {
                                    isProjectionPermissionInFlight = false
                                    Log.d(TAG, "MediaProjection already exists, setting up virtual display")
                                    setupVirtualDisplay()
                                }
                            }, 500)
                            isProjectionPermissionInFlight = true
                            
                            result.success(true)
                        } catch (e: Exception) {
                            isProjectionPermissionInFlight = false
                            Log.e(TAG, "Error starting service: ${e.message}", e)
                            result.error("SERVICE_ERROR", e.message, null)
                        }
                    }

                    "stopService" -> {
                        val forceStop = call.argument<Boolean>("force") ?: false
                        if (!forceStop) {
                            Log.w(TAG, "Ignoring stopService without force flag to keep background protection alive")
                            result.success(true)
                            return@setMethodCallHandler
                        }

                        if (isProjectionPermissionInFlight) {
                            Log.w(TAG, "stopService requested while projection permission is in-flight; deferring stop")
                            deferredStopRequested = true
                            result.success(true)
                            return@setMethodCallHandler
                        }

                        stopProtectionServices()
                        result.success(true)
                    }

                    "checkAccessibilityService" -> {
                        val isEnabled = isAccessibilityServiceEnabled()
                        Log.d(TAG, "checkAccessibilityService: Accessibility service enabled: $isEnabled")
                        result.success(isEnabled)
                    }

                    "isProjectionActive" -> {
                        val projectionActive =
                            ProjectionSession.hasActiveProjection() && ProjectionSession.imageReader != null
                        result.success(projectionActive)
                    }

                    "isNativeScanServiceRunning" -> {
                        result.success(NativeScanService.isScannerRuntimeRunning())
                    }

                    "requestProjectionPermissionRecovery" -> {
                        try {
                            if (isProjectionPermissionInFlight) {
                                Log.d(TAG, "Recovery skipped: projection permission already in-flight")
                                result.success(true)
                                return@setMethodCallHandler
                            }

                            isProjectionPermissionInFlight = false
                            deferredStopRequested = false

                            stopScreenCapture()
                            ProjectionSession.clear()
                            mediaProjection = null

                            val intent = Intent(this, MediaProjectionService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }

                            Handler(Looper.getMainLooper()).postDelayed({
                                if (!isProjectionPermissionInFlight) {
                                    isProjectionPermissionInFlight = true
                                    lastProjectionPermissionPromptAtElapsedMs = SystemClock.elapsedRealtime()
                                    startActivityForResult(
                                        projectionManager.createScreenCaptureIntent(),
                                        REQUEST_CODE,
                                    )
                                    Log.d(TAG, "Forced media projection recovery permission dialog shown")
                                }
                            }, 400)

                            result.success(true)
                        } catch (e: Exception) {
                            isProjectionPermissionInFlight = false
                            Log.e(TAG, "requestProjectionPermissionRecovery failed: ${e.message}", e)
                            result.success(false)
                        }
                    }

                    "openAccessibilitySettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error opening accessibility settings: ${e.message}")
                            result.error("SETTINGS_ERROR", e.message, null)
                        }
                    }

                    "toggleShield" -> {
                        val show = call.argument<Boolean>("show") ?: false
                        val type = call.argument<String>("type") ?: "nsfw"
                        val imageBase64 = call.argument<String>("imageBase64")
                        toggleShield(show, type, imageBase64)
                        result.success(null)
                    }

                    "captureScreen" -> {
                        Log.d(TAG, "captureScreen called")
                        Log.d(TAG, "mediaProjection: ${mediaProjection != null}, virtualDisplay: ${virtualDisplay != null}, imageReader: ${imageReader != null}")
                        if (mediaProjection == null) {
                            Log.w(TAG, "captureScreen failed: mediaProjection is null")
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        if (virtualDisplay == null) {
                            Log.w(TAG, "captureScreen failed: virtualDisplay is null")
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        try {
                            val capturedPath = performCapture()
                            if (capturedPath != null) {
                                Log.d(TAG, "Screen captured successfully: $capturedPath")
                            } else {
                                Log.w(TAG, "performCapture returned null")
                            }
                            result.success(capturedPath)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error capturing screen: ${e.message}", e)
                            result.success(null)
                        }
                    }

                    "checkAllPermissions" -> {
                        val permissions = mapOf(
                            "overlay" to canDrawOverlays(),
                            "usageStats" to hasUsageStatsPermission(),
                            "mediaProjection" to (mediaProjection != null),
                            "notifications" to hasNotificationPermission()
                        )
                        result.success(permissions)
                    }

                    "openAppSettings" -> {
                        openAppSettings()
                        result.success(true)
                    }

                    "openBatteryBackgroundManagementSettings" -> {
                        openBatteryBackgroundManagementSettings()
                        result.success(true)
                    }

                    "requestOverlayPermission" -> {
                        requestOverlayPermission()
                        result.success(null)
                    }

                    "requestUsageStatsPermission" -> {
                        requestUsageStatsPermission()
                        result.success(null)
                    }

                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(null)
                    }

                    "getForegroundApp" -> {
                        // Try accessibility service first, then fallback to usage stats
                        val appPackage = detectedAppPackage ?: getForegroundAppFromUsageStats()
                        result.success(appPackage)
                    }

                    "startNativeScanService" -> {
                        try {
                            setNativeScanEnabled(true)
                            val scanServiceIntent = Intent(this, NativeScanService::class.java).apply {
                                action = NativeScanService.ACTION_RESTART
                            }
                            val started = dispatchNativeScanIntent(scanServiceIntent)
                            Log.d(TAG, "NativeScanService explicit start requested")
                            result.success(started)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to start NativeScanService: ${e.message}", e)
                            result.success(false)
                        }
                    }

                    "updateNativeScanConfig" -> {
                        val porn = call.argument<Boolean>("pornEnabled") ?: false
                        val violence = call.argument<Boolean>("violenceEnabled") ?: false
                        val scanIntervalSeconds = call.argument<Int>("scanIntervalSeconds") ?: 3
                        saveNativeScanConfig(porn, violence, scanIntervalSeconds)
                        result.success(true)
                    }

                    "updateNativeScanExclusions" -> {
                        val packages = call.argument<List<String>>("packages") ?: emptyList()
                        saveNativeScanExclusions(packages)
                        result.success(true)
                    }

                    "updateNativeGroomingPackages" -> {
                        val packages = call.argument<List<String>>("packages") ?: emptyList()
                        saveNativeGroomingPackages(packages)
                        result.success(true)
                    }

                    "updateNativeChildContext" -> {
                        val childId = call.argument<String>("childId")
                        val parentId = call.argument<String>("parentId")
                        saveNativeChildContext(childId, parentId)
                        result.success(true)
                    }

                    "updateNativeBlockedApps" -> {
                        val packages = call.argument<List<String>>("packages") ?: emptyList()
                        saveBlockedPackages(packages)
                        result.success(true)
                    }

                    "startUsageTracking" -> {
                        UsageTrackingService.startService(this)
                        result.success(true)
                    }

                    "stopUsageTracking" -> {
                        UsageTrackingService.stopService(this)
                        result.success(true)
                    }

                    "getScreenTimeData" -> {
                        val data = getScreenTimeData()
                        result.success(data)
                    }

                    "getAppUsageData" -> {
                        val data = getAppUsageData()
                        result.success(data)
                    }

                    "getTodayUsageSecondsForPackage" -> {
                        val packageNameArg = call.argument<String>("packageName")
                        if (packageNameArg.isNullOrBlank()) {
                            result.success(0)
                        } else {
                            result.success(getTodayUsageSecondsForPackage(packageNameArg))
                        }
                    }

                    "getTodayTotalUsageSeconds" -> {
                        result.success(getTodayTotalUsageSeconds())
                    }

                    "hideNativeServiceShield" -> {
                        try {
                            val intent = Intent(this, NativeScanService::class.java).apply {
                                action = NativeScanService.ACTION_HIDE_SHIELD
                            }
                            result.success(dispatchNativeScanIntent(intent))
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to hide native service shield: ${e.message}", e)
                            result.success(false)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DETECTOR_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showGroomingLocalNotification" -> {
                        val title = call.argument<String>("title")
                            ?: "Child grooming risk detected"
                        val body = call.argument<String>("body")
                            ?: "Potential grooming content detected."
                        showGroomingLocalNotification(title, body)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
        
        // Setup location tracking method channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startLocationService" -> {
                        Log.d(TAG, "Starting location tracking service")
                        LocationTrackingService.startService(this)
                        result.success(true)
                    }
                    
                    "stopLocationService" -> {
                        Log.d(TAG, "Stopping location tracking service")
                        LocationTrackingService.stopService(this)
                        result.success(true)
                    }
                    
                    "requestBackgroundLocation" -> {
                        Log.d(TAG, "Requesting background location permission")
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            if (ContextCompat.checkSelfPermission(
                                    this,
                                    Manifest.permission.ACCESS_BACKGROUND_LOCATION
                                ) != PackageManager.PERMISSION_GRANTED
                            ) {
                                ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                                    REQUEST_CODE_BACKGROUND_LOCATION
                                )
                                result.success(false)
                            } else {
                                result.success(true)
                            }
                        } else {
                            // Background location permission not needed for Android < 10
                            result.success(true)
                        }
                    }
                    
                    else -> result.notImplemented()
                }
            }
    }

    private fun setupAccessibilityServiceListener() {
        Log.d(TAG, "setupAccessibilityServiceListener: Setting up app change receiver")
        appChangeReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                Log.d(TAG, "appChangeReceiver: Broadcast received! Intent action: ${intent?.action}")
                val packageName = intent?.getStringExtra("packageName")
                Log.d(TAG, "appChangeReceiver: Package name extracted: $packageName")
                detectedAppPackage = packageName
                
                // Immediately notify Dart to check if this app is blocked
                if (packageName != null) {
                    Log.d(TAG, "appChangeReceiver: Notifying Dart about app change to $packageName")
                    lifecycleScope.launch(Dispatchers.Main) {
                        try {
                            val engine = flutterEngine
                            if (engine == null) {
                                Log.w(TAG, "appChangeReceiver: Flutter engine unavailable; app changed to $packageName")
                                return@launch
                            }

                            val dartMethod = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                            dartMethod.invokeMethod("onAppChanged", mapOf("packageName" to packageName))
                            Log.d(TAG, "appChangeReceiver: Successfully notified Dart")
                        } catch (e: Exception) {
                            Log.e(TAG, "Error notifying Dart of app change: ${e.message}")
                        }
                    }
                } else {
                    Log.w(TAG, "appChangeReceiver: Package name is null, skipping notification")
                }
            }
        }

        val filter = IntentFilter("com.childsafe.app.APP_CHANGED")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(appChangeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(appChangeReceiver, filter)
        }
        Log.d(TAG, "setupAccessibilityServiceListener: Receiver registered for com.childsafe.app.APP_CHANGED")

        chatTextReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != "com.childsafe.app.CHAT_TEXT_CAPTURED") {
                    return
                }

                val packageName = intent.getStringExtra("packageName") ?: return
                val text = intent.getStringExtra("text") ?: return
                val messageId = intent.getStringExtra("messageId") ?: ""

                Log.d(
                    TAG,
                    "chatTextReceiver: forwarding text package=$packageName messageId=$messageId chars=${text.length}",
                )

                lifecycleScope.launch(Dispatchers.Main) {
                    try {
                        val engine = flutterEngine
                        if (engine == null) {
                            Log.w(TAG, "chatTextReceiver: Flutter engine unavailable")
                            return@launch
                        }

                        MethodChannel(engine.dartExecutor.binaryMessenger, DETECTOR_CHANNEL)
                            .invokeMethod(
                                "onChatTextCaptured",
                                mapOf(
                                    "packageName" to packageName,
                                    "text" to text,
                                    "messageId" to messageId,
                                ),
                            )
                        Log.d(TAG, "chatTextReceiver: forwarded to Dart successfully")
                    } catch (e: Exception) {
                        Log.e(TAG, "chatTextReceiver notify Dart failed: ${e.message}", e)
                    }
                }
            }
        }

        val chatFilter = IntentFilter("com.childsafe.app.CHAT_TEXT_CAPTURED")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(chatTextReceiver, chatFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(chatTextReceiver, chatFilter)
        }
        Log.d(TAG, "setupAccessibilityServiceListener: Receiver registered for com.childsafe.app.CHAT_TEXT_CAPTURED")
    }

    private fun showGroomingLocalNotification(title: String, body: String) {
        try {
            val channelId = "grooming_alerts_channel"
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "Child Grooming Alerts",
                    NotificationManager.IMPORTANCE_HIGH,
                )
                manager.createNotificationChannel(channel)
            }

            val notification = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(android.R.drawable.stat_notify_error)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()

            NotificationManagerCompat.from(this)
                .notify((SystemClock.elapsedRealtime() % Int.MAX_VALUE).toInt(), notification)
        } catch (e: Exception) {
            Log.e(TAG, "showGroomingLocalNotification failed: ${e.message}", e)
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val targetComponent = ComponentName(this, ScreenMonitoringService::class.java)
        val targetFull = targetComponent.flattenToString()
        val targetShort = targetComponent.flattenToShortString()
        try {
            val accessibilityManager =
                getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
            val enabledServiceIds = accessibilityManager
                ?.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                ?.mapNotNull { it.resolveInfo?.serviceInfo }
                ?.map { "${it.packageName}/${it.name}" }
                ?.toSet()
                ?: emptySet()

            if (enabledServiceIds.contains(targetFull) || enabledServiceIds.contains(targetShort)) {
                return true
            }

            val enabledServices = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
            Log.d(TAG, "Enabled accessibility services: $enabledServices")
            Log.d(TAG, "Looking for accessibility service: full=$targetFull short=$targetShort")

            if (enabledServices.isNullOrBlank()) return false

            val services = enabledServices.split(':')
            for (entry in services) {
                val component = ComponentName.unflattenFromString(entry)
                if (component != null && component == targetComponent) {
                    return true
                }

                if (entry == targetFull || entry == targetShort) {
                    return true
                }
            }

            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error checking accessibility service: ${e.message}")
            return false
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (appChangeReceiver != null) {
            unregisterReceiver(appChangeReceiver)
        }
        if (chatTextReceiver != null) {
            unregisterReceiver(chatTextReceiver)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        Log.d(TAG, "onActivityResult: requestCode=$requestCode, resultCode=$resultCode, data=$data")
        if (requestCode == REQUEST_CODE) {
            val shouldStopAfterPermissionResult = deferredStopRequested
            deferredStopRequested = false
            var permissionGranted = false
            if (resultCode == Activity.RESULT_OK && data != null) {
                Log.d(TAG, "Media projection permission granted")
                try {
                    mediaProjection = projectionManager.getMediaProjection(resultCode, data)
                    Log.d(TAG, "MediaProjection obtained: ${mediaProjection != null}")
                    setupVirtualDisplay()
                    permissionGranted = true
                    clearNativeScanRecoveryFlag()
                } catch (e: Exception) {
                    Log.e(TAG, "Error setting up media projection: ${e.message}", e)
                }
            } else {
                Log.w(TAG, "Media projection permission denied or cancelled. ResultCode: $resultCode")
            }
            isProjectionPermissionInFlight = false
            if (shouldStopAfterPermissionResult && !permissionGranted) {
                Log.w(TAG, "Applying deferred stop request after projection permission result")
                stopProtectionServices()
            } else if (shouldStopAfterPermissionResult && permissionGranted) {
                Log.w(TAG, "Ignoring deferred stop request after successful projection grant")
            }
        }
    }

    private fun clearNativeScanRecoveryFlag() {
        try {
            val childId = getSharedPreferences(scanPrefsName, Context.MODE_PRIVATE)
                .getString(scanChildIdKey, null)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?: return

            FirebaseFirestore.getInstance()
                .collection("users")
                .document(childId)
                .collection("systemHealth")
                .document("nativeScanRecovery")
                .set(
                    mapOf(
                        "requiresRecovery" to false,
                        "reason" to "",
                        "updatedAt" to FieldValue.serverTimestamp(),
                    ),
                    com.google.firebase.firestore.SetOptions.merge(),
                )
        } catch (e: Exception) {
            Log.e(TAG, "clearNativeScanRecoveryFlag failed: ${e.message}", e)
        }
    }

    private fun stopProtectionServices() {
        setNativeScanEnabled(false)
        isProjectionPermissionInFlight = false
        try {
            val stopNativeIntent = Intent(this, NativeScanService::class.java).apply {
                action = NativeScanService.ACTION_STOP
            }
            startService(stopNativeIntent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request NativeScanService stop: ${e.message}", e)
        }

        val hasActiveProjection = mediaProjection != null || ProjectionSession.hasActiveProjection()
        if (!hasActiveProjection) {
            Log.w(TAG, "Skipping stopScreenCapture because no active projection session exists yet")
            return
        }

        stopScreenCapture()
        try {
            stopService(Intent(this, NativeScanService::class.java))
        } catch (_: Exception) {}
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        Log.d(TAG, "onRequestPermissionsResult: requestCode=$requestCode")
        
        if (requestCode == REQUEST_CODE_BACKGROUND_LOCATION) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "Background location permission granted")
            } else {
                Log.w(TAG, "Background location permission denied")
            }
        }
    }

    private fun dispatchNativeScanIntent(intent: Intent): Boolean {
        return try {
            val isRunning = NativeScanService.isScannerRuntimeRunning()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !isRunning) {
                startForegroundService(intent)
                Log.d(TAG, "Started NativeScanService via startForegroundService action=${intent.action}")
            } else {
                startService(intent)
                Log.d(TAG, "Dispatched NativeScanService via startService action=${intent.action} running=$isRunning")
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "dispatchNativeScanIntent failed action=${intent.action}: ${e.message}", e)
            false
        }
    }

    private fun setupVirtualDisplay() {
        Log.d(TAG, "setupVirtualDisplay called")
        try {
            val metrics = DisplayMetrics()
            windowManager.defaultDisplay.getMetrics(metrics)
            Log.d(TAG, "Display metrics: ${metrics.widthPixels}x${metrics.heightPixels}, dpi=${metrics.densityDpi}")

            try {
                virtualDisplay?.release()
            } catch (_: Exception) {
            }
            virtualDisplay = null
            try {
                imageReader?.close()
            } catch (_: Exception) {
            }
            imageReader = null

            val width = 480
            val height = 854
            Log.d(TAG, "Creating ImageReader: ${width}x${height}")

            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            Log.d(TAG, "ImageReader created: ${imageReader != null}")

            virtualDisplay = mediaProjection?.createVirtualDisplay(
                "ScreenCapture",
                width,
                height,
                metrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader?.surface,
                null,
                null
            )
            Log.d(TAG, "VirtualDisplay created: ${virtualDisplay != null}")
            ProjectionSession.configureProjection(
                projection = mediaProjection,
                display = virtualDisplay,
                reader = imageReader,
                cachePath = cacheDir.absolutePath,
                captureWidth = width,
                captureHeight = height,
                captureDensityDpi = metrics.densityDpi,
            )

            try {
                setNativeScanEnabled(true)
                val scanServiceIntent = Intent(this, NativeScanService::class.java).apply {
                    action = NativeScanService.ACTION_RESTART
                }
                dispatchNativeScanIntent(scanServiceIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start NativeScanService: ${e.message}", e)
            }
            
            // Give it a moment to start capturing
            Handler(Looper.getMainLooper()).postDelayed({
                Log.d(TAG, "VirtualDisplay should be ready now")
            }, 500)
        } catch (e: Exception) {
            Log.e(TAG, "Error in setupVirtualDisplay: ${e.message}", e)
        }
    }

    private fun performCapture(): String? {
        try {
            Log.d(TAG, "performCapture: Attempting to acquire image...")
            val image = imageReader?.acquireLatestImage()
            if (image == null) {
                Log.w(TAG, "performCapture: No image available from ImageReader")
                // Try acquireNextImage as fallback
                val nextImage = imageReader?.acquireNextImageNoThrowISE()
                if (nextImage == null) {
                    Log.w(TAG, "performCapture: acquireNextImage also returned null")
                    return null
                }
                return processImage(nextImage)
            }
            return processImage(image)
        } catch (e: Exception) {
            Log.e(TAG, "Error in performCapture: ${e.message}", e)
            return null
        }
    }
    
    private fun ImageReader.acquireNextImageNoThrowISE(): android.media.Image? {
        return try {
            acquireNextImage()
        } catch (e: IllegalStateException) {
            Log.w(TAG, "ISE when acquiring next image: ${e.message}")
            null
        }
    }
    
    private fun processImage(image: android.media.Image): String? {
        try {
            Log.d(TAG, "processImage: Image dimensions ${image.width}x${image.height}")
            val plane = image.planes[0]
            val buffer = plane.buffer
            val pixelStride = plane.pixelStride
            val rowStride = plane.rowStride
            val rowPadding = rowStride - pixelStride * image.width
            Log.d(TAG, "processImage: pixelStride=$pixelStride, rowStride=$rowStride, rowPadding=$rowPadding")

            val bitmap = Bitmap.createBitmap(
                image.width + rowPadding / pixelStride,
                image.height,
                Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)
            image.close()
            Log.d(TAG, "processImage: Bitmap created ${bitmap.width}x${bitmap.height}")

            val file = File(cacheDir, "scan_frame.jpg")
            FileOutputStream(file).use { out ->
                val compressed = bitmap.compress(Bitmap.CompressFormat.JPEG, 70, out)
                Log.d(TAG, "processImage: Bitmap compressed: $compressed, file size: ${file.length()} bytes")
            }
            bitmap.recycle()
            Log.d(TAG, "processImage: Success! File saved to: ${file.absolutePath}")
            return file.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Error processing image: ${e.message}", e)
            try {
                image.close()
            } catch (ignored: Exception) {}
            return null
        }
    }

    private fun stopScreenCapture() {
        val intent = Intent(this, MediaProjectionService::class.java)
        stopService(intent)
        virtualDisplay?.release()
        virtualDisplay = null
        mediaProjection?.stop()
        mediaProjection = null
        imageReader?.close()
        imageReader = null
        ProjectionSession.clear()
        toggleShield(false, "nsfw", null)
    }

    private fun saveNativeScanConfig(
        pornEnabled: Boolean,
        violenceEnabled: Boolean,
        scanIntervalSeconds: Int,
    ) {
        val anyScanEnabled = pornEnabled || violenceEnabled
        val sanitizedInterval = scanIntervalSeconds.coerceIn(1, 30)
        getSharedPreferences(scanPrefsName, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(scanPornKey, pornEnabled)
            .putBoolean(scanViolenceKey, violenceEnabled)
            .putInt(scanIntervalSecondsKey, sanitizedInterval)
            .putBoolean(scanEnabledKey, anyScanEnabled)
            .apply()
    }

    private fun saveNativeScanExclusions(packages: List<String>) {
        getSharedPreferences(scanPrefsName, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(scanExcludedKey, packages.filter { it.isNotBlank() }.toSet())
            .apply()
    }

    private fun saveNativeGroomingPackages(packages: List<String>) {
        getSharedPreferences(scanPrefsName, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(groomingEnabledPackagesKey, packages.filter { it.isNotBlank() }.toSet())
            .apply()
    }

    private fun saveNativeChildContext(childId: String?, parentId: String?) {
        val editor = getSharedPreferences(scanPrefsName, Context.MODE_PRIVATE).edit()
        if (!childId.isNullOrBlank()) {
            editor.putString(scanChildIdKey, childId)
        }
        if (!parentId.isNullOrBlank()) {
            editor.putString(scanParentIdKey, parentId)
        }
        editor.apply()
    }

    private fun setNativeScanEnabled(enabled: Boolean) {
        getSharedPreferences(scanPrefsName, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(scanEnabledKey, enabled)
            .apply()
    }

    private fun toggleShield(show: Boolean, type: String = "nsfw", imageBase64: String? = null) {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        Handler(Looper.getMainLooper()).post {
            if (show) {
                if (shieldIsHiding) {
                    pendingShieldShowType = type
                    pendingShieldShowImageBase64 = imageBase64
                    Log.d(TAG, "toggleShield: queued show while hiding for type=$type")
                    return@post
                }

                val now = System.currentTimeMillis()
                val bypassDismissCooldown = (type == "app_time_limit" || type == "screen_time" || type == "app_block")
                if (!bypassDismissCooldown && (now - lastShieldDismissedAtMillis) < 4000) {
                    Log.d(TAG, "toggleShield: suppressed by post-dismiss cooldown for type=$type")
                    return@post
                }

                if (shieldView == null) {
                    // Root FrameLayout for full screen overlay
                    val rootLayout = android.widget.FrameLayout(this).apply {
                        setBackgroundColor(Color.BLACK)
                        alpha = 0f
                    }

                    // Image View - full screen background
                    val imageView = android.widget.ImageView(this).apply {
                        layoutParams = android.widget.FrameLayout.LayoutParams(
                            android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
                            android.widget.FrameLayout.LayoutParams.MATCH_PARENT
                        )
                        scaleType = android.widget.ImageView.ScaleType.FIT_XY
                        
                        try {
                            Log.d(TAG, "Loading image for type: $type")
                            
                            // Get base64 image data  from the method call parameter
                            if (imageBase64 != null) {
                                Log.d(TAG, "Decoding base64 image (${imageBase64.length} chars)")
                                
                                // Decode base64 to bytes
                                val decodedBytes = android.util.Base64.decode(imageBase64, android.util.Base64.DEFAULT)
                                Log.d(TAG, "Decoded ${decodedBytes.size} bytes")
                                
                                if (type == "app_block") {
                                    // Try GifDrawable first for GIF
                                    try {
                                        val gifDrawable = GifDrawable(decodedBytes)
                                        setImageDrawable(gifDrawable)
                                        Log.d(TAG, "✓ GIF drawable created and set")
                                    } catch (gifError: Exception) {
                                        Log.w(TAG, "GifDrawable failed, trying as bitmap: ${gifError.message}")
                                        val bitmap = android.graphics.BitmapFactory.decodeByteArray(decodedBytes, 0, decodedBytes.size)
                                        if (bitmap != null) {
                                            setImageBitmap(bitmap)
                                            Log.d(TAG, "✓ GIF loaded as bitmap fallback: ${bitmap.width}x${bitmap.height}")
                                        } else {
                                            Log.e(TAG, "✗ Both GifDrawable and bitmap failed")
                                            setBackgroundColor(Color.BLACK)
                                        }
                                    }
                                } else {
                                    // Load PNG as bitmap
                                    val bitmap = android.graphics.BitmapFactory.decodeByteArray(decodedBytes, 0, decodedBytes.size)
                                    if (bitmap != null) {
                                        setImageBitmap(bitmap)
                                        Log.d(TAG, "✓ PNG loaded: ${bitmap.width}x${bitmap.height}")
                                    } else {
                                        Log.e(TAG, "✗ PNG bitmap is null")
                                        setBackgroundColor(Color.BLACK)
                                    }
                                }
                            } else {
                                val fallbackAssetCandidates = fallbackAssetCandidatesForType(type)
                                Log.d(TAG, "No base64 provided, loading fallback assets: $fallbackAssetCandidates")
                                val fallbackBitmap = loadFirstAvailableBitmapFromAssets(fallbackAssetCandidates)
                                if (fallbackBitmap != null) {
                                    setImageBitmap(fallbackBitmap)
                                    Log.d(TAG, "✓ Fallback asset loaded: ${fallbackBitmap.width}x${fallbackBitmap.height}")
                                } else {
                                    Log.e(TAG, "✗ Failed to load any fallback asset for type=$type")
                                    setBackgroundColor(Color.BLACK)
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "✗ Exception: ${e.javaClass.simpleName} - ${e.message}")
                            e.printStackTrace()
                            setBackgroundColor(Color.BLACK)
                        }
                    }

                    // Button container - positioned at bottom
                    val buttonContainer = android.widget.FrameLayout(this).apply {
                        layoutParams = android.widget.FrameLayout.LayoutParams(
                            android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
                            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
                            android.view.Gravity.BOTTOM
                        ).apply {
                            setMargins(0, 0, 0, 60)
                        }
                    }

                    // Text (only for app_block) - REMOVED - now showing full screen image only
                    
                    // Button (only for nsfw and app_block, not for screen_time)
                    if (type != "screen_time") {
                        val actionButton = android.widget.Button(this).apply {
                            text = "Exit To Home Screen"
                            setTextColor(Color.WHITE)
                            textSize = 18f  // Larger font
                            
                            // Try custom font from Flutter assets, fall back to system font
                            try {
                                typeface = Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/ComicNeueSansID.ttf")
                                Log.d(TAG, "Custom font loaded successfully")
                            } catch (e: Exception) {
                                Log.w(TAG, "Custom font not found, using system font: ${e.message}")
                                typeface = Typeface.SANS_SERIF
                            }
                            
                            setPadding(60, 30, 60, 30)  // Bigger button (left, top, right, bottom)
                            isClickable = true
                            isFocusable = true
                            
                            val drawable = android.graphics.drawable.GradientDrawable().apply {
                                setColor(Color.parseColor("#8ac1ff"))
                                cornerRadius = 24f
                            }
                            background = drawable
                            
                            layoutParams = android.widget.FrameLayout.LayoutParams(
                                android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
                                android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
                                android.view.Gravity.BOTTOM or android.view.Gravity.CENTER_HORIZONTAL
                            ).apply {
                                setMargins(40, 40, 40, 100)  // Move higher: increase bottom margin
                            }
                            
                            var isProcessingClick = false
                            
                            setOnClickListener {
                                // Prevent double-click race condition
                                if (isProcessingClick) {
                                    Log.d(TAG, "Button click already being processed, ignoring")
                                    return@setOnClickListener
                                }
                                isProcessingClick = true
                                
                                Log.d(TAG, "Button clicked - dismissing shield immediately")

                                lastShieldDismissedAtMillis = System.currentTimeMillis()
                                
                                // IMMEDIATELY remove shield first (synchronous) to clear state
                                toggleShield(false, type)
                                Log.d(TAG, "Shield removed immediately")
                                
                                // Then notify Dart and navigate in background
                                lifecycleScope.launch(Dispatchers.Main) {
                                    try {
                                        val dartMethod = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "com.childsafe.app/screen_capture")
                                        dartMethod.invokeMethod("shieldDismissed", null)
                                        Log.d(TAG, "Dart notified of dismissal")
                                        
                                        // Small delay for smooth transition
                                        kotlinx.coroutines.delay(50)
                                        
                                        // Navigate to home
                                        val startMain = Intent(Intent.ACTION_MAIN).apply {
                                            addCategory(Intent.CATEGORY_HOME)
                                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                                        }
                                        startActivity(startMain)
                                        Log.d(TAG, "Navigated to home")
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Error during navigation: ${e.message}", e)
                                        // Still try to go home even if Dart call fails
                                        val startMain = Intent(Intent.ACTION_MAIN).apply {
                                            addCategory(Intent.CATEGORY_HOME)
                                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                                        }
                                        startActivity(startMain)
                                    } finally {
                                        isProcessingClick = false
                                    }
                                }
                            }
                        }

                        buttonContainer.addView(actionButton)
                    }

                    // Add to root layout - image first (behind), button on top (if exists)
                    rootLayout.addView(imageView)
                    rootLayout.addView(buttonContainer)
                    shieldView = rootLayout

                    val params = WindowManager.LayoutParams(
                        WindowManager.LayoutParams.MATCH_PARENT,
                        WindowManager.LayoutParams.MATCH_PARENT,
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                        PixelFormat.TRANSLUCENT
                    )

                    try {
                        wm.addView(shieldView, params)
                        shieldIsHiding = false
                        pendingShieldShowType = null
                        pendingShieldShowImageBase64 = null
                        shieldView!!.animate()
                            .alpha(1f)
                            .setDuration(300)
                            .start()
                        Log.d(TAG, "Shield view added to window")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error adding shield view: ${e.message}", e)
                    }
                }
            } else {
                if (shieldView != null) {
                    shieldIsHiding = true
                    shieldView!!.animate()
                        .alpha(0f)
                        .setDuration(300)
                        .withEndAction {
                            try {
                                wm.removeView(shieldView)
                                Log.d(TAG, "Shield view removed")
                            } catch (e: Exception) {
                                Log.e(TAG, "Error removing shield view: ${e.message}")
                            }
                            shieldView = null
                            shieldIsHiding = false

                            val queuedType = pendingShieldShowType
                            val queuedBase64 = pendingShieldShowImageBase64
                            pendingShieldShowType = null
                            pendingShieldShowImageBase64 = null
                            if (queuedType != null) {
                                toggleShield(true, queuedType, queuedBase64)
                            }
                        }
                        .start()
                }
            }
        }
    }

    private fun fallbackAssetCandidatesForType(type: String): List<String> {
        val primary = when (type) {
            "weapon" -> "assets/images/noWeapons.png"
            "gore" -> "assets/images/noGore.jpg"
            "nsfw" -> "assets/images/noNSFW.png"
            "app_block" -> "assets/images/blockApp.png"
            "screen_time" -> "assets/images/screenTimeExceeded.png"
            "app_time_limit" -> "assets/images/appLimit.png"
            else -> "assets/images/noNSFW.png"
        }

        val candidates = mutableListOf(
            "flutter_assets/$primary",
            primary,
        )

        if (type == "app_time_limit") {
            candidates.add("flutter_assets/assets/images/blockApp.png")
            candidates.add("assets/images/blockApp.png")
        }

        return candidates
    }

    private fun loadFirstAvailableBitmapFromAssets(paths: List<String>): android.graphics.Bitmap? {
        for (path in paths) {
            try {
                assets.open(path).use { stream ->
                    val bitmap = android.graphics.BitmapFactory.decodeStream(stream)
                    if (bitmap != null) {
                        Log.d(TAG, "Asset loaded from path: $path")
                        return bitmap
                    }
                    Log.w(TAG, "Asset decoded as null from path: $path")
                }
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
            } catch (e: Exception) {
                openAppSettings()
            }
        }
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun requestUsageStatsPermission() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
        } catch (e: Exception) {
            openAppSettings()
        }
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
        }
    }

    private fun openBatteryBackgroundManagementSettings() {
        try {
            val intent = Intent(Intent.ACTION_POWER_USAGE_SUMMARY).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val fallbackIntent = Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(fallbackIntent)
            } catch (_: Exception) {
                openAppSettings()
            }
        }
    }

    private fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 200)
        }
    }

    private fun getForegroundAppFromUsageStats(): String? {
        try {
            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val time = System.currentTimeMillis()
            // Get usage stats for the last 5 seconds
            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                time - 5000,
                time
            )
            
            if (stats != null && stats.isNotEmpty()) {
                // Find the most recently used app
                var recentStats = stats[0]
                for (usageStats in stats) {
                    if (usageStats.lastTimeUsed > recentStats.lastTimeUsed) {
                        recentStats = usageStats
                    }
                }
                return recentStats.packageName
            }
        } catch (e: Exception) {
            // Usage stats not available or permission denied
        }
        return null
    }

    private fun getScreenTimeData(): Map<String, Any> {
        val prefs = getSharedPreferences("screen_time_prefs", Context.MODE_PRIVATE)
        val calendar = java.util.Calendar.getInstance()
        
        android.util.Log.d("MainActivity", "Getting screen time data from prefs")
        
        // Build 7-day history
        val last7Days = mutableListOf<Map<String, Any>>()
        var totalWeekMinutes = 0
        
        for (i in 6 downTo 0) {
            val dayCal = calendar.clone() as java.util.Calendar
            dayCal.add(java.util.Calendar.DAY_OF_MONTH, -i)
            
            val dayKey = String.format("%04d-%02d-%02d",
                dayCal.get(java.util.Calendar.YEAR),
                dayCal.get(java.util.Calendar.MONTH) + 1,
                dayCal.get(java.util.Calendar.DAY_OF_MONTH)
            )
            
            val dayMinutes = (prefs.getLong(dayKey, 0) / 60000).toInt()
            android.util.Log.d("MainActivity", "Day $dayKey: $dayMinutes minutes")
            totalWeekMinutes += dayMinutes
            
            last7Days.add(mapOf(
                "date" to dayKey,
                "minutes" to dayMinutes
            ))
        }
        
        // Today's screen time
        val todayKey = String.format("%04d-%02d-%02d",
            calendar.get(java.util.Calendar.YEAR),
            calendar.get(java.util.Calendar.MONTH) + 1,
            calendar.get(java.util.Calendar.DAY_OF_MONTH)
        )
        val totalToday = (prefs.getLong(todayKey, 0) / 60000).toInt()
        
        val result = mapOf(
            "last7Days" to last7Days,
            "dailyAverage" to (totalWeekMinutes / 7.0),
            "totalToday" to totalToday
        )
        
        android.util.Log.d("MainActivity", "Screen time data: $result")
        return result
    }

    private fun getAppUsageData(): Map<String, Any> {
        val prefs = getSharedPreferences("screen_time_prefs", Context.MODE_PRIVATE)
        val calendar = java.util.Calendar.getInstance()
        
        val todayKey = String.format("%04d-%02d-%02d",
            calendar.get(java.util.Calendar.YEAR),
            calendar.get(java.util.Calendar.MONTH) + 1,
            calendar.get(java.util.Calendar.DAY_OF_MONTH)
        )
        
        android.util.Log.d("MainActivity", "Getting app usage data for key: ${todayKey}_apps")
        
        val appsString = prefs.getString("${todayKey}_apps", "")
        android.util.Log.d("MainActivity", "Apps string from prefs: $appsString")
        
        val apps = mutableListOf<Map<String, Any>>()
        
        if (!appsString.isNullOrEmpty()) {
            val appEntries = appsString.split(";")
            android.util.Log.d("MainActivity", "Found ${appEntries.size} app entries")
            for (entry in appEntries) {
                val parts = entry.split(",")
                if (parts.size >= 2) {
                    val packageName = parts[0]
                    val totalTimeMs = parts[1].toLongOrNull() ?: 0
                    val weeklyTotalMs = if (parts.size >= 4) {
                        parts[3].toLongOrNull() ?: totalTimeMs
                    } else {
                        totalTimeMs
                    }
                    
                    android.util.Log.d("MainActivity", "Processing app: $packageName, time: ${totalTimeMs/60000} min")
                    
                    // Get app name from package manager
                    val appName = try {
                        val appInfo = packageManager.getApplicationInfo(packageName, 0)
                        packageManager.getApplicationLabel(appInfo).toString()
                    } catch (e: Exception) {
                        packageName
                    }
                    
                    apps.add(mapOf(
                        "packageName" to packageName,
                        "appName" to appName,
                        "minutesToday" to (totalTimeMs / 60000).toInt(),
                        "minutesYesterday" to 0, // TODO: Get yesterday's data
                        "weeklyAverage" to (weeklyTotalMs / 60000 / 7.0),
                        "weeklyTotalMinutes" to (weeklyTotalMs / 60000).toInt(),
                    ))
                }
            }
        }
        
        val result = mapOf("apps" to apps)
        android.util.Log.d("MainActivity", "App usage data: ${apps.size} apps")
        return result
    }

    private fun getTodayUsageSecondsForPackage(targetPackageName: String): Int {
        return try {
            val now = System.currentTimeMillis()
            val todayStart = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, 0)
                set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
            }.timeInMillis

            val totalMs = collectUsageByPackageFromEvents(todayStart, now)[targetPackageName]?.totalMs ?: 0L

            (totalMs / 1000L).toInt().coerceAtLeast(0)
        } catch (e: Exception) {
            Log.w(TAG, "getTodayUsageSecondsForPackage failed for $targetPackageName: ${e.message}")
            0
        }
    }

    private fun getTodayTotalUsageSeconds(): Int {
        return try {
            val now = System.currentTimeMillis()
            val todayStart = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, 0)
                set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
            }.timeInMillis

            val totalMs = collectUsageByPackageFromEvents(todayStart, now)
                .values
                .sumOf { it.totalMs }

            (totalMs / 1000L).toInt().coerceAtLeast(0)
        } catch (e: Exception) {
            Log.w(TAG, "getTodayTotalUsageSeconds failed: ${e.message}")
            0
        }
    }

    private fun collectUsageByPackageFromEvents(
        startMs: Long,
        endMs: Long,
    ): Map<String, UsageWindowStats> {
        if (endMs <= startMs) {
            return emptyMap()
        }

        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
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

    data class UsageWindowStats(
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

    private fun saveBlockedPackages(packages: List<String>) {
        try {
            val sanitized = packages.filter { it.isNotBlank() }.toSet()
            getSharedPreferences(blockedPrefsName, Context.MODE_PRIVATE)
                .edit()
                .putStringSet(blockedPackagesKey, sanitized)
                .apply()
            Log.d(TAG, "Saved ${sanitized.size} blocked packages for native enforcement")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save blocked packages: ${e.message}", e)
        }
    }
}
