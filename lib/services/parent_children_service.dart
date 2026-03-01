import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/child_model.dart';

class ParentChildrenService {
  final FirebaseFirestore _firestore;

  ParentChildrenService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<ChildModel>> watchChildren(String parentId) {
    return _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .orderBy('pairedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(ChildModel.fromFirestore).toList());
  }
}
