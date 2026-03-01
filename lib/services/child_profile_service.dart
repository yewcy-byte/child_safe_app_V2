import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/child_model.dart';
import 'protection_status_service.dart';

/// Service for managing child profile operations
class ChildProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ProtectionStatusService _protectionStatusService = ProtectionStatusService();

  /// Get child profile stream
  Stream<ChildModel> getChildProfile(String parentId, String childId) {
    return _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .snapshots()
        .map((doc) => ChildModel.fromFirestore(doc));
  }

  /// Update child profile information
  Future<void> updateChildProfile({
    required String parentId,
    required String childId,
    String? name,
    DateTime? dateOfBirth,
    String? photoUrl,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (name != null) {
        updates['name'] = name;
      }

      if (dateOfBirth != null) {
        updates['dateOfBirth'] = Timestamp.fromDate(dateOfBirth);
        // Recalculate age
        final age = _calculateAge(dateOfBirth);
        updates['age'] = age;
      }

      if (photoUrl != null) {
        updates['profileImageUrl'] = photoUrl;
      }

      await _firestore
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .update(updates);
    } catch (e) {
      throw Exception('Failed to update child profile: $e');
    }
  }

  /// Calculate age from date of birth
  int? _calculateAge(DateTime dateOfBirth) {
    final now = DateTime.now();
    int age = now.year - dateOfBirth.year;
    
    if (now.month < dateOfBirth.month || 
        (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      age--;
    }
    
    return age;
  }

  /// Toggle child protection status
  /// Updates protection_status subcollection for real-time sync
  Future<void> toggleProtection({
    required String parentId,
    required String childId,
    required bool enabled,
  }) async {
    try {
      await _protectionStatusService.setShieldActive(
        parentId: parentId,
        childId: childId,
        enabled: enabled,
      );
    } catch (e) {
      throw Exception('Failed to toggle protection: $e');
    }
  }

  /// Get screen time data stream (last 7 days)
  Stream<Map<String, dynamic>?> getScreenTimeStream(String childId) {
    return _firestore
        .collection('users')
        .doc(childId)
        .collection('screenTime')
        .doc('current')
        .snapshots()
        .map((doc) => doc.exists ? doc.data() : null);
  }

  /// Get app usage data
  Future<Map<String, dynamic>?> getAppUsage(String childId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(childId)
          .collection('appUsage')
          .doc('current')
          .get();
      
      return doc.exists ? doc.data() : null;
    } catch (e) {
      throw Exception('Failed to get app usage: $e');
    }
  }

  /// Update filter settings
  /// Updates settings/filter_settings subcollection
  Future<void> updateFilterSettings({
    required String parentId,
    required String childId,
    required bool pornFilterEnabled,
    required bool violenceFilterEnabled,
    required int scanIntervalSeconds,
  }) async {
    try {
      final filterSettings = {
        'pornFilterEnabled': pornFilterEnabled,
        'violenceFilterEnabled': violenceFilterEnabled,
        'scanIntervalSeconds': scanIntervalSeconds,
      };

      await _firestore
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('settings')
          .doc('filter_settings')
          .set(filterSettings, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to update filter settings: $e');
    }
  }

  /// Get current filter settings
  /// Reads from settings/filter_settings subcollection
  Future<Map<String, dynamic>?> getFilterSettings(String parentId, String childId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('settings')
          .doc('filter_settings')
          .get();

      if (doc.exists && doc.data() != null) {
        return doc.data();
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get filter settings: $e');
    }
  }
}
