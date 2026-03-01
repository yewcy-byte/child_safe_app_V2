import 'package:cloud_firestore/cloud_firestore.dart';

class ChildAccountBootstrapService {
  final FirebaseFirestore _firestore;

  ChildAccountBootstrapService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<void> ensureChildStructure(String childId) async {
    final userRef = _firestore.collection('users').doc(childId);

    final batch = _firestore.batch();

    final userSnapshot = await userRef.get();
    final userData = userSnapshot.data() ?? <String, dynamic>{};
    final userUpdates = <String, dynamic>{};
    if (!userData.containsKey('isActive')) {
      userUpdates['isActive'] = true;
    }
    if (!userData.containsKey('shieldActive')) {
      userUpdates['shieldActive'] = true;
    }
    if (userUpdates.isNotEmpty) {
      userUpdates['updatedAt'] = FieldValue.serverTimestamp();
      batch.set(userRef, userUpdates, SetOptions(merge: true));
    }

    await _setDocIfMissing(
      batch,
      userRef.collection('appUsage').doc('current'),
      {
        'apps': <Map<String, dynamic>>[],
        'lastUpdated': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('screenTime').doc('current'),
      {
        'last7Days': <Map<String, dynamic>>[],
        'dailyAverage': 0.0,
        'totalToday': 0,
        'lastUpdated': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('gamification').doc('tomatoPlant'),
      {
        'level': 1,
        'growthPoints': 0,
        'dailyPenaltyPoints': 0,
        'tomatoes': 0,
        'screenTimeAllowanceMinutes': 0.0,
        'bonusMinutes': 0.0,
        'dayStart': FieldValue.serverTimestamp(),
        'lastHarvestDate': Timestamp.fromDate(DateTime(1970)),
        'lastUpdated': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('location').doc('current'),
      {
        'childId': childId,
        'latitude': 0.0,
        'longitude': 0.0,
        'accuracy': 0.0,
        'altitude': 0.0,
        'speed': 0.0,
        'heading': 0.0,
        'isMoving': false,
        'timestamp': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('location_history').doc('_bootstrap'),
      {
        'bootstrap': true,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('inventory').doc('_bootstrap'),
      {
        'bootstrap': true,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('customRewards').doc('_bootstrap'),
      {
        'bootstrap': true,
        'title': 'bootstrap',
        'price': 0,
        'isPurchased': true,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('detections').doc('_bootstrap'),
      {
        'bootstrap': true,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('parents').doc('_bootstrap'),
      {
        'bootstrap': true,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('scanSettings').doc('exclusions'),
      {
        'bootstrap': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('deviceSettings').doc('vivoSetupHelper'),
      {
        'dontShowAgain': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('systemHealth').doc('scanRuntimeStatus'),
      {
        'childId': childId,
        'isRunning': false,
        'expectedRunning': true,
        'reason': 'bootstrap',
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('systemHealth').doc('nativeScanRecovery'),
      {
        'requiresRecovery': false,
        'reason': '',
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    await _setDocIfMissing(
      batch,
      userRef.collection('systemRequests').doc('locationRefresh'),
      {
        'status': 'idle',
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    await batch.commit();
  }

  Future<void> _setDocIfMissing(
    WriteBatch batch,
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      batch.set(ref, data, SetOptions(merge: true));
    }
  }
}
