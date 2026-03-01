import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/child_model.dart';
import '../../../../models/detection_model.dart';
import '../../../../models/hive/app_usage_cache.dart';
import '../../../../models/hive/screen_time_cache.dart';
import '../../../../services/activity_service.dart';

/// Provider for the ActivityService
/// Creates and initializes the service with the current user's ID
final activityServiceProvider = Provider<ActivityService>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('User not authenticated');
  }

  final service = ActivityService(parentId: user.uid);
  // Initialize async - this will complete in the background
  service.initialize().catchError((e) {
    debugPrint('ActivityService initialization error: $e');
  });

  return service;
});

/// Provider for the selected child ID
final selectedChildIdProvider = StateProvider<String?>((ref) => null);

/// Provider for date range filter
final dateRangeFilterProvider = StateProvider<DateRangeFilter>(
  (ref) => DateRangeFilter.sevenDays,
);

/// Provider for detection type filter
final detectionTypeFilterProvider = StateProvider<DetectionType?>(
  (ref) => null,
);

/// Provider for sort order
final sortOrderProvider = StateProvider<SortOrder>(
  (ref) => SortOrder.newestFirst,
);

/// Enum for date range filtering
enum DateRangeFilter {
  today('Today'),
  sevenDays('7 Days'),
  thirtyDays('30 Days');

  final String label;
  const DateRangeFilter(this.label);

  DateTime get startDate {
    final now = DateTime.now();
    switch (this) {
      case DateRangeFilter.today:
        return DateTime(now.year, now.month, now.day);
      case DateRangeFilter.sevenDays:
        return now.subtract(const Duration(days: 7));
      case DateRangeFilter.thirtyDays:
        return now.subtract(const Duration(days: 30));
    }
  }
}

/// Enum for sort order
enum SortOrder {
  newestFirst('Newest First'),
  oldestFirst('Oldest First');

  final String label;
  const SortOrder(this.label);
}

/// State class for Activity data
@immutable
class ActivityState {
  final AsyncValue<List<DetectionModel>> detections;
  final AsyncValue<ScreenTimeCache> screenTime;
  final AsyncValue<AppUsageCacheList> appUsage;
  final DateTime? lastSyncTime;
  final String? syncError;
  final bool isRefreshing;

  const ActivityState({
    this.detections = const AsyncValue.loading(),
    this.screenTime = const AsyncValue.loading(),
    this.appUsage = const AsyncValue.loading(),
    this.lastSyncTime,
    this.syncError,
    this.isRefreshing = false,
  });

  ActivityState copyWith({
    AsyncValue<List<DetectionModel>>? detections,
    AsyncValue<ScreenTimeCache>? screenTime,
    AsyncValue<AppUsageCacheList>? appUsage,
    DateTime? lastSyncTime,
    String? syncError,
    bool? isRefreshing,
  }) {
    return ActivityState(
      detections: detections ?? this.detections,
      screenTime: screenTime ?? this.screenTime,
      appUsage: appUsage ?? this.appUsage,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      syncError: syncError ?? this.syncError,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }

  /// Get filtered and sorted detections
  List<DetectionModel> getFilteredDetections({
    required DateRangeFilter dateRange,
    required DetectionType? typeFilter,
    required SortOrder sortOrder,
  }) {
    return detections.when(
      data: (list) {
        var filtered = list.where((d) {
          // Date range filter
          if (d.timestamp.isBefore(dateRange.startDate)) {
            return false;
          }
          // Type filter
          if (typeFilter != null && d.detectionType != typeFilter) {
            return false;
          }
          return true;
        }).toList();

        // Sort
        if (sortOrder == SortOrder.oldestFirst) {
          filtered = filtered.reversed.toList();
        }

        return filtered;
      },
      loading: () => [],
      error: (_, __) => [],
    );
  }

  /// Check if any data is loading
  bool get isLoading =>
      detections.isLoading || screenTime.isLoading || appUsage.isLoading;

  /// Check if all data has error
  bool get hasError =>
      detections.hasError && screenTime.hasError && appUsage.hasError;
}

/// StateNotifier for Activity page
class ActivityNotifier extends StateNotifier<ActivityState> {
  final ActivityService _activityService;
  String? _currentChildId;
  final List<StreamSubscription> _subscriptions = [];

  ActivityNotifier({required ActivityService activityService})
    : _activityService = activityService,
      super(const ActivityState());

  @override
  void dispose() {
    // Cancel all subscriptions when notifier is disposed
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }

  /// Initialize and load data for a child
  Future<void> loadChildData(String childId) async {
    await _activityService.ensureInitialized();
    if (_currentChildId == childId) return;

    // Cancel existing subscriptions before switching
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    _currentChildId = childId;
    state = const ActivityState();

    // Get last sync info
    final lastSync = _activityService.getLastSyncTime(childId);
    final syncError = _activityService.getSyncError(childId);

    state = state.copyWith(lastSyncTime: lastSync, syncError: syncError);

    // Subscribe to streams
    _subscribeToStreams(childId);
  }

  void _subscribeToStreams(String childId) {
    // Screen time stream
    final screenTimeSub = _activityService
        .getScreenTimeStream(childId)
        .listen(
          (screenTime) {
            if (mounted) {
              state = state.copyWith(
                screenTime: AsyncValue.data(screenTime),
                lastSyncTime: screenTime.lastSyncAttempt,
                syncError: screenTime.syncError,
              );
            }
          },
          onError: (error, stackTrace) {
            if (mounted) {
              state = state.copyWith(
                screenTime: AsyncValue.error(error, stackTrace),
                syncError: error.toString(),
              );
            }
          },
        );
    _subscriptions.add(screenTimeSub);

    // App usage stream
    final appUsageSub = _activityService
        .getAppUsageStream(childId)
        .listen(
          (appUsage) {
            if (mounted) {
              state = state.copyWith(
                appUsage: AsyncValue.data(appUsage),
                lastSyncTime: appUsage.lastSyncAttempt,
                syncError: appUsage.syncError,
              );
            }
          },
          onError: (error, stackTrace) {
            if (mounted) {
              state = state.copyWith(
                appUsage: AsyncValue.error(error, stackTrace),
                syncError: error.toString(),
              );
            }
          },
        );
    _subscriptions.add(appUsageSub);

    // Detections stream
    final detectionsSub = _activityService
        .getDetectionsStream(childId: childId)
        .listen(
          (detections) {
            if (mounted) {
              state = state.copyWith(detections: AsyncValue.data(detections));
            }
          },
          onError: (error, stackTrace) {
            if (mounted) {
              state = state.copyWith(
                detections: AsyncValue.error(error, stackTrace),
                syncError: error.toString(),
              );
            }
          },
        );
    _subscriptions.add(detectionsSub);
  }

  /// Refresh all data
  Future<void> refresh() async {
    if (_currentChildId == null) return;

    state = state.copyWith(isRefreshing: true);

    try {
      await _activityService.refreshData(_currentChildId!);
      state = state.copyWith(isRefreshing: false);
    } catch (e) {
      state = state.copyWith(isRefreshing: false, syncError: e.toString());
    }
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(syncError: null);
  }
}

/// Provider for ActivityNotifier
final activityProvider = StateNotifierProvider<ActivityNotifier, ActivityState>(
  (ref) {
    final activityService = ref.watch(activityServiceProvider);
    return ActivityNotifier(activityService: activityService);
  },
);

/// Provider for filtered detections
final filteredDetectionsProvider = Provider<List<DetectionModel>>((ref) {
  final state = ref.watch(activityProvider);
  final dateRange = ref.watch(dateRangeFilterProvider);
  final typeFilter = ref.watch(detectionTypeFilterProvider);
  final sortOrder = ref.watch(sortOrderProvider);

  return state.getFilteredDetections(
    dateRange: dateRange,
    typeFilter: typeFilter,
    sortOrder: sortOrder,
  );
});

/// Provider for child list - fetches from Firestore
/// First gets child IDs from parent's subcollection, then fetches full data from users/{childId}
final childrenListProvider = FutureProvider<List<ChildModel>>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('User not authenticated');
  }

  try {
    debugPrint('Fetching children for parent: ${user.uid}');

    // Step 1: Query the parent's children subcollection to get child IDs
    final parentChildrenSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('children')
        .orderBy('pairedAt', descending: true)
        .get();

    debugPrint(
      'Found ${parentChildrenSnapshot.docs.length} child references in parent collection',
    );

    if (parentChildrenSnapshot.docs.isEmpty) {
      return [];
    }

    // Step 2: Fetch full child data from users/{childId} for each child
    final children = <ChildModel>[];

    for (final parentChildDoc in parentChildrenSnapshot.docs) {
      final childId = parentChildDoc.id;
      debugPrint('Fetching full data for child: $childId');

      try {
        // Fetch the full child data from users/{childId}
        final childDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(childId)
            .get();

        if (childDoc.exists) {
          final data = childDoc.data() as Map<String, dynamic>?;
          debugPrint('Child $childId data: $data');
          debugPrint('Child name field: ${data?['name']}');

          final child = ChildModel.fromFirestore(childDoc);
          debugPrint(
            'Parsed child: id=${child.id}, name=${child.name}, age=${child.age}',
          );
          children.add(child);
        } else {
          debugPrint('Child document not found: $childId');
        }
      } catch (e, stackTrace) {
        debugPrint('Error fetching child $childId: $e');
        debugPrint('Stack trace: $stackTrace');
        // Continue with other children even if one fails
      }
    }

    debugPrint('Successfully loaded ${children.length} children');
    return children;
  } catch (e) {
    debugPrint('Error fetching children: $e');
    rethrow;
  }
});
