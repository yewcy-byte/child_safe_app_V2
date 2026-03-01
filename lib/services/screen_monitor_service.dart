import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_name_resolver_service.dart';
import '../models/detection_model.dart';

class ScreenMonitorService {
  static const _channel = MethodChannel('com.childsafe.app/screen_capture');
  final _appNameResolver = AppNameResolverService();
  final _firestore = FirebaseFirestore.instance;

  ScreenMonitorService() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'logDetection':
        await _logDetectionToFirestore(call.arguments);
        break;
      case 'shieldDismissed':
        break;
    }
  }

  Future<void> _logDetectionToFirestore(dynamic arguments) async {
    try {
      final packageName = arguments['packageName'] as String?;
      final reason = arguments['reason'] as String?;
      final confidenceScore = (arguments['confidenceScore'] as num?)?.toDouble() ?? 1.0;

      if (packageName == null || reason == null) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final appName = await _appNameResolver.getAppName(packageName);

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('detections')
          .add({
        'packageName': packageName,
        'appName': appName,
        'detectionType': DetectionType.nsfw.value,
        'confidenceScore': confidenceScore,
        'timestamp': FieldValue.serverTimestamp(),
        'metadata': {
          'reason': reason,
          'platform': 'android',
        },
      });
    } catch (e) {
      // Detection logging failed - don't crash the app
    }
  }

  Future<bool> startService() async {
    try {
      await _channel.invokeMethod('startService');
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> stopService() async {
    try {
      await _channel.invokeMethod('stopService');
    } catch (e) {
      // Service might already be stopped
    }
  }

  Future<void> toggleShield(bool show) async {
    try {
      await _channel.invokeMethod('toggleShield', {'show': show});
    } catch (e) {
      // Shield toggle failed
    }
  }

  Future<String?> captureScreen() async {
    try {
      return await _channel.invokeMethod<String>('captureScreen');
    } catch (e) {
      return null;
    }
  }
}
