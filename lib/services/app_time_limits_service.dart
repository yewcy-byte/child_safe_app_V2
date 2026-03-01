import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppTimeLimitsService {
  AppTimeLimitsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Set time limit for a specific app (in minutes)
  Future<void> setAppTimeLimit({
    required String childId,
    required String packageName,
    required String appName,
    required int minutesLimit,
    int secondsLimit = 0,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw StateError('No authenticated user found.');
    }

    final clampedSeconds = secondsLimit.clamp(0, 59);
    final totalSecondsLimit = (minutesLimit * 60) + clampedSeconds;

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('appTimeLimits')
        .doc(packageName)
        .set({
          'packageName': packageName,
          'appName': appName,
          'minutesLimit': minutesLimit,
          'secondsLimit': clampedSeconds,
          'totalSecondsLimit': totalSecondsLimit,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  /// Remove time limit for a specific app
  Future<void> removeAppTimeLimit({
    required String childId,
    required String packageName,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw StateError('No authenticated user found.');
    }

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('appTimeLimits')
        .doc(packageName)
        .delete();
  }

  /// Get all app time limits for a child
  Stream<Map<String, int>> watchAppTimeLimits(String childId) {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw StateError('No authenticated user found.');
    }

    return _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('appTimeLimits')
        .snapshots()
        .map((snapshot) {
          final limits = <String, int>{};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final packageName = data['packageName'] as String?;
            final totalSecondsLimit = (data['totalSecondsLimit'] as num?)?.toInt();
            final minutesLimit = (data['minutesLimit'] as num?)?.toInt();
            final secondsLimit = (data['secondsLimit'] as num?)?.toInt() ?? 0;
            if (packageName != null) {
              if (totalSecondsLimit != null && totalSecondsLimit > 0) {
                limits[packageName] = totalSecondsLimit;
              } else if (minutesLimit != null && minutesLimit >= 0) {
                limits[packageName] = (minutesLimit * 60) + secondsLimit.clamp(0, 59);
              }
            }
          }
          return limits;
        });
  }

  /// Get time limit for a specific app
  Future<int?> getAppTimeLimit(String childId, String packageName) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw StateError('No authenticated user found.');
    }

    final doc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('appTimeLimits')
        .doc(packageName)
        .get();

    if (!doc.exists) return null;

    final data = doc.data();
    if (data == null) {
      return null;
    }

    final totalSecondsLimit = (data['totalSecondsLimit'] as num?)?.toInt();
    if (totalSecondsLimit != null && totalSecondsLimit > 0) {
      return totalSecondsLimit;
    }

    final minutesLimit = (data['minutesLimit'] as num?)?.toInt();
    final secondsLimit = (data['secondsLimit'] as num?)?.toInt() ?? 0;
    if (minutesLimit == null) {
      return null;
    }
    return (minutesLimit * 60) + secondsLimit.clamp(0, 59);
  }

  /// Check if app time limit is exceeded for today
  Future<bool> isAppTimeLimitExceeded({
    required String childId,
    required String packageName,
    required int currentSecondsUsed,
  }) async {
    final limit = await getAppTimeLimit(childId, packageName);
    if (limit == null) return false;

    return currentSecondsUsed >= limit;
  }
}