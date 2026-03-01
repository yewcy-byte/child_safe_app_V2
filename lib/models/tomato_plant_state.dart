import 'package:cloud_firestore/cloud_firestore.dart';

class TomatoPlantState {
  final int level;
  final int growthPoints;
  final int dailyPenaltyPoints;
  final int tomatoes;
  final double screenTimeAllowanceMinutes;
  final double bonusMinutes;
  final DateTime dayStart;
  final DateTime lastHarvestDate;
  final DateTime lastUpdated;

  TomatoPlantState({
    required this.level,
    required this.growthPoints,
    required this.dailyPenaltyPoints,
    required this.tomatoes,
    required this.screenTimeAllowanceMinutes,
    required this.bonusMinutes,
    required this.dayStart,
    required this.lastHarvestDate,
    required this.lastUpdated,
  });

  factory TomatoPlantState.initial() {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    return TomatoPlantState(
      level: 1,
      growthPoints: 0,
      dailyPenaltyPoints: 0,
      tomatoes: 0,
      screenTimeAllowanceMinutes: 0.0,
      bonusMinutes: 0.0,
      dayStart: dayStart,
      lastHarvestDate: DateTime.fromMillisecondsSinceEpoch(0),
      lastUpdated: now,
    );
  }

  factory TomatoPlantState.fromMap(Map<String, dynamic> map) {
    return TomatoPlantState(
      level: (map['level'] as num?)?.toInt() ?? 1,
      growthPoints: (map['growthPoints'] as num?)?.toInt() ?? 0,
      dailyPenaltyPoints: (map['dailyPenaltyPoints'] as num?)?.toInt() ?? 0,
      tomatoes: (map['tomatoes'] as num?)?.toInt() ?? 0,
      screenTimeAllowanceMinutes:
          (map['screenTimeAllowanceMinutes'] as num?)?.toDouble() ?? 0.0,
        bonusMinutes: (map['bonusMinutes'] as num?)?.toDouble() ?? 0.0,
      dayStart: _parseTimestamp(map['dayStart']) ?? DateTime.now(),
      lastHarvestDate:
          _parseTimestamp(map['lastHarvestDate']) ?? DateTime(1970),
      lastUpdated: _parseTimestamp(map['lastUpdated']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'level': level,
      'growthPoints': growthPoints,
      'dailyPenaltyPoints': dailyPenaltyPoints,
      'tomatoes': tomatoes,
      'screenTimeAllowanceMinutes': screenTimeAllowanceMinutes,
      'bonusMinutes': bonusMinutes,
      'dayStart': Timestamp.fromDate(dayStart),
      'lastHarvestDate': Timestamp.fromDate(lastHarvestDate),
      'lastUpdated': Timestamp.fromDate(lastUpdated),
    };
  }

  TomatoPlantState copyWith({
    int? level,
    int? growthPoints,
    int? dailyPenaltyPoints,
    int? tomatoes,
    double? screenTimeAllowanceMinutes,
    double? bonusMinutes,
    DateTime? dayStart,
    DateTime? lastHarvestDate,
    DateTime? lastUpdated,
  }) {
    return TomatoPlantState(
      level: level ?? this.level,
      growthPoints: growthPoints ?? this.growthPoints,
      dailyPenaltyPoints: dailyPenaltyPoints ?? this.dailyPenaltyPoints,
      tomatoes: tomatoes ?? this.tomatoes,
      screenTimeAllowanceMinutes:
          screenTimeAllowanceMinutes ?? this.screenTimeAllowanceMinutes,
        bonusMinutes: bonusMinutes ?? this.bonusMinutes,
      dayStart: dayStart ?? this.dayStart,
      lastHarvestDate: lastHarvestDate ?? this.lastHarvestDate,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
