import 'package:hive/hive.dart';

part 'app_usage_cache.g.dart';

@HiveType(typeId: 2)
class AppUsageCache {
  @HiveField(0)
  final String packageName;
  
  @HiveField(1)
  final String appName;
  
  @HiveField(2)
  final int minutesToday;
  
  @HiveField(3)
  final int minutesYesterday;
  
  @HiveField(4)
  final double weeklyAverage;
  
  @HiveField(5)
  final String? iconUrl;
  
  @HiveField(6)
  final DateTime lastUpdated;

  AppUsageCache({
    required this.packageName,
    required this.appName,
    required this.minutesToday,
    required this.minutesYesterday,
    required this.weeklyAverage,
    this.iconUrl,
    required this.lastUpdated,
  });

  String get formattedToday {
    final hours = minutesToday ~/ 60;
    final mins = minutesToday % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  String get formattedWeeklyAverage {
    final avg = weeklyAverage;
    final hours = avg ~/ 60;
    final mins = (avg % 60).toInt();
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }
}

@HiveType(typeId: 3)
class AppUsageCacheList {
  @HiveField(0)
  final List<AppUsageCache> apps;
  
  @HiveField(1)
  final DateTime lastUpdated;
  
  @HiveField(2)
  final DateTime lastSyncAttempt;
  
  @HiveField(3)
  final String? syncError;

  AppUsageCacheList({
    required this.apps,
    required this.lastUpdated,
    required this.lastSyncAttempt,
    this.syncError,
  });

  factory AppUsageCacheList.empty() {
    return AppUsageCacheList(
      apps: [],
      lastUpdated: DateTime.now(),
      lastSyncAttempt: DateTime.now(),
      syncError: null,
    );
  }

  List<AppUsageCache> get top5Apps {
    final sorted = List<AppUsageCache>.from(apps)
      ..sort((a, b) => b.minutesToday.compareTo(a.minutesToday));
    return sorted.take(5).toList();
  }

  List<AppUsageCache> get allAppsSorted {
    return List<AppUsageCache>.from(apps)
      ..sort((a, b) => b.minutesToday.compareTo(a.minutesToday));
  }

  int get maxMinutes {
    if (apps.isEmpty) return 1;
    return apps.map((a) => a.minutesToday).reduce((a, b) => a > b ? a : b);
  }

  AppUsageCacheList copyWith({
    List<AppUsageCache>? apps,
    DateTime? lastUpdated,
    DateTime? lastSyncAttempt,
    String? syncError,
  }) {
    return AppUsageCacheList(
      apps: apps ?? this.apps,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastSyncAttempt: lastSyncAttempt ?? this.lastSyncAttempt,
      syncError: syncError ?? this.syncError,
    );
  }
}
