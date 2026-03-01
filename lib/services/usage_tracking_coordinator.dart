import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service that coordinates usage tracking on the child device
/// Interfaces with native Android service and uploads to Firestore
class UsageTrackingCoordinator {
  final FirebaseFirestore _firestore;
  final MethodChannel _platform;
  Timer? _syncTimer;
  
  UsageTrackingCoordinator({
    FirebaseFirestore? firestore,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _platform = const MethodChannel('com.childsafe.app/screen_capture');

  /// Start the usage tracking service
  Future<void> startTracking() async {
    try {
      debugPrint('UsageTrackingCoordinator: Starting tracking service');
      
      // Start native Android service
      await _platform.invokeMethod('startUsageTracking');
      
      // Start periodic sync to Firestore
      _startPeriodicSync();
      
    } catch (e) {
      debugPrint('UsageTrackingCoordinator: Error starting tracking: $e');
      // Fallback: Start sync anyway
      _startPeriodicSync();
    }
  }

  /// Stop the usage tracking service
  Future<void> stopTracking() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    
    try {
      await _platform.invokeMethod('stopUsageTracking');
    } catch (e) {
      debugPrint('UsageTrackingCoordinator: Error stopping tracking: $e');
    }
  }

  /// Start periodic sync to Firestore (every 15 minutes)
  void _startPeriodicSync() {
    // Sync immediately
    _syncToFirestore();
    
    // Then every 15 minutes
    _syncTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _syncToFirestore(),
    );
  }

  /// Sync usage data to Firestore
  Future<void> _syncToFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('UsageTrackingCoordinator: No user logged in');
        return;
      }

      debugPrint('UsageTrackingCoordinator: Syncing data for user ${user.uid}');

      // Get data from native service
      final screenTimeData = await _getScreenTimeData();
      final appUsageData = await _getAppUsageData();

      debugPrint('UsageTrackingCoordinator: Screen time data: $screenTimeData');
      debugPrint('UsageTrackingCoordinator: App usage data: $appUsageData');

      // Check if we have any real data
      final last7Days = screenTimeData['last7Days'] as List<dynamic>? ?? [];
      final hasScreenTimeData = last7Days.any((d) {
        final day = d as Map<dynamic, dynamic>;
        final minutes = day['minutes'] as int? ?? 0;
        return minutes > 0;
      });
      final hasAppUsageData = (appUsageData['apps']?.length ?? 0) > 0;
      
      if (!hasScreenTimeData && !hasAppUsageData) {
        debugPrint('UsageTrackingCoordinator: No usage data available yet - this is normal for first run');
        debugPrint('UsageTrackingCoordinator: The service needs to run for a while to collect data');
        return;
      }

      // Upload to Firestore
      final batch = _firestore.batch();

      // Screen time document (only when we have meaningful data)
      if (hasScreenTimeData) {
        final screenTimeRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('screenTime')
            .doc('current');

        batch.set(screenTimeRef, {
          'last7Days': screenTimeData['last7Days'],
          'dailyAverage': screenTimeData['dailyAverage'],
          'totalToday': screenTimeData['totalToday'],
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      // App usage document (only when we have app entries)
      if (hasAppUsageData) {
        final appUsageRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('appUsage')
            .doc('current');

        batch.set(appUsageRef, {
          'apps': appUsageData['apps'],
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      debugPrint('UsageTrackingCoordinator: Committing batch to Firestore...');
      await batch.commit();
      
      debugPrint('UsageTrackingCoordinator: Successfully synced usage data to Firestore');
      
    } catch (e, stackTrace) {
      debugPrint('UsageTrackingCoordinator: Error syncing to Firestore: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Get screen time data from native service
  Future<Map<String, dynamic>> _getScreenTimeData() async {
    try {
      final result = await _platform.invokeMethod<Map<dynamic, dynamic>>('getScreenTimeData');
      
      if (result != null) {
        return {
          'last7Days': result['last7Days'] ?? [],
          'dailyAverage': result['dailyAverage'] ?? 0.0,
          'totalToday': result['totalToday'] ?? 0,
        };
      }
    } catch (e) {
      debugPrint('UsageTrackingCoordinator: Error getting screen time: $e');
    }
    
    // Return empty data if native call fails
    return {
      'last7Days': [],
      'dailyAverage': 0.0,
      'totalToday': 0,
    };
  }

  /// Get app usage data from native service
  Future<Map<String, dynamic>> _getAppUsageData() async {
    try {
      final result = await _platform.invokeMethod<Map<dynamic, dynamic>>('getAppUsageData');
      
      if (result != null) {
        final apps = result['apps'] as List<dynamic>? ?? [];
        
        return {
          'apps': apps.map((app) => {
            'packageName': app['packageName'] ?? '',
            'appName': app['appName'] ?? 'Unknown',
            'minutesToday': app['minutesToday'] ?? 0,
            'minutesYesterday': app['minutesYesterday'] ?? 0,
            'weeklyAverage': app['weeklyAverage'] ?? 0.0,
            'weeklyTotalMinutes': app['weeklyTotalMinutes'] ?? 0,
            'iconUrl': app['iconUrl'],
          }).toList(),
        };
      }
    } catch (e) {
      debugPrint('UsageTrackingCoordinator: Error getting app usage: $e');
    }
    
    // Return empty data if native call fails
    return {
      'apps': [],
    };
  }

  /// Force immediate sync
  Future<void> forceSync() async {
    await _syncToFirestore();
  }
}
