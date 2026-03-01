// filepath: d:\kitaHackFlutter\child_safe_app\lib\services\accessibility_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service layer for accessibility monitoring
/// Follows AGENTS.MD: No UI logic, proper error handling
class AccessibilityService {
  static const _channel = MethodChannel('com.example.child_safe_app/accessibility');

  /// Check if accessibility service is enabled
  /// Returns false on any error (fail gracefully)
  Future<bool> isAccessibilityEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking accessibility status: $e');
      return false;
    }
  }

  /// Open accessibility settings
  /// Does not throw - handles errors internally
  Future<bool> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
      return true;
    } catch (e) {
      debugPrint('Error opening accessibility settings: $e');
      return false;
    }
  }

  /// Start monitoring app changes
  /// Must be called after accessibility is enabled
  Future<bool> startMonitoring() async {
    try {
      await _channel.invokeMethod('startMonitoring');
      return true;
    } catch (e) {
      debugPrint('Error starting monitoring: $e');
      return false;
    }
  }

  /// Get currently detected app package name
  Future<String?> getDetectedApp() async {
    try {
      return await _channel.invokeMethod<String>('getDetectedApp');
    } catch (e) {
      debugPrint('Error getting detected app: $e');
      return null;
    }
  }

  /// Stop monitoring (cleanup)
  Future<void> stopMonitoring() async {
    try {
      await _channel.invokeMethod('stopMonitoring');
    } catch (e) {
      debugPrint('Error stopping monitoring: $e');
    }
  }
}