import 'package:hive/hive.dart';

part 'screen_time_cache.g.dart';

@HiveType(typeId: 1)
class ScreenTimeCache {
  @HiveField(0)
  final List<int> dailyMinutes;
  
  @HiveField(1)
  final DateTime lastUpdated;
  
  @HiveField(2)
  final DateTime lastSyncAttempt;
  
  @HiveField(3)
  final String? syncError;

  ScreenTimeCache({
    required this.dailyMinutes,
    required this.lastUpdated,
    required this.lastSyncAttempt,
    this.syncError,
  });

  factory ScreenTimeCache.empty() {
    return ScreenTimeCache(
      dailyMinutes: List.filled(7, 0),
      lastUpdated: DateTime.now(),
      lastSyncAttempt: DateTime.now(),
      syncError: null,
    );
  }

  int get totalWeekMinutes => dailyMinutes.isNotEmpty 
      ? dailyMinutes.reduce((a, b) => a + b) 
      : 0;
  
  double get dailyAverageMinutes => totalWeekMinutes / 7;
  
  int get todayMinutes => dailyMinutes.isNotEmpty ? dailyMinutes.last : 0;

  ScreenTimeCache copyWith({
    List<int>? dailyMinutes,
    DateTime? lastUpdated,
    DateTime? lastSyncAttempt,
    String? syncError,
  }) {
    return ScreenTimeCache(
      dailyMinutes: dailyMinutes ?? this.dailyMinutes,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastSyncAttempt: lastSyncAttempt ?? this.lastSyncAttempt,
      syncError: syncError ?? this.syncError,
    );
  }
}
