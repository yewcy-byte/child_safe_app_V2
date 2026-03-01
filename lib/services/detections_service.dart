import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/detection_model.dart';

class DetectionsService {
  final FirebaseFirestore _firestore;
  final String _childId;

  DetectionsService({
    required String childId,
    FirebaseFirestore? firestore,
  })  : _childId = childId,
        _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _detectionsCollection =>
      _firestore.collection('users').doc(_childId).collection('detections');

  Future<void> logDetection({
    required String packageName,
    required String appName,
    required DetectionType detectionType,
    required double confidenceScore,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      debugPrint('DetectionsService: Logging detection for $appName ($packageName)');
      debugPrint('DetectionsService: Collection path: users/$_childId/detections');
      
      final detection = DetectionModel(
        id: '',
        packageName: packageName,
        appName: appName,
        detectionType: detectionType,
        confidenceScore: confidenceScore,
        timestamp: DateTime.now(),
        metadata: metadata,
      );

      final docRef = await _detectionsCollection.add(detection.toFirestore());
      debugPrint('DetectionsService: Detection logged with ID: ${docRef.id}');
    } catch (e, stackTrace) {
      debugPrint('DetectionsService: ERROR logging detection: $e');
      debugPrint('DetectionsService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  Stream<List<DetectionModel>> getDetectionsStream({
    int limit = 100,
    DetectionType? filterType,
  }) {
    Query<Map<String, dynamic>> query = _detectionsCollection
        .orderBy('timestamp', descending: true)
        .limit(limit);

    if (filterType != null) {
      query = query.where('detectionType', isEqualTo: filterType.value);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => DetectionModel.fromFirestore(doc)).toList();
    });
  }

  Future<List<DetectionModel>> getDetections({
    int limit = 100,
    DetectionType? filterType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    Query<Map<String, dynamic>> query = _detectionsCollection
        .orderBy('timestamp', descending: true)
        .limit(limit);

    if (filterType != null) {
      query = query.where('detectionType', isEqualTo: filterType.value);
    }

    if (startDate != null) {
      query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }

    if (endDate != null) {
      query = query.where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => DetectionModel.fromFirestore(doc)).toList();
  }

  Future<void> deleteDetection(String detectionId) async {
    await _detectionsCollection.doc(detectionId).delete();
  }

  Future<void> clearOldDetections(Duration maxAge) async {
    final cutoffDate = DateTime.now().subtract(maxAge);
    final snapshot = await _detectionsCollection
        .where('timestamp', isLessThan: Timestamp.fromDate(cutoffDate))
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<int> getDetectionCount({
    DetectionType? filterType,
    DateTime? since,
  }) async {
    Query<Map<String, dynamic>> query = _detectionsCollection.where(
      'timestamp',
      isGreaterThanOrEqualTo: Timestamp.fromDate(
        DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );

    if (filterType != null) {
      query = query.where('detectionType', isEqualTo: filterType.value);
    }

    if (since != null) {
      query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    }

    final snapshot = await query.count().get();
    return snapshot.count ?? 0;
  }
}
