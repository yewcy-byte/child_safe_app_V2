import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../models/detection_model.dart';
import '../../models/hive/app_usage_cache.dart';
import '../../models/hive/screen_time_cache.dart';

/// Combined service for Activity page data
/// Manages detections, screen time, and app usage
class ActivityService {
  final FirebaseFirestore _firestore;
  final String _parentId;
  bool _initialized = false;

  // Hive boxes for local cache
  late Box<ScreenTimeCache> _screenTimeBox;
  late Box<AppUsageCacheList> _appUsageBox;

  ActivityService({required String parentId, FirebaseFirestore? firestore})
    : _parentId = parentId,
      _firestore = firestore ?? FirebaseFirestore.instance;

  /// Initialize Hive boxes
  Future<void> initialize() async {
    _screenTimeBox = await Hive.openBox<ScreenTimeCache>('screen_time_cache');
    _appUsageBox = await Hive.openBox<AppUsageCacheList>('app_usage_cache');
    _initialized = true;
  }

  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await initialize();
  }

  /// Get stream of detections for a specific child
  Stream<List<DetectionModel>> getDetectionsStream({
    required String childId,
    DetectionType? filterType,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(childId)
        .collection('detections')
        .orderBy('timestamp', descending: true)
        .limit(limit);

    if (filterType != null) {
      query = query.where('detectionType', isEqualTo: filterType.value);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => DetectionModel.fromFirestore(doc))
          .toList();
    });
  }

  /// Get stream of screen time data for a child
  /// Returns cached data immediately, then updates from Firestore
  Stream<ScreenTimeCache> getScreenTimeStream(String childId) async* {
    // First emit cached data
    final cached = _screenTimeBox.get(childId);
    if (cached != null) {
      yield cached;
    } else {
      yield ScreenTimeCache.empty();
    }

    // Then listen to Firestore updates
    yield* _firestore
        .collection('users')
        .doc(childId)
        .collection('screenTime')
        .doc('current')
        .snapshots()
        .asyncMap((doc) async {
          try {
            if (!doc.exists || doc.data() == null) {
              return cached ?? ScreenTimeCache.empty();
            }

            final data = doc.data()!;
            final history =
                (data['last7Days'] as List<dynamic>?)
                    ?.map((d) => (d['minutes'] as num?)?.toInt() ?? 0)
                    .toList() ??
                List.filled(7, 0);

            final screenTimeCache = ScreenTimeCache(
              dailyMinutes: history,
              lastUpdated: DateTime.now(),
              lastSyncAttempt: DateTime.now(),
              syncError: null,
            );

            // Cache locally
            await _screenTimeBox.put(childId, screenTimeCache);
            return screenTimeCache;
          } catch (e) {
            debugPrint('ActivityService: Error fetching screen time: $e');
            final errorCache = (cached ?? ScreenTimeCache.empty()).copyWith(
              lastSyncAttempt: DateTime.now(),
              syncError: e.toString(),
            );
            await _screenTimeBox.put(childId, errorCache);
            return errorCache;
          }
        });
  }

  /// Get stream of app usage data for a child
  /// Returns cached data immediately, then updates from Firestore
  Stream<AppUsageCacheList> getAppUsageStream(String childId) async* {
    // First emit cached data
    final cached = _appUsageBox.get(childId);
    if (cached != null) {
      yield cached;
    } else {
      yield AppUsageCacheList.empty();
    }

    // Then listen to Firestore updates
    yield* _firestore
        .collection('users')
        .doc(childId)
        .collection('appUsage')
        .doc('current')
        .snapshots()
        .asyncMap((doc) async {
          try {
            if (!doc.exists || doc.data() == null) {
              return cached ?? AppUsageCacheList.empty();
            }

            final data = doc.data()!;
            final appsList =
                (data['apps'] as List<dynamic>?)
                    ?.map(
                      (a) => AppUsageCache(
                        packageName: a['packageName'] as String? ?? '',
                        appName: a['appName'] as String? ?? 'Unknown',
                        minutesToday: a['minutesToday'] as int? ?? 0,
                        minutesYesterday: a['minutesYesterday'] as int? ?? 0,
                        weeklyAverage:
                            (a['weeklyAverage'] as num?)?.toDouble() ?? 0.0,
                        iconUrl: a['iconUrl'] as String?,
                        lastUpdated: DateTime.now(),
                      ),
                    )
                    .toList() ??
                [];

            final appUsageCache = AppUsageCacheList(
              apps: appsList,
              lastUpdated: DateTime.now(),
              lastSyncAttempt: DateTime.now(),
              syncError: null,
            );

            // Cache locally
            await _appUsageBox.put(childId, appUsageCache);
            return appUsageCache;
          } catch (e) {
            debugPrint('ActivityService: Error fetching app usage: $e');
            final errorCache = (cached ?? AppUsageCacheList.empty()).copyWith(
              lastSyncAttempt: DateTime.now(),
              syncError: e.toString(),
            );
            await _appUsageBox.put(childId, errorCache);
            return errorCache;
          }
        });
  }

  /// Force refresh all data for a child
  /// Triggers a re-fetch from Firestore
  Future<void> refreshData(String childId) async {
    try {
      // This will trigger the streams to update
      // The actual refresh happens through the Firestore listeners
      debugPrint('ActivityService: Refresh requested for $childId');
    } catch (e) {
      debugPrint('ActivityService: Error refreshing data: $e');
      rethrow;
    }
  }

  /// Get the last sync time for a child
  DateTime? getLastSyncTime(String childId) {
    if (!_initialized) {
      return null;
    }
    final screenTime = _screenTimeBox.get(childId);
    final appUsage = _appUsageBox.get(childId);

    if (screenTime != null && appUsage != null) {
      return screenTime.lastSyncAttempt.isBefore(appUsage.lastSyncAttempt)
          ? screenTime.lastSyncAttempt
          : appUsage.lastSyncAttempt;
    }

    return screenTime?.lastSyncAttempt ?? appUsage?.lastSyncAttempt;
  }

  /// Check if there's a sync error for a child
  String? getSyncError(String childId) {
    if (!_initialized) {
      return null;
    }
    final screenTime = _screenTimeBox.get(childId);
    final appUsage = _appUsageBox.get(childId);

    return screenTime?.syncError ?? appUsage?.syncError;
  }

  /// Clear cache for a specific child
  Future<void> clearCache(String childId) async {
    if (!_initialized) {
      return;
    }
    await _screenTimeBox.delete(childId);
    await _appUsageBox.delete(childId);
  }

  /// Dispose service
  Future<void> dispose() async {
    if (!_initialized) {
      return;
    }
    await _screenTimeBox.close();
    await _appUsageBox.close();
  }
}
