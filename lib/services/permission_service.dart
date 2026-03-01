import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;

enum PermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  unknown,
}

class PermissionState {
  final PermissionStatus overlay;
  final PermissionStatus usageStats;
  final PermissionStatus notifications;
  final PermissionStatus accessibility;
  final DateTime lastChecked;

  PermissionState({
    required this.overlay,
    required this.usageStats,
    required this.notifications,
    required this.accessibility,
    required this.lastChecked,
  });

  bool get allGranted =>
      overlay == PermissionStatus.granted &&
      usageStats == PermissionStatus.granted &&
      notifications == PermissionStatus.granted &&
      accessibility == PermissionStatus.granted;

  int get grantedCount {
    int count = 0;
    if (overlay == PermissionStatus.granted) count++;
    if (usageStats == PermissionStatus.granted) count++;
    if (notifications == PermissionStatus.granted) count++;
    if (accessibility == PermissionStatus.granted) count++;
    return count;
  }

  int get totalRequired => 4;

  factory PermissionState.unknown() {
    return PermissionState(
      overlay: PermissionStatus.unknown,
      usageStats: PermissionStatus.unknown,
      notifications: PermissionStatus.unknown,
      accessibility: PermissionStatus.unknown,
      lastChecked: DateTime.now(),
    );
  }

  PermissionState copyWith({
    PermissionStatus? overlay,
    PermissionStatus? usageStats,
    PermissionStatus? notifications,
    PermissionStatus? accessibility,
  }) {
    return PermissionState(
      overlay: overlay ?? this.overlay,
      usageStats: usageStats ?? this.usageStats,
      notifications: notifications ?? this.notifications,
      accessibility: accessibility ?? this.accessibility,
      lastChecked: DateTime.now(),
    );
  }
}

class PermissionService {
  static const MethodChannel _channel = MethodChannel('com.childsafe.app/screen_capture');
  
  static final _permissionStateController = StreamController<PermissionState>.broadcast();
  static PermissionState _currentState = PermissionState.unknown();

  static Stream<PermissionState> get permissionStateStream => _permissionStateController.stream;
  static PermissionState get currentState => _currentState;

  static void initialize() {
    checkAllPermissions();
  }

  static Future<PermissionState> checkAllPermissions() async {
    if (!Platform.isAndroid) {
      _currentState = PermissionState(
        overlay: PermissionStatus.granted,
        usageStats: PermissionStatus.granted,
        notifications: PermissionStatus.granted,
        accessibility: PermissionStatus.granted,
        lastChecked: DateTime.now(),
      );
      _permissionStateController.add(_currentState);
      return _currentState;
    }

    try {
      // Check native permissions (overlay and usage stats)
      final results = await _channel.invokeMethod<Map>('checkAllPermissions');
      final accessibilityEnabled =
          await _channel.invokeMethod<bool>('checkAccessibilityService');
      
      // Check notification permission using permission_handler (more reliable)
      final notificationStatus = await permission_handler.Permission.notification.status;
      final notificationGranted = notificationStatus.isGranted;
      
      _currentState = PermissionState(
        overlay: _parseBool(results?['overlay']) ? PermissionStatus.granted : PermissionStatus.denied,
        usageStats: _parseBool(results?['usageStats']) ? PermissionStatus.granted : PermissionStatus.denied,
        notifications: notificationGranted ? PermissionStatus.granted : PermissionStatus.denied,
        accessibility: accessibilityEnabled == true
            ? PermissionStatus.granted
            : PermissionStatus.denied,
        lastChecked: DateTime.now(),
      );
    } catch (e) {
      _currentState = PermissionState.unknown();
    }

    _permissionStateController.add(_currentState);
    return _currentState;
  }

  static bool _parseBool(dynamic value) {
    if (value == true) return true;
    if (value == false) return false;
    if (value is int) return value == 1;
    return false;
  }

  static Future<bool> requestOverlayPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      await _channel.invokeMethod('requestOverlayPermission');
      // Wait a bit for user to grant, then check
      await Future.delayed(const Duration(seconds: 1));
      await checkAllPermissions();
      return _currentState.overlay == PermissionStatus.granted;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> requestUsageStatsPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      await _channel.invokeMethod('requestUsageStatsPermission');
      // Don't auto-check - user needs to manually enable in settings
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      // Use permission_handler for requesting notification permission
      final status = await permission_handler.Permission.notification.request();
      await checkAllPermissions();
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> requestAccessibilityPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> openAppSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openAppSettings');
    } on MissingPluginException {
      await permission_handler.openAppSettings();
    } catch (_) {
      await permission_handler.openAppSettings();
    }
  }

  static Future<void> openBatteryBackgroundManagementSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openBatteryBackgroundManagementSettings');
    } on MissingPluginException {
      await permission_handler.openAppSettings();
    } catch (_) {
      await permission_handler.openAppSettings();
    }
  }

  static void dispose() {
    _permissionStateController.close();
  }
}
