import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import '../models/user_profile_model.dart';

class UserProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Future<UserProfileModel?> getCurrentUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        // Create initial profile if doesn't exist
        final profile = UserProfileModel(
          uid: user.uid,
          email: user.email ?? '',
          authProvider: _detectAuthProvider(user),
          photoUrl: user.photoURL,
        );
        await _firestore.collection('users').doc(user.uid).set({
          ...profile.toFirestore(),
          'role': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        return profile;
      }

      return UserProfileModel.fromFirestore(doc);
    } catch (e) {
      throw Exception('Failed to load user profile: $e');
    }
  }

  Future<void> updateUserName(String name) async {
    final user = currentUser;
    if (user == null) throw Exception('No user logged in');

    // Validate max 20 characters
    if (name.length > 20) {
      throw Exception('Name cannot exceed 20 characters');
    }

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'name': name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update name: $e');
    }
  }

  Future<void> changePassword(
    String oldPassword,
    String newPassword,
  ) async {
    final user = currentUser;
    if (user == null) throw Exception('No user logged in');

    // Verify user is email/password user
    final provider = _detectAuthProvider(user);
    if (provider != AuthProvider.email) {
      throw Exception('Password can only be changed for email/password accounts');
    }

    try {
      // Re-authenticate user with old password
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: oldPassword,
      );
      await user.reauthenticateWithCredential(credential);

      // Update password
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        throw Exception('Current password is incorrect');
      }
      throw Exception('Failed to change password: ${e.message}');
    } catch (e) {
      throw Exception('Failed to change password: $e');
    }
  }

  Future<String?> getUserPhotoUrl() async {
    final user = currentUser;
    if (user == null) return null;

    // For Google users, return photoURL from Firebase Auth
    final provider = _detectAuthProvider(user);
    if (provider == AuthProvider.google) {
      return user.photoURL;
    }

    // For email users, check Firestore
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        return doc.data()?['photoUrl'] as String?;
      }
    } catch (e) {
      // Ignore error, return null
    }

    return null;
  }

  AuthProvider getCurrentAuthProvider() {
    final user = currentUser;
    if (user == null) return AuthProvider.email;
    return _detectAuthProvider(user);
  }

  AuthProvider _detectAuthProvider(User user) {
    for (final provider in user.providerData) {
      if (provider.providerId == 'google.com') {
        return AuthProvider.google;
      }
    }
    return AuthProvider.email;
  }

  String getInitials(String? name) {
    if (name == null || name.isEmpty) return '??';

    final parts = name.trim().split(' ');
    if (parts.length == 1) {
      return parts[0].length >= 2
          ? parts[0].substring(0, 2).toUpperCase()
          : parts[0].toUpperCase();
    } else {
      final firstInitial = parts.first.isNotEmpty ? parts.first[0] : '';
      final lastInitial = parts.last.isNotEmpty ? parts.last[0] : '';
      return '$firstInitial$lastInitial'.toUpperCase();
    }
  }
}
