import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Model for apps excluded from content scanning
class ScanExcludedApp {
  final String packageName;
  final String appName;
  final DateTime addedAt;
  final String reason; // 'user_choice', 'gaming', 'performance', etc.

  ScanExcludedApp({
    required this.packageName,
    required this.appName,
    required this.addedAt,
    required this.reason,
  });

  factory ScanExcludedApp.fromFirestore(Map<String, dynamic> data) {
    return ScanExcludedApp(
      packageName: data['packageName'] as String? ?? '',
      appName: data['appName'] as String? ?? '',
      addedAt: (data['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reason: data['reason'] as String? ?? 'user_choice',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'packageName': packageName,
      'appName': appName,
      'addedAt': Timestamp.fromDate(addedAt),
      'reason': reason,
    };
  }
}

/// Service to manage apps excluded from content scanning
class ScanExclusionService {
  final FirebaseFirestore _firestore;

  ScanExclusionService({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Get reference to excluded apps collection for a child
  CollectionReference<Map<String, dynamic>> _getExcludedAppsRef(String childId) {
    return _firestore
        .collection('users')
        .doc(childId)
        .collection('scanSettings')
        .doc('exclusions')
        .collection('apps');
  }

  /// Watch all excluded apps for a child
  Stream<List<ScanExcludedApp>> watchExcludedApps(String childId) {
    return _getExcludedAppsRef(childId)
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => ScanExcludedApp.fromFirestore(doc.data()))
              .toList();
        });
  }

  /// Check if an app is excluded from scanning
  Future<bool> isExcludedFromScanning(String childId, String packageName) async {
    try {
      final doc = await _getExcludedAppsRef(childId).doc(packageName).get();
      return doc.exists;
    } catch (e) {
      debugPrint('isExcludedFromScanning error: $e');
      return false;
    }
  }

  /// Add an app to the exclusion list
  /// [reason] can be: 'user_choice', 'gaming', 'performance', 'auto'
  Future<void> excludeAppFromScanning({
    required String childId,
    required String packageName,
    required String appName,
    required String reason,
  }) async {
    try {
      await _getExcludedAppsRef(childId).doc(packageName).set({
        'packageName': packageName,
        'appName': appName,
        'addedAt': FieldValue.serverTimestamp(),
        'reason': reason,
      });
    } catch (e) {
      throw Exception('Failed to exclude app from scanning: $e');
    }
  }

  /// Remove an app from the exclusion list
  Future<void> removeExclusionFromScanning({
    required String childId,
    required String packageName,
  }) async {
    try {
      await _getExcludedAppsRef(childId).doc(packageName).delete();
    } catch (e) {
      throw Exception('Failed to remove app exclusion: $e');
    }
  }

  /// Clear all user-added exclusions (keep auto ones like gaming apps)
  Future<void> clearUserExclusions(String childId) async {
    try {
      final snapshot = await _getExcludedAppsRef(childId)
          .where('reason', isEqualTo: 'user_choice')
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      throw Exception('Failed to clear exclusions: $e');
    }
  }

  /// Get all excluded apps (synchronously cached)
  Future<List<ScanExcludedApp>> getExcludedApps(String childId) async {
    try {
      final snapshot = await _getExcludedAppsRef(childId).get();
      return snapshot.docs
          .map((doc) => ScanExcludedApp.fromFirestore(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('getExcludedApps error: $e');
      return [];
    }
  }
}
