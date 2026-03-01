import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a child account paired with a parent
class ChildModel {
  final String id;
  final String name;
  final String? profileImageUrl;
  final String? deviceId;
  final DateTime pairedAt;

  // New fields
  final String? email;
  final DateTime? dateOfBirth;
  final int? age;

  ChildModel({
    required this.id,
    required this.name,
    this.profileImageUrl,
    this.deviceId,
    required this.pairedAt,
    this.email,
    this.dateOfBirth,
    this.age,
  });

  /// Calculate age from dateOfBirth
  static int? _calculateAge(DateTime? dateOfBirth) {
    if (dateOfBirth == null) return null;
    
    final now = DateTime.now();
    int age = now.year - dateOfBirth.year;
    
    // Adjust age if birthday hasn't occurred this year
    if (now.month < dateOfBirth.month || 
        (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      age--;
    }
    
    return age;
  }

  /// Create ChildModel from Firestore document
  factory ChildModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Parse dateOfBirth if available
    final dateOfBirthTimestamp = data['dateOfBirth'] as Timestamp?;
    final dateOfBirth = dateOfBirthTimestamp?.toDate();
    
    // Calculate age from dateOfBirth or use stored age
    final storedAge = data['age'] as int?;
    final calculatedAge = storedAge ?? _calculateAge(dateOfBirth);
    
    // Handle name - check for null or empty string
    final rawName = data['name'] as String?;
    final displayName = (rawName != null && rawName.trim().isNotEmpty) 
        ? rawName.trim() 
        : 'Unknown';
    
    return ChildModel(
      id: doc.id,
      name: displayName,
      profileImageUrl: data['profileImageUrl'] as String?,
      deviceId: data['deviceId'] as String?,
      pairedAt: (data['pairedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      email: data['email'] as String?,
      dateOfBirth: dateOfBirth,
      age: calculatedAge,
    );
  }

  /// Convert to Firestore-compatible map
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'profileImageUrl': profileImageUrl,
      'deviceId': deviceId,
      'pairedAt': Timestamp.fromDate(pairedAt),
      'email': email,
      'dateOfBirth': dateOfBirth != null ? Timestamp.fromDate(dateOfBirth!) : null,
      'age': age,
    };
  }

  /// Create a copy with modified fields
  ChildModel copyWith({
    String? id,
    String? name,
    String? profileImageUrl,
    String? deviceId,
    DateTime? pairedAt,
    String? email,
    DateTime? dateOfBirth,
    int? age,
  }) {
    return ChildModel(
      id: id ?? this.id,
      name: name ?? this.name,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      deviceId: deviceId ?? this.deviceId,
      pairedAt: pairedAt ?? this.pairedAt,
      email: email ?? this.email,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      age: age ?? this.age,
    );
  }

  /// Get initials from child name (2 letters)
  String getInitials() {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty || trimmedName == 'Unknown') return '??';
    
    final parts = trimmedName.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '??';
    
    if (parts.length == 1) {
      // Single word - take first 2 letters or just first letter
      return parts[0].length >= 2 
          ? parts[0].substring(0, 2).toUpperCase()
          : parts[0].toUpperCase();
    } else {
      // Multiple words - take first letter of first and last word
      final firstInitial = parts.first[0];
      final lastInitial = parts.last[0];
      return '$firstInitial$lastInitial'.toUpperCase();
    }
  }
}
