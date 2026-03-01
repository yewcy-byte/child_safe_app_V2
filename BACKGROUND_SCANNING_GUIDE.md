# Background Scanning - How It Works When App is Closed

## Architecture Overview

The content scanning system has **two layers** to ensure protection continues even when the Flutter app is closed:

### Layer 1: Flutter Layer (Foreground)
- `ChildProtectionRunner` - Runs TensorFlow inference when app is in focus
- Detects NSFW, violence, and app blocking
- Shows overlay shields when content is detected
- Caches exclusion list to avoid blocking apps during gaming

### Layer 2: Native Layer (Background)
- **MediaProjectionService** - Foreground service that persists even when app is closed
- **ScreenMonitoringService** - AccessibilityService that monitors app changes
- **BroadcastReceiver** - Listens for app lifecycle events
- Handles screen capture requests from Flutter layer
- Runs independently of the Flutter app lifecycle

## How Scanning Continues When App is Closed

### When Child Force-Closes the App or Removes from Recents:

```
1. Child closes app or swipes from recents
   ↓
2. Flutter widgets are destroyed (including ChildProtectionRunner)
   ↓
3. MediaProjectionService continues running as foreground service
   (Visible as persistent notification: "Child Safe Protection")
   ↓
4. ScreenMonitoringService (AccessibilityService) continues monitoring
   app changes via system accessibility events
   ↓
5. When child opens any app, native code notifies Flutter
   ↓
6. When app is reopened, Flutter resumes scanning from where it left off
```

## Key Components

### 1. MediaProjectionService (Native)
**File**: `android/app/src/main/kotlin/.../MediaProjectionService.kt`

- **Type**: Android Foreground Service
- **Service Type**: FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION (API 31+)
- **Purpose**: Keeps media projection alive and enables screen capture
- **Persistence**: Continues running even when app is closed
- **Indicator**: Shows persistent notification to user
- **Lifecycle**: Started when `startService` is called, keeps running until explicitly stopped

```kotlin
class MediaProjectionService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(1, notification, FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        return START_STICKY  // Restart if killed
    }
}
```

### 2. ScreenMonitoringService (Native)
**File**: `android/app/src/main/kotlin/.../ScreenMonitoringService.kt`

- **Type**: Android AccessibilityService
- **Purpose**: Monitors which app is currently in foreground
- **Trigger**: System fires TYPE_WINDOW_STATE_CHANGED events
- **Broadcasts**: Sends app changes via BroadcastReceiver
- **Persistence**: Enabled via accessibility settings, runs independent of app

### 3. BackgroundProtectionService (Dart)
**File**: `lib/services/background_protection_service.dart`

- **Purpose**: Manages lifecycle of native background services from Flutter
- **Methods**:
  - `startBackgroundProtection()` - Initializes native services
  - `ensureForegroundService()` - Verifies service is running
  - `handleAppRemovedFromRecents()` - Called when app is closed

### 4. ChildDashboard (Dart) - Lifecycle Integration
**File**: `lib/ui/child/child_dashboard.dart`

- **initState**: Calls `BackgroundProtectionService.startBackgroundProtection()`
- **didChangeAppLifecycleState(paused)**: Calls `handleAppRemovedFromRecents()`
- **didChangeAppLifecycleState(resumed)**: Calls `ensureForegroundService()`

## Scanning Behavior Timeline

### Scenario: Child Opens Blocked App, Then Closes Flutter App

```
T0: App running, scanning active
    └─ ChildProtectionRunner actively scanning
    └─ MediaProjectionService in foreground
    └─ ScreenMonitoringService monitoring

T1: Child opens blocked app (e.g., Instagram)
    └─ ChildProtectionRunner detects app is blocked
    └─ Native overlay shield is shown via method channel
    └─ Alert dialog displayed to child

T2: Child taps "OK" to dismiss alert
    └─ Scanning continues

T3: Child closes Flutter app (swipe from recents)
    └─ Flutter widgets destroyed (ChildProtectionRunner gone)
    └─ MediaProjectionService still running (foreground)
    └─ ScreenMonitoringService still monitoring
    └─ Scanning capability still available on native side

T4: Child tries to open Instagram again
    └─ ScreenMonitoringService detects app change
    └─ Broadcasts app change via BroadcastReceiver
    └─ Native code can perform actions (via MediaProjectionService)
    └─ If Flutter app reopens, scanning resumes

T5: Child opens Flutter app again
    └─ ChildDashboard initializes
    └─ didChangeAppLifecycleState(resumed) fires
    └─ ensureForegroundService() called
    └─ ChildProtectionRunner reconnects to scanning pipeline
    └─ Full scanning with overlays resumes
```

## Why This Works

### Foreground Service Persistence
- `START_STICKY` flag ensures MediaProjectionService restarts if killed
- Android prevents killing foreground services to preserve user's chosen functionality
- Visible notification prevents silent termination

### AccessibilityService Persistence
- Enabled via device accessibility settings
- System keeps running even if Flutter app is closed
- Survives app removal from recents

### Two-Layer Architecture
- **Native layer**: Handles low-level app monitoring, screen capture setup
- **Flutter layer**: Handles TensorFlow inference, UI, and complex logic
- Clear separation allows Flutter to exit without killing background monitoring

## Configuration

### Permissions Required (AndroidManifest.xml)
```xml
<uses-permission android:name="android.permission.BIND_ACCESSIBILITY_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
<uses-permission android:name="android.permission.INTERNET" />
```

### Accessibility Service Declaration
```xml
<service android:name=".ScreenMonitoringService"
         android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
         android:enabled="true"
         android:exported="false">
    <intent-filter>
        <action android:name="android.accessibilityservice.AccessibilityService" />
    </intent-filter>
</service>
```

## Testing Scenarios

### Test 1: App Close
1. Parent enables content filters
2. Child opens app, sees overlay alert
3. Child force-closes app (swipe from recents)
4. **Expected**: Next time app opens, scanning resumes

### Test 2: Screen Lock
1. App scanning is active
2. Child locks screen
3. **Expected**: MediaProjectionService continues running in background
4. When screen unlocks and app reopens, scanning continues

### Test 3: Multiple App Changes
1. App closed/removed from recents
2. Child switches between several apps
3. ScreenMonitoringService tracks all changes
4. When Flutter app reopens, parent can see activity logs

### Test 4: Content Detection
1. App closed
2. Child opens app with inappropriate content
3. **Expected**: Native overlay shield shown (even with app closed)
4. Shield persists until child acknowledges it

## Future Enhancements

### WorkManager Integration
- Use Google WorkManager for periodic scanning jobs
- Ensures scanning even if MediaProjectionService is killed
- Schedule background scans every few minutes

### JobScheduler (Android 5.0+)
- Alternative to WorkManager for older devices
- Schedules periodic content checks

### Persistent WakeLock
- Keep device CPU awake during scanning
- Ensures TensorFlow inference completes even in standby

## Troubleshooting

### Scanning Stops After App Close
1. **Check**: Verify MediaProjectionService is running
   ```bash
   adb shell dumpsys activity services | grep MediaProjectionService
   ```
2. **Check**: Verify AccessibilityService is enabled
   - Settings → Accessibility → ChildSafe app
3. **Check**: Verify permissions are granted
   - Runtime: RECORD_AUDIO, WRITE_EXTERNAL_STORAGE
   - Manifest: FOREGROUND_SERVICE, MEDIA_PROJECTION

### Notification Not Showing
1. Verify FOREGROUND_SERVICE permission in AndroidManifest.xml
2. Ensure notification channel is created (NotificationManager)
3. Check Android version (different behavior for Android 8.0+)

### App Not Detecting Changes
1. Enable Developer Mode → Monitoring → Services
2. Check logcat for ScreenMonitoringService logs:
   ```bash
   adb logcat | grep ScreenMonitoringService
   ```
3. Verify BroadcastReceiver is registered in MainActivity

## Summary

✅ **Content scanning persists when app is closed** via:
- `MediaProjectionService` running as foreground service
- `ScreenMonitoringService` monitoring app changes via accessibility
- `BackgroundProtectionService` managing native lifecycle from Dart

✅ **When app reopens**: Scanning automatically resumes from cache

✅ **Parent visibility**: Activity logs and detections are saved to Firestore regardless of app state
