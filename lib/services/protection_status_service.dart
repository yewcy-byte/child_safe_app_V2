import 'package:cloud_firestore/cloud_firestore.dart';

class ProtectionStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<Map<String, dynamic>> watchProtectionStatus(String parentId, String childId) {
    return _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('settings')
        .doc('protection_status')
        .snapshots()
        .map((doc) {
      if (doc.exists && doc.data() != null) {
        return doc.data()!;
      }
      return <String, dynamic>{
        'isActive': true,
        'shieldActive': true,
      };
    });
  }

  Future<Map<String, dynamic>> getProtectionStatus(String parentId, String childId) async {
    final doc = await _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('settings')
        .doc('protection_status')
        .get();

    if (doc.exists && doc.data() != null) {
      return doc.data()!;
    }
    return {
      'isActive': true,
      'shieldActive': true,
    };
  }

  Future<void> setShieldActive({
    required String parentId,
    required String childId,
    required bool enabled,
  }) async {
    final batch = _firestore.batch();

    final parentChildRef = _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('settings')
        .doc('protection_status');

    batch.set(parentChildRef, {
      'shieldActive': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final childRef = _firestore.collection('users').doc(childId);
    batch.update(childRef, {
      'shieldActive': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> setIsActive({
    required String parentId,
    required String childId,
    required bool enabled,
  }) async {
    final batch = _firestore.batch();

    final parentChildRef = _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('settings')
        .doc('protection_status');

    batch.set(parentChildRef, {
      'isActive': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final childRef = _firestore.collection('users').doc(childId);
    batch.update(childRef, {
      'isActive': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> updateProtectionStatus({
    required String parentId,
    required String childId,
    bool? shieldActive,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (shieldActive != null) {
      updates['shieldActive'] = shieldActive;
    }

    if (isActive != null) {
      updates['isActive'] = isActive;
    }

    await _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('settings')
        .doc('protection_status')
        .set(updates, SetOptions(merge: true));
  }
}
