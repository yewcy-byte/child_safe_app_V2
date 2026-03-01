import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/filter_settings_model.dart';

class FilterSettingsService {
  final FirebaseFirestore _firestore;

  FilterSettingsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<FilterSettings?> getFilterSettings(String parentId, String childId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('settings')
          .doc('filter_settings')
          .get()
          .timeout(const Duration(seconds: 10));

      if (doc.exists && doc.data() != null) {
        return FilterSettings.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> saveFilterSettings(String parentId, String childId, FilterSettings settings) async {
    try {
      await _firestore
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('settings')
          .doc('filter_settings')
          .set(settings.toMap())
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      rethrow;
    }
  }

  Stream<FilterSettings> watchUserSettings(String parentId, String childId) {
    final stream = _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('settings')
        .doc('filter_settings')
      .snapshots(includeMetadataChanges: true);

    return stream
        .transform<FilterSettings>(
          StreamTransformer<DocumentSnapshot<Map<String, dynamic>>, FilterSettings>.fromHandlers(
            handleData: (doc, sink) {
              final data = doc.data();
              if (data != null) {
                sink.add(FilterSettings.fromMap(data));
              } else {
                sink.add(FilterSettings.disabled(childId));
              }
            },
            handleError: (_, _, sink) =>
                sink.add(FilterSettings.disabled(childId)),
          ),
        );
  }
}
