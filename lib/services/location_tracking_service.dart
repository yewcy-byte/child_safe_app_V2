import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/location_model.dart';

/// Service for tracking and managing child location
class LocationTrackingService {
  static const MethodChannel _channel = MethodChannel(
    'com.childsafe.app/location',
  );
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _uploadTimer;
  Position? _lastPosition;
  DateTime? _lastUploadTime;

  // Upload interval (5 minutes)
  static const Duration _uploadInterval = Duration(minutes: 5);

  // Minimum distance change to trigger upload (100 meters)
  static const double _minimumDistanceMeters = 100.0;

  LocationTrackingService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  })
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _functions = functions ?? FirebaseFunctions.instance,
      _auth = auth ?? FirebaseAuth.instance;

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check location permission status
  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Request location permissions
  Future<LocationPermission> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied');
    }

    return permission;
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    return status.isGranted;
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  /// Request background location permission (Android 10+)
  Future<bool> requestBackgroundPermission() async {
    try {
      // First ensure foreground permission is granted
      final permission = await checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        await requestPermission();
      }

      // Request background permission via native code
      final result = await _channel.invokeMethod<bool>(
        'requestBackgroundLocation',
      );
      return result ?? false;
    } catch (e) {
      debugPrint(
        'LocationTrackingService: Error requesting background permission: $e',
      );
      return false;
    }
  }

  /// Get current location
  Future<LocationModel?> getCurrentLocation() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return LocationModel(
        childId: user.uid,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        heading: position.heading,
        timestamp: DateTime.now(),
        isMoving: position.speed > 0.5, // Moving if speed > 0.5 m/s
      );
    } catch (e) {
      debugPrint('LocationTrackingService: Error getting current location: $e');
      return null;
    }
  }

  /// Upload location to Firestore
  Future<void> uploadLocation(LocationModel location) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('LocationTrackingService: No user logged in');
        return;
      }

      debugPrint(
        'LocationTrackingService: Uploading location for user ${user.uid}',
      );

      // Update current location
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('location')
          .doc('current')
          .set(location.toFirestore(), SetOptions(merge: true));

      // Add to location history
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('location_history')
          .add(location.toFirestore());

      debugPrint('LocationTrackingService: Location uploaded successfully');
      _lastUploadTime = DateTime.now();
    } catch (e) {
      debugPrint('LocationTrackingService: Error uploading location: $e');
      rethrow;
    }
  }

  /// Start location tracking (foreground)
  Future<void> startTracking() async {
    try {
      debugPrint('LocationTrackingService: Starting location tracking');

      // Check permissions
      final permission = await requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied');
      }

      // Check if location service is enabled
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      // Start listening to position changes
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50, // Minimum 50 meters movement
      );

      _positionStreamSubscription =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            _handlePositionUpdate,
            onError: (error) {
              debugPrint(
                'LocationTrackingService: Position stream error: $error',
              );
            },
          );

      // Upload current location immediately
      final currentLocation = await getCurrentLocation();
      if (currentLocation != null) {
        await uploadLocation(currentLocation);
      }

      // Set up periodic upload timer
      _uploadTimer = Timer.periodic(_uploadInterval, (_) async {
        if (_lastPosition != null) {
          final location = await _convertPositionToModel(_lastPosition!);
          if (location != null) {
            await uploadLocation(location);
          }
        }
      });

      debugPrint('LocationTrackingService: Location tracking started');
    } catch (e) {
      debugPrint('LocationTrackingService: Error starting tracking: $e');
      rethrow;
    }
  }

  /// Handle position updates
  void _handlePositionUpdate(Position position) async {
    try {
      debugPrint(
        'LocationTrackingService: Position update received: ${position.latitude}, ${position.longitude}',
      );

      _lastPosition = position;

      // Upload if significant movement or time elapsed
      final shouldUpload = _shouldUploadLocation(position);
      if (shouldUpload) {
        final location = await _convertPositionToModel(position);
        if (location != null) {
          await uploadLocation(location);
        }
      }
    } catch (e) {
      debugPrint('LocationTrackingService: Error handling position update: $e');
    }
  }

  /// Determine if location should be uploaded
  bool _shouldUploadLocation(Position position) {
    // Upload if this is the first position
    if (_lastUploadTime == null) return true;

    // Upload if enough time has passed
    final timeSinceLastUpload = DateTime.now().difference(_lastUploadTime!);
    if (timeSinceLastUpload >= _uploadInterval) return true;

    // Upload if moved significant distance
    if (_lastPosition != null) {
      final distance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      if (distance >= _minimumDistanceMeters) return true;
    }

    return false;
  }

  /// Convert Position to LocationModel
  Future<LocationModel?> _convertPositionToModel(Position position) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      return LocationModel(
        childId: user.uid,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        heading: position.heading,
        timestamp: DateTime.now(),
        isMoving: position.speed > 0.5,
      );
    } catch (e) {
      debugPrint('LocationTrackingService: Error converting position: $e');
      return null;
    }
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    debugPrint('LocationTrackingService: Stopping location tracking');

    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    _uploadTimer?.cancel();
    _uploadTimer = null;

    _lastPosition = null;
    _lastUploadTime = null;

    debugPrint('LocationTrackingService: Location tracking stopped');
  }

  /// Start background location service (native Android service)
  Future<bool> startBackgroundService() async {
    try {
      debugPrint(
        'LocationTrackingService: Starting background location service',
      );

      // Ensure permissions are granted
      final permission = await checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        throw Exception('Location permission not granted');
      }

      final result = await _channel.invokeMethod<bool>('startLocationService');
      debugPrint(
        'LocationTrackingService: Background service start result: $result',
      );
      return result ?? false;
    } catch (e) {
      debugPrint(
        'LocationTrackingService: Error starting background service: $e',
      );
      return false;
    }
  }

  /// Stop background location service
  Future<void> stopBackgroundService() async {
    try {
      debugPrint(
        'LocationTrackingService: Stopping background location service',
      );
      await _channel.invokeMethod('stopLocationService');
    } catch (e) {
      debugPrint(
        'LocationTrackingService: Error stopping background service: $e',
      );
    }
  }

  /// Get location stream for a child (DEPRECATED - use fetchChildLocationNow instead)
  @deprecated
  Stream<LocationModel?> watchChildLocation(String childId) {
    return _firestore
        .collection('users')
        .doc(childId)
        .collection('location')
        .doc('current')
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) return null;
          return LocationModel.fromFirestore(doc);
        });
  }

  /// Fetch child's last known location from Firestore (battery efficient)
  /// Returns the most recently stored location without triggering GPS
  Future<LocationModel?> fetchChildLastKnownLocation(String childId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(childId)
          .collection('location')
          .doc('current')
          .get();

      if (!doc.exists || doc.data() == null) return null;
      return LocationModel.fromFirestore(doc);
    } catch (e) {
      debugPrint(
        'LocationTrackingService: Error fetching last known location: $e',
      );
      return null;
    }
  }

  /// Request and upload current location from child device (on-demand)
  /// This is battery efficient as it only activates GPS when parent requests
  Future<LocationModel?> fetchAndUploadChildLocationNow(
    String childId,
  ) async {
    try {
      debugPrint(
        'LocationTrackingService: Requesting current location for child $childId',
      );

      final requestTime = DateTime.now();
      final triggeredByFunction =
          await _triggerLocationRequestViaCallable(childId);
      if (!triggeredByFunction) {
        await _triggerLocationRequestViaLegacyFirestore(childId, requestTime);
      }

      final deadline = DateTime.now().add(const Duration(seconds: 15));
      LocationModel? latest = await fetchChildLastKnownLocation(childId);

      while (DateTime.now().isBefore(deadline)) {
        if (latest != null && latest.timestamp.isAfter(requestTime)) {
          return latest;
        }

        await Future.delayed(const Duration(seconds: 1));
        latest = await fetchChildLastKnownLocation(childId);
      }

      return latest;
    } catch (e) {
      debugPrint(
        'LocationTrackingService: Error fetching current location: $e',
      );
      return null;
    }
  }

  Future<bool> _triggerLocationRequestViaCallable(String childId) async {
    try {
      final callable = _functions.httpsCallable('requestChildLocation');
      await callable.call({'childId': childId});
      debugPrint(
        'LocationTrackingService: requestChildLocation callable dispatched',
      );
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'LocationTrackingService: Callable location request failed '
        '[${e.code}] ${e.message}; using Firestore fallback',
      );
      return false;
    } catch (e) {
      debugPrint(
        'LocationTrackingService: Callable location request error: $e; '
        'using Firestore fallback',
      );
      return false;
    }
  }

  Future<void> _triggerLocationRequestViaLegacyFirestore(
    String childId,
    DateTime requestTime,
  ) async {
    final requestId =
        '${requestTime.microsecondsSinceEpoch}_${childId.hashCode.abs()}';
    final requesterId = _auth.currentUser?.uid;

    await _firestore
        .collection('users')
        .doc(childId)
        .collection('systemRequests')
        .doc('locationRefresh')
        .set({
          'requestId': requestId,
          'requestedAt': Timestamp.fromDate(requestTime),
          'requestedBy': requesterId,
          'status': 'pending',
        }, SetOptions(merge: true));

    debugPrint('LocationTrackingService: Legacy Firestore location request set');
  }

  /// Get location history for a child
  Future<List<LocationModel>> getLocationHistory({
    required String childId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('users')
          .doc(childId)
          .collection('location_history')
          .orderBy('timestamp', descending: true)
          .limit(limit);

      if (startDate != null) {
        query = query.where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        );
      }

      if (endDate != null) {
        query = query.where(
          'timestamp',
          isLessThanOrEqualTo: Timestamp.fromDate(endDate),
        );
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => LocationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('LocationTrackingService: Error getting location history: $e');
      return [];
    }
  }

  /// Clean up old location history
  Future<void> cleanOldHistory(Duration maxAge) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final cutoffDate = DateTime.now().subtract(maxAge);
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('location_history')
          .where('timestamp', isLessThan: Timestamp.fromDate(cutoffDate))
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      debugPrint(
        'LocationTrackingService: Cleaned ${snapshot.docs.length} old location records',
      );
    } catch (e) {
      debugPrint('LocationTrackingService: Error cleaning old history: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _positionStreamSubscription?.cancel();
    _uploadTimer?.cancel();
  }
}
