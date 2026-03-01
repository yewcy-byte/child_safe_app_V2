import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing app usage data for a single app
class AppUsageItem {
  final String appName;
  final String packageName;
  final int minutesToday;
  final int minutesYesterday;
  final double minutes7DayAvg;
  final String? iconUrl;

  AppUsageItem({
    required this.appName,
    required this.packageName,
    required this.minutesToday,
    required this.minutesYesterday,
    required this.minutes7DayAvg,
    this.iconUrl,
  });

  String get formattedToday {
    final hours = minutesToday ~/ 60;
    final mins = minutesToday % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  factory AppUsageItem.fromMap(Map<String, dynamic> map) {
    return AppUsageItem(
      appName: map['appName'] as String? ?? 'Unknown',
      packageName: map['packageName'] as String? ?? '',
      minutesToday: map['minutesToday'] as int? ?? 0,
      minutesYesterday: map['minutesYesterday'] as int? ?? 0,
      minutes7DayAvg: (map['minutes7DayAvg'] as num?)?.toDouble() ?? 0.0,
      iconUrl: map['iconUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'appName': appName,
      'packageName': packageName,
      'minutesToday': minutesToday,
      'minutesYesterday': minutesYesterday,
      'minutes7DayAvg': minutes7DayAvg,
      'iconUrl': iconUrl,
    };
  }
}

/// Model representing app usage data collection
class AppUsageData {
  final DateTime lastUpdated;
  final List<AppUsageItem> apps;

  AppUsageData({
    required this.lastUpdated,
    required this.apps,
  });

  /// Get top 3 most used apps
  List<AppUsageItem> get top3Apps {
    final sorted = List<AppUsageItem>.from(apps)
      ..sort((a, b) => b.minutesToday.compareTo(a.minutesToday));
    return sorted.take(3).toList();
  }

  /// Get all apps sorted by usage
  List<AppUsageItem> get allAppsSorted {
    return List<AppUsageItem>.from(apps)
      ..sort((a, b) => b.minutesToday.compareTo(a.minutesToday));
  }

  /// Get maximum minutes for chart scaling
  int get maxMinutes {
    if (apps.isEmpty) return 1;
    return apps.map((a) => a.minutesToday).reduce((a, b) => a > b ? a : b);
  }

  factory AppUsageData.fromMap(Map<String, dynamic> map) {
    final appsList = (map['apps'] as List<dynamic>?)
        ?.map((a) => AppUsageItem.fromMap(a as Map<String, dynamic>))
        .toList() ?? [];

    return AppUsageData(
      lastUpdated: (map['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      apps: appsList,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      'apps': apps.map((a) => a.toMap()).toList(),
    };
  }
}
