import 'package:cloud_firestore/cloud_firestore.dart';

enum DetectionType {
  nsfw,
  gun,
  gore,
  grooming,
}

extension DetectionTypeExtension on DetectionType {
  String get value {
    switch (this) {
      case DetectionType.nsfw:
        return 'nsfw';
      case DetectionType.gun:
        return 'gun';
      case DetectionType.gore:
        return 'gore';
      case DetectionType.grooming:
        return 'grooming';
    }
  }

  static DetectionType fromString(String type) {
    switch (type) {
      case 'nsfw':
        return DetectionType.nsfw;
      case 'gun':
        return DetectionType.gun;
      case 'gore':
        return DetectionType.gore;
      case 'grooming':
        return DetectionType.grooming;
      default:
        return DetectionType.nsfw;
    }
  }
}

class DetectionModel {
  final String id;
  final String packageName;
  final String appName;
  final DetectionType detectionType;
  final double confidenceScore;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  const DetectionModel({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.detectionType,
    required this.confidenceScore,
    required this.timestamp,
    this.metadata,
  });

  factory DetectionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DetectionModel(
      id: doc.id,
      packageName: data['packageName'] as String? ?? '',
      appName: data['appName'] as String? ?? '',
      detectionType: DetectionTypeExtension.fromString(
        data['detectionType'] as String? ?? 'nsfw',
      ),
      confidenceScore: (data['confidenceScore'] as num?)?.toDouble() ?? 0.0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'packageName': packageName,
      'appName': appName,
      'detectionType': detectionType.value,
      'confidenceScore': confidenceScore,
      'timestamp': FieldValue.serverTimestamp(),
      'metadata': metadata,
    };
  }

  DetectionModel copyWith({
    String? id,
    String? packageName,
    String? appName,
    DetectionType? detectionType,
    double? confidenceScore,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return DetectionModel(
      id: id ?? this.id,
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      detectionType: detectionType ?? this.detectionType,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }
}
