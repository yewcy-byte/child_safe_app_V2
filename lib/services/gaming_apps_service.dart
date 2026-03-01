import 'package:cloud_firestore/cloud_firestore.dart';

/// Known popular gaming package patterns and app IDs
const List<String> _commonGamingPackages = [
  // Popular game publishers and engines
  'com.supercell', // Supercell (Clash, Boom Beach)
  'com.king', // King (Candy Crush)
  'com.playrix', // Playrix (Homescapes, Gardenscapes)
  'com.zynga', // Zynga (Words with Friends)
  'com.miniclip', // Miniclip (8 Ball Pool)
  'com.outfit7', // Outfit7 (My Talking Tom)
  'com.rovio', // Rovio (Angry Birds)
  'com.bandcamp', // Music games
  'air.com.hypercasual', // Hypercasual games
  'com.Raft',
  'com.roblox',
  'com.tencent',
  'com.netease',
  'com.tinyco',
  'com.glu',
  'com.grumpyface',
  'com.halfbrick',
  'com.ea',
  'com.gameloft',
  'com.chillingo',
  'com.etermax', // Trivia Crack
  'com.scopely',
  'com.playlogic',
  'air.WirelessTrivia', // Quiz games
  'com.storm8',
];

/// Service to manage gaming apps and detect if an app is a gaming app
class GamingAppsService {
  static final GamingAppsService _instance = GamingAppsService._internal();
  
  factory GamingAppsService() {
    return _instance;
  }
  
  GamingAppsService._internal();

  /// Check if a package name is a known gaming app
  bool isKnownGamingApp(String packageName) {
    return _commonGamingPackages.any((pattern) => packageName.contains(pattern));
  }

  /// Get parent's custom gaming apps list from Firestore
  Stream<List<String>> watchCustomGamingApps(String parentId, String childId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('settings')
        .doc('gaming_apps')
        .snapshots()
        .map((doc) {
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>?;
            return List<String>.from(data?['customGamingApps'] as List? ?? []);
          }
          return <String>[];
        });
  }

  /// Add a custom gaming app to pause scanning
  Future<void> addCustomGamingApp(
    String parentId,
    String childId,
    String packageName,
  ) async {
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('settings')
        .doc('gaming_apps');

    await docRef.update({
      'customGamingApps': FieldValue.arrayUnion([packageName]),
      'lastModified': FieldValue.serverTimestamp(),
    }).catchError((_) async {
      // If document doesn't exist, create it
      await docRef.set({
        'customGamingApps': [packageName],
        'lastModified': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Remove a custom gaming app
  Future<void> removeCustomGamingApp(
    String parentId,
    String childId,
    String packageName,
  ) async {
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('settings')
        .doc('gaming_apps');

    await docRef.update({
      'customGamingApps': FieldValue.arrayRemove([packageName]),
      'lastModified': FieldValue.serverTimestamp(),
    });
  }

  /// Check if scanning is enabled for this child
  Stream<bool> watchScanningEnabled(String parentId, String childId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('settings')
        .doc('continuous_scanning')
        .snapshots()
        .map((doc) {
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>?;
            return data?['enabled'] as bool? ?? true; // Default to enabled
          }
          return true; // Default to enabled
        });
  }

  /// Enable or disable continuous scanning
  Future<void> setScanningEnabled(
    String parentId,
    String childId,
    bool enabled,
  ) async {
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('settings')
        .doc('continuous_scanning');

    await docRef.set({
      'enabled': enabled,
      'lastModified': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Check if app is a gaming app (known or custom)
  bool isGamingApp(String packageName, List<String> customGamingApps) {
    return isKnownGamingApp(packageName) || customGamingApps.contains(packageName);
  }
}
