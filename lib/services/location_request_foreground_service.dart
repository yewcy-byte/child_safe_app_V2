import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../firebase_options.dart';

const String _locationRequestPayloadKey = 'location_request_payload';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await LocationRequestForegroundService.handleIncomingMessage(message.data);
}

@pragma('vm:entry-point')
void startLocationCheckCallback() {
  FlutterForegroundTask.setTaskHandler(LocationRequestTaskHandler());
}

class LocationRequestForegroundService {
  static bool _foregroundTaskInitialized = false;

  static Future<void> initialize() async {
    FlutterForegroundTask.initCommunicationPort();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _initForegroundTask();
    _listenForegroundMessages();
    await _syncFcmTokenToUserDocument();
    FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      _syncFcmTokenToUserDocument();
    });
  }

  static Future<void> handleIncomingMessage(Map<String, dynamic> data) async {
    final command = (data['command'] ?? '').toString();
    if (command != 'GET_LOCATION') {
      return;
    }

    _initForegroundTask();
    await FlutterForegroundTask.saveData(
      key: _locationRequestPayloadKey,
      value: Map<String, dynamic>.from(data),
    );

    final running = await FlutterForegroundTask.isRunningService;
    if (running) {
      await FlutterForegroundTask.restartService();
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 4201,
      notificationTitle: 'Location Check',
      notificationText: 'Updating your location...',
      callback: startLocationCheckCallback,
    );
  }

  static void _initForegroundTask() {
    if (_foregroundTaskInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'location_check_channel',
        channelName: 'Location Check',
        channelDescription:
            'Notification shown while processing emergency location requests.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    _foregroundTaskInitialized = true;
  }

  static void _listenForegroundMessages() {
    FirebaseMessaging.onMessage.listen((message) {
      handleIncomingMessage(message.data);
    });
  }

  static Future<void> _syncFcmTokenToUserDocument() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('LocationRequestForegroundService token sync error: $error');
    }
  }
}

class LocationRequestTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final payload =
          await FlutterForegroundTask.getData(key: _locationRequestPayloadKey)
              as Map<dynamic, dynamic>?;
      final requestData = payload == null
          ? <String, dynamic>{}
          : payload.map(
              (key, value) => MapEntry(key.toString(), value),
            );

      final authUser = FirebaseAuth.instance.currentUser;
      final childId = (requestData['childId'] ?? authUser?.uid)?.toString();
      if (childId == null || childId.isEmpty) {
        await FlutterForegroundTask.stopService();
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        await _markRequestFailed(childId, 'Location permission is not granted');
        await FlutterForegroundTask.stopService();
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _markRequestFailed(childId, 'Location services are disabled');
        await FlutterForegroundTask.stopService();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );

      await _uploadLocation(
        childId: childId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        heading: position.heading,
      );

      await _markRequestCompleted(childId);
    } catch (error) {
      final payload =
          await FlutterForegroundTask.getData(key: _locationRequestPayloadKey)
              as Map<dynamic, dynamic>?;
      final requestData = payload == null
          ? <String, dynamic>{}
          : payload.map(
              (key, value) => MapEntry(key.toString(), value),
            );
      final authUser = FirebaseAuth.instance.currentUser;
      final childId = (requestData['childId'] ?? authUser?.uid)?.toString();
      if (childId != null && childId.isNotEmpty) {
        await _markRequestFailed(childId, error.toString());
      }
    } finally {
      await FlutterForegroundTask.stopService();
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  Future<void> _uploadLocation({
    required String childId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required double altitude,
    required double speed,
    required double heading,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final locationData = {
      'childId': childId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
      'timestamp': Timestamp.now(),
      'isMoving': speed > 0.5,
    };

    await firestore
        .collection('users')
        .doc(childId)
        .collection('location')
        .doc('current')
        .set(locationData, SetOptions(merge: true));

    await firestore
        .collection('users')
        .doc(childId)
        .collection('location_history')
        .add(locationData);
  }

  Future<void> _markRequestCompleted(String childId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(childId)
        .collection('systemRequests')
        .doc('locationRefresh')
        .set({
      'status': 'completed',
      'completedAt': Timestamp.now(),
      'lastError': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Future<void> _markRequestFailed(String childId, String reason) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(childId)
        .collection('systemRequests')
        .doc('locationRefresh')
        .set({
      'status': 'failed',
      'lastError': reason,
      'failedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }
}
