import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/blocked_app_model.dart';

class BlockedAppsService {
  final FirebaseFirestore _firestore;

  BlockedAppsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _blockedAppsCollection(String parentId) {
    return _firestore.collection('users').doc(parentId).collection('blocked_apps');
  }

  Stream<List<BlockedAppModel>> watchBlockedApps({
    required String parentId,
    required String childId,
  }) {
    return _blockedAppsCollection(parentId)
        .where('childId', isEqualTo: childId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => BlockedAppModel.fromFirestore(doc))
          .toList();
    });
  }

  Future<void> upsertBlockedApp({
    required String parentId,
    required String childId,
    required String appName,
    required String packageName,
    required DateTime? blockedUntil,
  }) async {
    try {
      final docId = '${childId}_$packageName';

      final data = {
        'childId': childId,
        'appName': appName,
        'packageName': packageName,
        'blockedUntil': blockedUntil != null ? Timestamp.fromDate(blockedUntil) : null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _blockedAppsCollection(parentId)
          .doc(docId)
          .set({
            ...data,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw Exception('Failed to save blocked app: $e');
    }
  }

  Future<void> updateBlockedUntil({
    required String parentId,
    required String blockedAppId,
    required DateTime? blockedUntil,
  }) async {
    try {
      await _blockedAppsCollection(parentId)
          .doc(blockedAppId)
          .update({
            'blockedUntil':
                blockedUntil != null ? Timestamp.fromDate(blockedUntil) : null,
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw Exception('Failed to update blocked app: $e');
    }
  }

  Future<void> removeBlockedApp({
    required String parentId,
    required String blockedAppId,
  }) async {
    try {
      await _blockedAppsCollection(parentId)
          .doc(blockedAppId)
          .delete()
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw Exception('Failed to remove blocked app: $e');
    }
  }
}
