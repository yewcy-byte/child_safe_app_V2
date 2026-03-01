package com.example.child_safe_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityEvent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.auth.FirebaseAuth
import android.app.NotificationChannel
import android.app.NotificationManager
import java.util.LinkedHashSet

class ScreenMonitoringService : AccessibilityService() {
    companion object {
        private const val LOG_TAG = "ScreenMonitoringService"
        private const val BROADCAST_ACTION = "com.childsafe.app.APP_CHANGED"
        private const val CHAT_TEXT_BROADCAST_ACTION = "com.childsafe.app.CHAT_TEXT_CAPTURED"
        private const val EXTRA_PACKAGE_NAME = "packageName"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_MESSAGE_ID = "messageId"
        private const val BLOCKED_PREFS_NAME = "childsafe_blocking"
        private const val BLOCKED_PACKAGES_KEY = "blocked_packages"
        private const val GROOMING_ENABLED_PACKAGES_KEY = "grooming_enabled_packages"
        private const val SCAN_CHILD_ID_KEY = "scan_child_id"
        private const val SCAN_PARENT_ID_KEY = "scan_parent_id"
        private const val GROOMING_ALERT_CHANNEL_ID = "grooming_alerts_channel"
        private const val GROOMING_DETECTION_COOLDOWN_MS = 15_000L
        private const val BLOCK_SCREEN_DEBOUNCE_MS = 1200L

        private val CHAT_PACKAGES = setOf(
            "com.whatsapp",
            "com.whatsapp.w4b",
            "com.instagram.android",
            "com.facebook.orca",
            "org.telegram.messenger",
            "com.snapchat.android",
        )

        private val GROOMING_KEYWORDS = setOf(
            "nude",
            "nudes",
            "naked",
            "sexy",
            "sex",
        )
    }

    private var currentPackage: String? = null
    private var lastBlockedLaunchPackage: String? = null
    private var lastBlockedLaunchAtMillis: Long = 0L
    private val recentScannedMessageIds = LinkedHashSet<String>()
    private val lastGroomingDetectionAtByPackage = mutableMapOf<String, Long>()
    private var groomingAppsListener: ListenerRegistration? = null
    private var groomingAppsListenerParentId: String? = null
    private var groomingAppsListenerChildId: String? = null
    @Volatile
    private var groomingEnabledPackagesCache: Set<String> = emptySet()

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val packageName = event.packageName?.toString()
            
            // Filter out the ChildSafe app itself to prevent flickering when shield shows
            if (packageName == "com.example.child_safe_app") {
                Log.d(LOG_TAG, "Ignoring app change to ChildSafe app itself")
                return
            }
            
            if (packageName != null && packageName != currentPackage) {
                currentPackage = packageName
                Log.w(LOG_TAG, "App changed to: $packageName - triggering native scan")

                if (CHAT_PACKAGES.contains(packageName)) {
                    Handler(Looper.getMainLooper()).postDelayed({
                        scrapeAndBroadcastChatText(packageName)
                    }, 250)
                }

                val blocked = isBlockedPackage(packageName)

                if (blocked) {
                    enforceBlock(packageName)
                    notifyAppChange(packageName)
                    return
                }

                try {
                    val scanIntent = Intent(this, NativeScanService::class.java).apply {
                        action = NativeScanService.ACTION_SCAN
                        putExtra(NativeScanService.EXTRA_PACKAGE, packageName)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(scanIntent)
                        Log.w(LOG_TAG, "Started NativeScanService via startForegroundService for $packageName")
                    } else {
                        startService(scanIntent)
                        Log.w(LOG_TAG, "Started NativeScanService via startService for $packageName")
                    }
                } catch (e: Exception) {
                    Log.e(LOG_TAG, "Failed to trigger background scan: ${e.message}", e)
                }

                notifyAppChange(packageName)
            }
        }

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            val packageName = event.packageName?.toString() ?: return
            if (!CHAT_PACKAGES.contains(packageName)) {
                return
            }

            scrapeAndBroadcastChatText(packageName)
        }
    }

    override fun onInterrupt() {
        Log.d(LOG_TAG, "Service interrupted")
    }

    override fun onServiceConnected() {
        Log.d(LOG_TAG, "Accessibility Service connected")

        ensureGroomingAppsListener()

        try {
            val restartIntent = Intent(this, NativeScanService::class.java).apply {
                action = NativeScanService.ACTION_RESTART
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(restartIntent)
            } else {
                startService(restartIntent)
            }
            Log.d(LOG_TAG, "Requested NativeScanService restart from accessibility connection")
        } catch (e: Exception) {
            Log.e(LOG_TAG, "Failed to request NativeScanService restart: ${e.message}", e)
        }
        
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_REQUEST_ENHANCED_WEB_ACCESSIBILITY
            notificationTimeout = 100
        }
        
        serviceInfo = info
    }

    override fun onDestroy() {
        groomingAppsListener?.remove()
        groomingAppsListener = null
        groomingAppsListenerParentId = null
        groomingAppsListenerChildId = null
        super.onDestroy()
    }

    private fun ensureGroomingAppsListener() {
        val prefs = getSharedPreferences(BLOCKED_PREFS_NAME, Context.MODE_PRIVATE)
        val parentId = prefs
            .getString(SCAN_PARENT_ID_KEY, null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        val childId = resolveChildIdForLogging()

        if (parentId.isNullOrBlank() || childId.isNullOrBlank()) {
            groomingAppsListener?.remove()
            groomingAppsListener = null
            groomingAppsListenerParentId = null
            groomingAppsListenerChildId = null
            return
        }

        if (
            groomingAppsListener != null &&
            groomingAppsListenerParentId == parentId &&
            groomingAppsListenerChildId == childId
        ) {
            return
        }

        groomingAppsListener?.remove()
        groomingAppsListener = null
        groomingAppsListenerParentId = parentId
        groomingAppsListenerChildId = childId

        groomingAppsListener = FirebaseFirestore.getInstance()
            .collection("users")
            .document(parentId)
            .collection("children")
            .document(childId)
            .collection("groomingDetectionApps")
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.e(LOG_TAG, "ensureGroomingAppsListener error: ${error.message}", error)
                    return@addSnapshotListener
                }

                val enabledPackages = snapshot?.documents
                    ?.mapNotNull { doc ->
                        val packageName = doc.getString("packageName")
                            ?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: doc.id.trim().takeIf { it.isNotEmpty() }
                            ?: return@mapNotNull null
                        val enabled = doc.getBoolean("enabled") ?: true
                        if (enabled) packageName else null
                    }
                    ?.toSet()
                    ?: emptySet()

                groomingEnabledPackagesCache = enabledPackages
                prefs.edit()
                    .putStringSet(GROOMING_ENABLED_PACKAGES_KEY, enabledPackages)
                    .apply()

                Log.d(
                    LOG_TAG,
                    "ensureGroomingAppsListener: synced ${enabledPackages.size} enabled grooming packages",
                )
            }
    }

    private fun notifyAppChange(packageName: String) {
        Log.d(LOG_TAG, "notifyAppChange: Preparing to broadcast app change for $packageName")
        val intent = Intent(BROADCAST_ACTION).apply {
            putExtra(EXTRA_PACKAGE_NAME, packageName)
        }
        sendBroadcast(intent)
        Log.d(LOG_TAG, "notifyAppChange: Broadcast sent successfully for $packageName")
    }

    private fun scrapeAndBroadcastChatText(packageName: String) {
        val root = rootInActiveWindow ?: return
        val candidates = mutableListOf<String>()
        collectChatTexts(root, candidates)
        if (candidates.isEmpty()) {
            return
        }

        val trimmedCandidates = candidates
            .asSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toList()

        if (trimmedCandidates.isEmpty()) {
            return
        }

        val keywordCandidate = trimmedCandidates.firstOrNull { candidate ->
            containsGroomingKeyword(candidate)
        }

        val selectedText = keywordCandidate ?: trimmedCandidates
            .asSequence()
            .filter { it.length >= 8 }
            .maxByOrNull { it.length }
            ?: trimmedCandidates.maxByOrNull { it.length }
            ?: return

        val messageId = "$packageName:${selectedText.hashCode()}"
        if (isDuplicateMessageId(messageId)) {
            return
        }

        maybeHandleNativeGroomingDetection(
            packageName = packageName,
            text = selectedText,
            messageId = messageId,
        )

        val intent = Intent(CHAT_TEXT_BROADCAST_ACTION).apply {
            putExtra(EXTRA_PACKAGE_NAME, packageName)
            putExtra(EXTRA_TEXT, selectedText)
            putExtra(EXTRA_MESSAGE_ID, messageId)
        }
        sendBroadcast(intent)
        Log.d(LOG_TAG, "scrapeAndBroadcastChatText: emitted chat text for $packageName")
    }

    private fun collectChatTexts(node: AccessibilityNodeInfo?, out: MutableList<String>) {
        if (node == null) {
            return
        }

        val className = node.className?.toString() ?: ""
        val viewId = node.viewIdResourceName ?: ""
        val nodeText = node.text?.toString()?.trim() ?: ""
        val contentDescription = node.contentDescription?.toString()?.trim() ?: ""

        val looksLikeChatNode = viewId.contains("message", ignoreCase = true) ||
            viewId.contains("chat", ignoreCase = true) ||
            viewId.contains("conversation", ignoreCase = true) ||
            viewId.contains("row", ignoreCase = true) ||
            className.contains("TextView", ignoreCase = true)

        if (looksLikeChatNode) {
            if (nodeText.isNotEmpty()) {
                out.add(nodeText)
            }
            if (contentDescription.isNotEmpty()) {
                out.add(contentDescription)
            }
        }

        for (i in 0 until node.childCount) {
            collectChatTexts(node.getChild(i), out)
        }
    }

    private fun maybeHandleNativeGroomingDetection(
        packageName: String,
        text: String,
        messageId: String,
    ) {
        if (!isGroomingPackageEnabled(packageName)) {
            return
        }

        if (!containsGroomingKeyword(text)) {
            return
        }

        if (isInGroomingCooldown(packageName)) {
            return
        }

        markGroomingDetectionNow(packageName)
        showGroomingLocalNotification(
            title = "Child grooming risk detected",
            body = "Potential grooming content found in $packageName. Please review child activity.",
        )
        logNativeGroomingDetection(packageName = packageName, messageId = messageId)
    }

    private fun isGroomingPackageEnabled(packageName: String): Boolean {
        return try {
            val cache = groomingEnabledPackagesCache
            if (cache.isNotEmpty()) {
                return cache.contains(packageName)
            }

            val packages = getSharedPreferences(BLOCKED_PREFS_NAME, Context.MODE_PRIVATE)
                .getStringSet(GROOMING_ENABLED_PACKAGES_KEY, emptySet())
                ?: emptySet()
            groomingEnabledPackagesCache = packages
            packages.contains(packageName)
        } catch (e: Exception) {
            Log.e(LOG_TAG, "isGroomingPackageEnabled error: ${e.message}", e)
            false
        }
    }

    private fun containsGroomingKeyword(messageText: String): Boolean {
        val normalized = messageText
            .lowercase()
            .replace(Regex("[^a-z0-9\\s]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()

        if (normalized.isEmpty()) {
            return false
        }

        val words = normalized.split(' ').filter { it.isNotBlank() }.toSet()
        return GROOMING_KEYWORDS.any { words.contains(it) }
    }

    private fun isInGroomingCooldown(packageName: String): Boolean {
        val lastAt = lastGroomingDetectionAtByPackage[packageName] ?: return false
        return (System.currentTimeMillis() - lastAt) < GROOMING_DETECTION_COOLDOWN_MS
    }

    private fun markGroomingDetectionNow(packageName: String) {
        lastGroomingDetectionAtByPackage[packageName] = System.currentTimeMillis()
    }

    private fun showGroomingLocalNotification(title: String, body: String) {
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    GROOMING_ALERT_CHANNEL_ID,
                    "Child Grooming Alerts",
                    NotificationManager.IMPORTANCE_HIGH,
                )
                manager.createNotificationChannel(channel)
            }

            val notification = NotificationCompat.Builder(this, GROOMING_ALERT_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_notify_error)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()

            NotificationManagerCompat.from(this)
                .notify((SystemClock.elapsedRealtime() % Int.MAX_VALUE).toInt(), notification)
        } catch (e: Exception) {
            Log.e(LOG_TAG, "showGroomingLocalNotification failed: ${e.message}", e)
        }
    }

    private fun logNativeGroomingDetection(packageName: String, messageId: String) {
        val childId = resolveChildIdForLogging() ?: return

        val payload = mapOf(
            "packageName" to packageName,
            "appName" to packageName,
            "detectionType" to "grooming",
            "confidenceScore" to 1.0,
            "timestamp" to FieldValue.serverTimestamp(),
            "metadata" to mapOf(
                "source" to "accessibility_native_keyword",
                "messageId" to messageId,
            ),
        )

        FirebaseFirestore.getInstance()
            .collection("users")
            .document(childId)
            .collection("detections")
            .add(payload)
            .addOnFailureListener { e ->
                Log.e(LOG_TAG, "logNativeGroomingDetection failed: ${e.message}", e)
            }
    }

    private fun resolveChildIdForLogging(): String? {
        val prefs = getSharedPreferences(BLOCKED_PREFS_NAME, Context.MODE_PRIVATE)
        val fromPrefs = try {
            prefs
                .getString(SCAN_CHILD_ID_KEY, null)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        } catch (e: Exception) {
            Log.e(LOG_TAG, "resolveChildIdForLogging prefs read failed: ${e.message}", e)
            null
        }
        if (!fromPrefs.isNullOrBlank()) {
            return fromPrefs
        }

        val fromAuth = try {
            FirebaseAuth.getInstance().currentUser?.uid?.trim()?.takeIf { it.isNotEmpty() }
        } catch (e: Exception) {
            Log.e(LOG_TAG, "resolveChildIdForLogging auth fallback failed: ${e.message}", e)
            null
        }

        if (!fromAuth.isNullOrBlank()) {
            prefs.edit().putString(SCAN_CHILD_ID_KEY, fromAuth).apply()
        }

        return fromAuth
    }

    private fun isDuplicateMessageId(messageId: String): Boolean {
        if (recentScannedMessageIds.contains(messageId)) {
            return true
        }

        recentScannedMessageIds.add(messageId)
        while (recentScannedMessageIds.size > 10) {
            val iterator = recentScannedMessageIds.iterator()
            if (iterator.hasNext()) {
                iterator.next()
                iterator.remove()
            }
        }

        return false
    }

    private fun isBlockedPackage(packageName: String): Boolean {
        return try {
            val blocked = getSharedPreferences(BLOCKED_PREFS_NAME, Context.MODE_PRIVATE)
                .getStringSet(BLOCKED_PACKAGES_KEY, emptySet())
                ?: emptySet()
            blocked.contains(packageName)
        } catch (e: Exception) {
            Log.e(LOG_TAG, "isBlockedPackage error: ${e.message}", e)
            false
        }
    }

    private fun enforceBlock(packageName: String) {
        val now = System.currentTimeMillis()
        if (
            lastBlockedLaunchPackage == packageName &&
            (now - lastBlockedLaunchAtMillis) < BLOCK_SCREEN_DEBOUNCE_MS
        ) {
            Log.d(LOG_TAG, "enforceBlock: Debounced duplicate launch for $packageName")
            return
        }

        lastBlockedLaunchPackage = packageName
        lastBlockedLaunchAtMillis = now

        try {
            val blockIntent = Intent(this, BlockedAppActivity::class.java).apply {
                putExtra(EXTRA_PACKAGE_NAME, packageName)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            startActivity(blockIntent)
            Log.d(LOG_TAG, "enforceBlock: Opened block screen for $packageName")
        } catch (e: Exception) {
            Log.e(LOG_TAG, "enforceBlock error: ${e.message}", e)
        }
    }
}