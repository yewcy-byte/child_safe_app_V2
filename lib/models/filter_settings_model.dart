import 'package:cloud_firestore/cloud_firestore.dart';

class FilterSettings {
  final String childUID;
  final bool pornFilterEnabled;
  final bool violenceFilterEnabled;
  final int scanIntervalSeconds;
  final DateTime lastUpdated;

  FilterSettings({
    required this.childUID,
    required this.pornFilterEnabled,
    required this.violenceFilterEnabled,
    required this.scanIntervalSeconds,
    required this.lastUpdated,
  });

  // Convenience getters for child_dashboard.dart
  bool get pornEnabled => pornFilterEnabled;
  bool get violenceEnabled => violenceFilterEnabled;
  Duration get scanInterval => Duration(seconds: scanIntervalSeconds);
  bool get anyEnabled => pornFilterEnabled || violenceFilterEnabled;

  factory FilterSettings.defaults(String userId) {
    return FilterSettings(
      childUID: userId,
      pornFilterEnabled: true,
      violenceFilterEnabled: true,
      scanIntervalSeconds: 3,
      lastUpdated: DateTime.now(),
    );
  }

  factory FilterSettings.disabled(String userId) {
    return FilterSettings(
      childUID: userId,
      pornFilterEnabled: false,
      violenceFilterEnabled: false,
      scanIntervalSeconds: 3,
      lastUpdated: DateTime.now(),
    );
  }

  factory FilterSettings.fromMap(Map<String, dynamic> map) {
    return FilterSettings(
      childUID: map['childUID'] as String,
      pornFilterEnabled: map['pornFilterEnabled'] as bool? ?? false,
      violenceFilterEnabled: map['violenceFilterEnabled'] as bool? ?? false,
      scanIntervalSeconds: map['scanIntervalSeconds'] as int? ?? 3,
      lastUpdated: map['lastUpdated'] is Timestamp
          ? (map['lastUpdated'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'childUID': childUID,
      'pornFilterEnabled': pornFilterEnabled,
      'violenceFilterEnabled': violenceFilterEnabled,
      'scanIntervalSeconds': scanIntervalSeconds,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
    };
  }

  FilterSettings copyWith({
    String? childUID,
    bool? pornFilterEnabled,
    bool? violenceFilterEnabled,
    int? scanIntervalSeconds,
    DateTime? lastUpdated,
  }) {
    return FilterSettings(
      childUID: childUID ?? this.childUID,
      pornFilterEnabled: pornFilterEnabled ?? this.pornFilterEnabled,
      violenceFilterEnabled: violenceFilterEnabled ?? this.violenceFilterEnabled,
      scanIntervalSeconds: scanIntervalSeconds ?? this.scanIntervalSeconds,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
