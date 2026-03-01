import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for handling parent-child device pairing
class PairingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Code expiration duration (15 minutes)
  static const Duration _codeExpirationDuration = Duration(minutes: 15);
  
  /// Generates a unique 6-digit pairing code for the parent
  /// 
  /// The code is stored in Firestore and expires after 15 minutes.
  /// Returns the generated pairing code as a String.
  Future<String> generatePairingCode(String parentId) async {
    try {
      // Generate 6-digit code
      final code = _generateRandomCode();
      final expiresAt = DateTime.now().add(_codeExpirationDuration);
      
      // Store in Firestore
      await _firestore.collection('pairing_codes').doc(code).set({
        'parentId': parentId,
        'code': code,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'used': false,
      });
      
      return code;
    } catch (e) {
      throw Exception('Failed to generate pairing code: $e');
    }
  }
  
  /// Validates and uses a pairing code to link a child device
  /// 
  /// Returns the parent ID if successful, null if code is invalid/expired
  Future<String?> validateAndUsePairingCode(String code, String childDeviceId) async {
    try {
      final docRef = _firestore.collection('pairing_codes').doc(code);
      
      return await _firestore.runTransaction<String?>((transaction) async {
        final doc = await transaction.get(docRef);
        
        if (!doc.exists) {
          return null;
        }
        
        final data = doc.data()!;
        final expiresAt = (data['expiresAt'] as Timestamp).toDate();
        final used = data['used'] as bool;
        final parentId = data['parentId'] as String;
        
        // Check if code is expired or already used
        if (DateTime.now().isAfter(expiresAt) || used) {
          return null;
        }
        
        // Mark code as used
        transaction.update(docRef, {'used': true});
        
        return parentId;
      });
    } catch (e) {
      throw Exception('Failed to validate pairing code: $e');
    }
  }

  /// Calculates age from date of birth
  int? _calculateAge(DateTime? dateOfBirth) {
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

  /// Validates a pairing code and links a child with a parent account.
  ///
  /// Marks the code as used and creates references under both users.
  /// Fetches child's profile data to include email and calculate age.
  /// Returns false when the code is invalid/expired/used.
  Future<bool> pairChildWithCode({
    required String code,
    required String childId,
    required String childName,
    String? childPhotoUrl,
  }) async {
    try {
      // First, fetch the child's user document to get additional data
      final childDoc = await _firestore.collection('users').doc(childId).get();
      
      String? childEmail;
      DateTime? dateOfBirth;
      int? age;
      
      if (childDoc.exists) {
        final childData = childDoc.data()!;
        childEmail = childData['email'] as String?;
        
        final dobTimestamp = childData['dateOfBirth'] as Timestamp?;
        if (dobTimestamp != null) {
          dateOfBirth = dobTimestamp.toDate();
          age = _calculateAge(dateOfBirth);
        }
      }
      
      final codeRef = _firestore.collection('pairing_codes').doc(code);

      final parentId = await _firestore.runTransaction<String?>((transaction) async {
        final codeSnapshot = await transaction.get(codeRef);
        if (!codeSnapshot.exists) {
          return null;
        }

        final data = codeSnapshot.data()!;
        final expiresAt = (data['expiresAt'] as Timestamp).toDate();
        final used = data['used'] as bool;
        final parentId = data['parentId'] as String;

        if (DateTime.now().isAfter(expiresAt) || used) {
          return null;
        }

        final parentChildRef = _firestore
            .collection('users')
            .doc(parentId)
            .collection('children')
            .doc(childId);

        final childParentRef = _firestore
            .collection('users')
            .doc(childId)
            .collection('parents')
            .doc(parentId);

        transaction.update(codeRef, {'used': true});
        transaction.set(
          parentChildRef,
          {
            'deviceId': childId,
            'name': childName,
            'profileImageUrl': childPhotoUrl,
            'pairedAt': FieldValue.serverTimestamp(),
            // New fields
            'email': childEmail,
            'dateOfBirth': dateOfBirth != null ? Timestamp.fromDate(dateOfBirth) : null,
            'age': age,
          },
          SetOptions(merge: true),
        );

        // Create protection_status subcollection with defaults
        transaction.set(
          _firestore
              .collection('users')
              .doc(parentId)
              .collection('children')
              .doc(childId)
              .collection('settings')
              .doc('protection_status'),
          {
            'isActive': false,
            'shieldActive': false,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
        transaction.set(
          childParentRef,
          {
            'parentId': parentId,
            'pairedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        // Also store parentId directly in child's user document for easy access
        transaction.set(
          _firestore.collection('users').doc(childId),
          {'parentId': parentId},
          SetOptions(merge: true),
        );

        // Create filter_settings document with defaults
        transaction.set(
          _firestore
              .collection('users')
              .doc(parentId)
              .collection('children')
              .doc(childId)
              .collection('settings')
              .doc('filter_settings'),
          {
            'childUID': childId,
            'pornFilterEnabled': true,
            'violenceFilterEnabled': true,
            'scanIntervalSeconds': 3,
            'lastUpdated': FieldValue.serverTimestamp(),
          },
        );

        return parentId;
      });

      return parentId != null;
    } catch (e) {
      throw Exception('Failed to pair with parent: $e');
    }
  }
  
  /// Pairs a child device with a parent account
  Future<void> pairChildDevice({
    required String parentId,
    required String childDeviceId,
    required String childName,
    String? childEmail,
    DateTime? dateOfBirth,
  }) async {
    try {
      final batch = _firestore.batch();
      
      // Calculate age if dateOfBirth is provided
      final age = _calculateAge(dateOfBirth);
      
      // Add child to parent's children collection
      final childRef = _firestore
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childDeviceId);
      
      batch.set(childRef, {
        'deviceId': childDeviceId,
        'name': childName,
        'pairedAt': FieldValue.serverTimestamp(),
        'email': childEmail,
        'dateOfBirth': dateOfBirth != null ? Timestamp.fromDate(dateOfBirth) : null,
        'age': age,
      });

      // Create protection_status subcollection with defaults
      batch.set(
        _firestore
            .collection('users')
            .doc(parentId)
            .collection('children')
            .doc(childDeviceId)
            .collection('settings')
            .doc('protection_status'),
        {
          'isActive': false,
          'shieldActive': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
      
      // Add parent reference to child device
      final deviceRef = _firestore
          .collection('child_devices')
          .doc(childDeviceId);
      
      batch.set(deviceRef, {
        'parentId': parentId,
        'deviceId': childDeviceId,
        'name': childName,
        'pairedAt': FieldValue.serverTimestamp(),
      });
      
      await batch.commit();
    } catch (e) {
      throw Exception('Failed to pair child device: $e');
    }
  }
  
  /// Unpairs a child device from parent account
  Future<void> unpairChildDevice({
    required String parentId,
    required String childDeviceId,
  }) async {
    try {
      final batch = _firestore.batch();
      
      // Remove from parent's children
      final childRef = _firestore
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childDeviceId);
      
      batch.delete(childRef);
      
      // Remove child device document
      final deviceRef = _firestore
          .collection('child_devices')
          .doc(childDeviceId);
      
      batch.delete(deviceRef);
      
      await batch.commit();
    } catch (e) {
      throw Exception('Failed to unpair child device: $e');
    }
  }
  
  /// Generates a random 6-digit numeric code
  String _generateRandomCode() {
    final random = Random.secure();
    final code = random.nextInt(900000) + 100000; // Range: 100000-999999
    return code.toString();
  }
  
  /// Cleans up expired pairing codes (should be called periodically)
  Future<void> cleanupExpiredCodes() async {
    try {
      final now = Timestamp.now();
      final snapshot = await _firestore
          .collection('pairing_codes')
          .where('expiresAt', isLessThan: now)
          .get();
      
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
    } catch (e) {
      throw Exception('Failed to cleanup expired codes: $e');
    }
  }
}
