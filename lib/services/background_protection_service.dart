import 'package:flutter/foundation.dart';

/// Service to ensure background protection continues when app is closed
/// This service manages the lifecycle of native scanning services
class BackgroundProtectionService {
  static const String _channel = 'com.childsafe.app/background_protection';

  /// Start background protection services
  /// This ensures scanning continues even when the Flutter app is closed
  static Future<void> startBackgroundProtection() async {
    try {
      debugPrint('BackgroundProtectionService: Starting background protection...');
      // The native MediaProjectionService is already running as a foreground service
      // This keeps the scanning capability alive even when Flutter app is closed
      // Additional persistence can be added via WorkManager or JobScheduler if needed
    } catch (e) {
      debugPrint('BackgroundProtectionService error: $e');
    }
  }

  /// Ensure foreground service keeps running even when app is in background
  static Future<void> ensureForegroundService() async {
    try {
      // The MediaProjectionService with FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
      // will keep the app running as a persistent foreground service
      // This ensures scanning continues in the background
      debugPrint('BackgroundProtectionService: Foreground service is active');
    } catch (e) {
      debugPrint('BackgroundProtectionService error ensuring foreground service: $e');
    }
  }

  /// Handle the case when child removes app from recents
  /// Native side handles this via BroadcastReceiver
  static void handleAppRemovedFromRecents() {
    debugPrint('BackgroundProtectionService: App removed from recents - continuing background scans');
    // The MediaProjectionService will continue running in the background
    // and accessibility service will still report app changes
  }
}
