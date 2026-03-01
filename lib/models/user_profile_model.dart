import 'package:cloud_firestore/cloud_firestore.dart';

enum AuthProvider { email, google }

class UserProfileModel {
  final String uid;
  final String? name;
  final String email;
  final AuthProvider authProvider;
  final String? photoUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserProfileModel({
    required this.uid,
    this.name,
    required this.email,
    required this.authProvider,
    this.photoUrl,
    this.createdAt,
    this.updatedAt,
  });

  factory UserProfileModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfileModel(
      uid: doc.id,
      name: data['name'] as String?,
      email: data['email'] as String? ?? '',
      authProvider: _parseAuthProvider(data['authProvider'] as String?),
      photoUrl: data['photoUrl'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'authProvider': authProvider.name,
      'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  UserProfileModel copyWith({
    String? uid,
    String? name,
    String? email,
    AuthProvider? authProvider,
    String? photoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfileModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      authProvider: authProvider ?? this.authProvider,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static AuthProvider _parseAuthProvider(String? value) {
    switch (value) {
      case 'google':
        return AuthProvider.google;
      case 'email':
      default:
        return AuthProvider.email;
    }
  }

  String getInitials() {
    if (name == null || name!.isEmpty) return '??';
    
    final parts = name!.trim().split(' ');
    if (parts.length == 1) {
      // Single word - take first 2 letters or just first letter
      return parts[0].length >= 2 
          ? parts[0].substring(0, 2).toUpperCase()
          : parts[0].toUpperCase();
    } else {
      // Multiple words - take first letter of first and last word
      final firstInitial = parts.first.isNotEmpty ? parts.first[0] : '';
      final lastInitial = parts.last.isNotEmpty ? parts.last[0] : '';
      return '$firstInitial$lastInitial'.toUpperCase();
    }
  }
}
