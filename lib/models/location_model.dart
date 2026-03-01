import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a child's location at a specific point in time
class LocationModel {
  final String childId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final DateTime timestamp;
  final String? address;
  final bool isMoving;

  LocationModel({
    required this.childId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
    required this.timestamp,
    this.address,
    this.isMoving = false,
  });

  /// Create LocationModel from Firestore document
  factory LocationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LocationModel(
      childId: data['childId'] ?? '',
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      accuracy: (data['accuracy'] as num?)?.toDouble(),
      altitude: (data['altitude'] as num?)?.toDouble(),
      speed: (data['speed'] as num?)?.toDouble(),
      heading: (data['heading'] as num?)?.toDouble(),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      address: data['address'] as String?,
      isMoving: data['isMoving'] ?? false,
    );
  }

  /// Convert LocationModel to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'childId': childId,
      'latitude': latitude,
      'longitude': longitude,
      if (accuracy != null) 'accuracy': accuracy,
      if (altitude != null) 'altitude': altitude,
      if (speed != null) 'speed': speed,
      if (heading != null) 'heading': heading,
      'timestamp': Timestamp.fromDate(timestamp),
      if (address != null) 'address': address,
      'isMoving': isMoving,
    };
  }

  /// Create a copy with updated fields
  LocationModel copyWith({
    String? childId,
    double? latitude,
    double? longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    double? heading,
    DateTime? timestamp,
    String? address,
    bool? isMoving,
  }) {
    return LocationModel(
      childId: childId ?? this.childId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      timestamp: timestamp ?? this.timestamp,
      address: address ?? this.address,
      isMoving: isMoving ?? this.isMoving,
    );
  }

  @override
  String toString() {
    return 'LocationModel(childId: $childId, lat: $latitude, lng: $longitude, timestamp: $timestamp)';
  }
}

/// Model for location history entry
class LocationHistoryEntry {
  final String id;
  final LocationModel location;

  LocationHistoryEntry({required this.id, required this.location});

  factory LocationHistoryEntry.fromFirestore(DocumentSnapshot doc) {
    return LocationHistoryEntry(
      id: doc.id,
      location: LocationModel.fromFirestore(doc),
    );
  }
}
