import 'package:cloud_firestore/cloud_firestore.dart';

class GroomingDetectionApp {
  final String packageName;
  final String appName;
  final bool enabled;

  const GroomingDetectionApp({
    required this.packageName,
    required this.appName,
    required this.enabled,
  });
}

class GroomingDetectionAppsService {
  GroomingDetectionAppsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _appsCollection({
    required String parentId,
    required String childId,
  }) {
    return _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('groomingDetectionApps');
  }

  Future<void> setAppEnabled({
    required String parentId,
    required String childId,
    required String packageName,
    required String appName,
    required bool enabled,
  }) async {
    await _appsCollection(parentId: parentId, childId: childId)
        .doc(packageName)
        .set({
      'packageName': packageName,
      'appName': appName,
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<GroomingDetectionApp>> watchApps({
    required String parentId,
    required String childId,
  }) {
    return _appsCollection(parentId: parentId, childId: childId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return GroomingDetectionApp(
          packageName: (data['packageName'] as String?) ?? doc.id,
          appName: (data['appName'] as String?) ?? (data['packageName'] as String?) ?? doc.id,
          enabled: data['enabled'] as bool? ?? true,
        );
      }).toList();
    });
  }

  Stream<Set<String>> watchEnabledPackageNames({
    required String parentId,
    required String childId,
  }) {
    return watchApps(parentId: parentId, childId: childId).map((apps) {
      return apps.where((app) => app.enabled).map((app) => app.packageName).toSet();
    });
  }
}
