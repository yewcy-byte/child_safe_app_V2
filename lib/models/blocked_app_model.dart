import 'package:cloud_firestore/cloud_firestore.dart';

class BlockedAppModel {
  final String id;
  final String childId;
  final String appName;
  final String packageName;
  final DateTime? blockedUntil;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BlockedAppModel({
    required this.id,
    required this.childId,
    required this.appName,
    required this.packageName,
    required this.blockedUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive {
    if (blockedUntil == null) return true;
    return blockedUntil!.isAfter(DateTime.now());
  }

  factory BlockedAppModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    final blockedUntil = data['blockedUntil'] as Timestamp?;
    final createdAt = data['createdAt'] as Timestamp?;
    final updatedAt = data['updatedAt'] as Timestamp?;

    return BlockedAppModel(
      id: doc.id,
      childId: data['childId'] as String? ?? '',
      appName: data['appName'] as String? ?? '',
      packageName: data['packageName'] as String? ?? '',
      blockedUntil: blockedUntil?.toDate(),
      createdAt: createdAt?.toDate(),
      updatedAt: updatedAt?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'childId': childId,
      'appName': appName,
      'packageName': packageName,
      'blockedUntil': blockedUntil != null ? Timestamp.fromDate(blockedUntil!) : null,
    };
  }
}
