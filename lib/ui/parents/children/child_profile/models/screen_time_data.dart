import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a single day's screen time data
class DailyScreenTime {
  final DateTime date;
  final int minutes;

  DailyScreenTime({
    required this.date,
    required this.minutes,
  });

  String get dayLabel {
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[date.weekday % 7];
  }

  String get fullDayLabel {
    final days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    return days[date.weekday % 7];
  }

  String get formattedDuration {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  factory DailyScreenTime.fromMap(Map<String, dynamic> map) {
    return DailyScreenTime(
      date: (map['date'] as Timestamp).toDate(),
      minutes: map['minutes'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'minutes': minutes,
    };
  }
}

/// Model representing screen time data for the past 7 days
class ScreenTimeData {
  final double dailyAverage;
  final List<DailyScreenTime> last7Days;
  final int? totalToday;
  final DateTime? lastUpdated;

  ScreenTimeData({
    required this.dailyAverage,
    required this.last7Days,
    this.totalToday,
    this.lastUpdated,
  });

  /// Get the maximum minutes in the 7-day period for chart scaling
  int get maxMinutes {
    if (last7Days.isEmpty) return 1;
    return last7Days.map((d) => d.minutes).reduce((a, b) => a > b ? a : b);
  }

  factory ScreenTimeData.fromMap(Map<String, dynamic> map) {
    final daysList = (map['last7Days'] as List<dynamic>?)
        ?.map((d) => DailyScreenTime.fromMap(d as Map<String, dynamic>))
        .toList() ?? [];

    return ScreenTimeData(
      dailyAverage: (map['dailyAverage'] as num?)?.toDouble() ?? 0.0,
      last7Days: daysList,
      totalToday: map['totalToday'] as int?,
      lastUpdated: (map['lastUpdated'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dailyAverage': dailyAverage,
      'last7Days': last7Days.map((d) => d.toMap()).toList(),
      'totalToday': totalToday,
      'lastUpdated': lastUpdated != null ? Timestamp.fromDate(lastUpdated!) : null,
    };
  }
}
