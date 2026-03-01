import 'package:cloud_firestore/cloud_firestore.dart';

enum InventoryItemType { screenTime, goldenTicket }

class InventoryItem {
  final String id;
  final InventoryItemType type;
  final String title;
  final int cost;
  final int valueMinutes;
  final String? parentText;
  final bool isScanned;
  final DateTime createdAt;

  const InventoryItem({
    required this.id,
    required this.type,
    required this.title,
    required this.cost,
    required this.valueMinutes,
    required this.parentText,
    required this.isScanned,
    required this.createdAt,
  });

  factory InventoryItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawType = (data['type'] as String?) ?? 'screenTime';
    final type = rawType == 'goldenTicket'
        ? InventoryItemType.goldenTicket
        : InventoryItemType.screenTime;

    return InventoryItem(
      id: doc.id,
      type: type,
      title: (data['title'] as String?) ?? 'Inventory Item',
      cost: (data['cost'] as num?)?.toInt() ?? 0,
      valueMinutes: (data['valueMinutes'] as num?)?.toInt() ?? 0,
      parentText: data['parentText'] as String?,
      isScanned: (data['isScanned'] as bool?) ?? false,
      createdAt: _timestampToDate(data['createdAt']),
    );
  }

  static DateTime _timestampToDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.now();
  }
}

class CustomReward {
  final String id;
  final String title;
  final int price;
  final bool isPurchased;

  const CustomReward({
    required this.id,
    required this.title,
    required this.price,
    required this.isPurchased,
  });

  factory CustomReward.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return CustomReward(
      id: doc.id,
      title: (data['title'] as String?) ?? 'Golden Ticket',
      price: (data['price'] as num?)?.toInt() ?? 150,
      isPurchased: (data['isPurchased'] as bool?) ?? false,
    );
  }
}

class MarketService {
  static const int item30MinCost = 30;
  static const int item120MinCost = 100;
  static const int goldenTicketCost = 150;

  final FirebaseFirestore _firestore;

  MarketService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _plantRef(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('gamification')
        .doc('tomatoPlant');
  }

  CollectionReference<Map<String, dynamic>> _inventoryRef(String uid) {
    return _firestore.collection('users').doc(uid).collection('inventory');
  }

  CollectionReference<Map<String, dynamic>> _customRewardsRef(String uid) {
    return _firestore.collection('users').doc(uid).collection('customRewards');
  }

  Stream<int> watchTomatoBalance(String uid) {
    return _plantRef(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return 0;
      }
      final data = snapshot.data() ?? <String, dynamic>{};
      return (data['tomatoes'] as num?)?.toInt() ?? 0;
    });
  }

  Stream<int> watchInventoryCount(String uid) {
    return _inventoryRef(uid).snapshots().map(
      (snapshot) => snapshot.docs.where((doc) {
        final data = doc.data();
        return data['bootstrap'] != true;
      }).length,
    );
  }

  Stream<List<InventoryItem>> watchInventory(String uid) {
    return _inventoryRef(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
      .map((snapshot) => snapshot.docs
        .where((doc) => doc.data()['bootstrap'] != true)
        .map(InventoryItem.fromDoc)
        .toList(growable: false));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchInventoryItem(
    String uid,
    String itemId,
  ) {
    return _inventoryRef(uid).doc(itemId).snapshots();
  }

  Stream<List<CustomReward>> watchAvailableCustomRewards(String uid) {
    return _customRewardsRef(uid)
        .where('isPurchased', isEqualTo: false)
        .snapshots()
      .map((snapshot) => snapshot.docs
        .where((doc) => doc.data()['bootstrap'] != true)
        .map(CustomReward.fromDoc)
        .toList(growable: false));
  }

  Future<bool> purchaseScreenTimeItem({
    required String uid,
    required int minutes,
    required int cost,
  }) async {
    final plantRef = _plantRef(uid);
    final inventoryRef = _inventoryRef(uid).doc();

    return _firestore.runTransaction((transaction) async {
      final plantSnapshot = await transaction.get(plantRef);
      final tomatoes =
          (plantSnapshot.data()?['tomatoes'] as num?)?.toInt() ?? 0;
      if (tomatoes < cost) {
        return false;
      }

      transaction.set(
        plantRef,
        {
          'tomatoes': tomatoes - cost,
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      transaction.set(inventoryRef, {
        'type': 'screenTime',
        'title': '$minutes Mins Extra Time',
        'cost': cost,
        'valueMinutes': minutes,
        'isScanned': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    });
  }

  Future<bool> purchaseGoldenTicket({
    required String uid,
    required CustomReward reward,
  }) async {
    final plantRef = _plantRef(uid);
    final rewardRef = _customRewardsRef(uid).doc(reward.id);
    final inventoryRef = _inventoryRef(uid).doc();

    return _firestore.runTransaction((transaction) async {
      final plantSnapshot = await transaction.get(plantRef);
      final rewardSnapshot = await transaction.get(rewardRef);

      final tomatoes =
          (plantSnapshot.data()?['tomatoes'] as num?)?.toInt() ?? 0;
      final isPurchased = (rewardSnapshot.data()?['isPurchased'] as bool?) ?? true;

      if (isPurchased || tomatoes < goldenTicketCost) {
        return false;
      }

      transaction.set(
        plantRef,
        {
          'tomatoes': tomatoes - goldenTicketCost,
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      transaction.set(
        rewardRef,
        {
          'isPurchased': true,
          'purchasedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      transaction.set(inventoryRef, {
        'type': 'goldenTicket',
        'title': 'Golden Ticket',
        'cost': goldenTicketCost,
        'valueMinutes': 0,
        'parentText': reward.title,
        'customRewardId': reward.id,
        'isScanned': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    });
  }

  Future<void> useScreenTimeInventoryItem({
    required String uid,
    required InventoryItem item,
  }) async {
    final plantRef = _plantRef(uid);
    final itemRef = _inventoryRef(uid).doc(item.id);

    await _firestore.runTransaction((transaction) async {
      final plantSnapshot = await transaction.get(plantRef);
      final itemSnapshot = await transaction.get(itemRef);

      if (!itemSnapshot.exists) {
        return;
      }

      final currentBonus =
          (plantSnapshot.data()?['bonusMinutes'] as num?)?.toInt() ?? 0;

      transaction.set(
        plantRef,
        {
          'bonusMinutes': currentBonus + item.valueMinutes,
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      transaction.delete(itemRef);
    });
  }

  Future<void> consumeGoldenTicket({
    required String uid,
    required String itemId,
  }) async {
    await _inventoryRef(uid).doc(itemId).delete();
  }

  Future<bool> markInventoryItemAsScanned({
    required String uid,
    required String itemId,
  }) async {
    try {
      await _inventoryRef(uid).doc(itemId).update({
        'isScanned': true,
        'scannedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeInventoryItem({
    required String uid,
    required String itemId,
  }) async {
    try {
      await _inventoryRef(uid).doc(itemId).delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<InventoryItem?> getInventoryItemById({
    required String uid,
    required String itemId,
  }) async {
    try {
      final snapshot = await _inventoryRef(uid).doc(itemId).get();
      if (snapshot.exists) {
        return InventoryItem.fromDoc(snapshot);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> addCustomReward({
    required String childId,
    required String title,
    int price = goldenTicketCost,
  }) async {
    await _customRewardsRef(childId).add({
      'title': title,
      'price': price,
      'isPurchased': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
