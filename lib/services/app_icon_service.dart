import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Service for managing app icon uploads and downloads
/// Icons are stored in Firebase Storage and cached locally
class AppIconService {
  final FirebaseStorage _storage;
  late final Box<String> _iconUrlCache;
  
  AppIconService({FirebaseStorage? storage}) 
      : _storage = storage ?? FirebaseStorage.instance;

  /// Initialize the service and open Hive box
  Future<void> initialize() async {
    _iconUrlCache = await Hive.openBox<String>('app_icon_urls');
  }

  /// Upload app icons to Firebase Storage in batch
  /// Returns map of packageName to download URL
  Future<Map<String, String>> uploadAppIcons(
    Map<String, Uint8List> icons, {
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <String, String>{};
    final total = icons.length;
    var current = 0;

    for (final entry in icons.entries) {
      try {
        final packageName = entry.key;
        final iconBytes = entry.value;
        
        // Check if already uploaded
        final cachedUrl = _iconUrlCache.get(packageName);
        if (cachedUrl != null) {
          results[packageName] = cachedUrl;
          current++;
          onProgress?.call(current, total);
          continue;
        }

        // Upload to Firebase Storage
        final ref = _storage.ref('app-icons/$packageName.png');
        
        final metadata = SettableMetadata(
          contentType: 'image/png',
          customMetadata: {
            'packageName': packageName,
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        );

        await ref.putData(iconBytes, metadata);
        final downloadUrl = await ref.getDownloadURL();
        
        // Cache the URL locally
        await _iconUrlCache.put(packageName, downloadUrl);
        results[packageName] = downloadUrl;
        
        current++;
        onProgress?.call(current, total);
        
      } catch (e) {
        debugPrint('AppIconService: Failed to upload icon for ${entry.key}: $e');
        current++;
        onProgress?.call(current, total);
      }
    }

    return results;
  }

  /// Get cached icon URL for a package
  String? getCachedIconUrl(String packageName) {
    return _iconUrlCache.get(packageName);
  }

  /// Preload icon URLs from cache
  Future<void> preloadIconUrls(List<String> packageNames) async {
    // URLs are already in Hive, just ensure box is open
    if (!_iconUrlCache.isOpen) {
      await initialize();
    }
  }

  /// Clear icon cache (useful for troubleshooting)
  Future<void> clearCache() async {
    await _iconUrlCache.clear();
  }

  /// Dispose service
  Future<void> dispose() async {
    await _iconUrlCache.close();
  }
}
