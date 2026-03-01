import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/consultant_action.dart';
import './app_time_limits_service.dart';
import './blocked_apps_service.dart';
import './market_service.dart';

/// Executor for AI consultant actions
class ConsultantActionExecutor {
  ConsultantActionExecutor({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AppTimeLimitsService? appTimeLimitsService,
    BlockedAppsService? blockedAppsService,
    MarketService? marketService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _appTimeLimitsService = appTimeLimitsService ?? AppTimeLimitsService(),
        _blockedAppsService = blockedAppsService ?? BlockedAppsService(),
        _marketService = marketService ?? MarketService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final AppTimeLimitsService _appTimeLimitsService;
  final BlockedAppsService _blockedAppsService;
  final MarketService _marketService;

  /// Execute a consultant action
  /// Throws an exception if the action fails
  Future<String> executeAction(ConsultantAction action) async {
    switch (action.type) {
      case 'set_app_time_limit':
        return _setAppTimeLimit(action);
      
      case 'set_daily_screen_limit':
        return _setDailyScreenLimit(action);
      
      case 'block_app':
        return _blockApp(action);
      
      case 'unblock_app':
        return _unblockApp(action);
      
      case 'add_reward':
        return _addReward(action);
      
      default:
        throw 'Unknown action type: ${action.type}';
    }
  }

  Future<String> _setAppTimeLimit(ConsultantAction action) async {
    final packageName = action.parameters['packageName'] as String?;
    final appName = action.parameters['appName'] as String?;
    final minutes = action.parameters['minutes'] as int?;

    if (packageName == null || appName == null || minutes == null) {
      throw 'Missing required parameters: packageName, appName, minutes';
    }

    await _appTimeLimitsService.setAppTimeLimit(
      childId: action.childId,
      packageName: packageName,
      appName: appName,
      minutesLimit: minutes,
    );

    return 'Time limit for $appName set to $minutes minutes.';
  }

  Future<String> _setDailyScreenLimit(ConsultantAction action) async {
    final screenTimeMinutes = action.parameters['screenTimeMinutes'] as int?;

    if (screenTimeMinutes == null) {
      throw 'Missing required parameter: screenTimeMinutes';
    }

    try {
      await _firestore
          .collection('users')
          .doc(action.childId)
          .collection('gamification')
          .doc('tomatoPlant')
          .update({
        'screenTimeAllowanceMinutes': screenTimeMinutes,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      return 'Daily screen time limit set to $screenTimeMinutes minutes.';
    } catch (e) {
      throw 'Failed to set daily screen limit: $e';
    }
  }

  Future<String> _blockApp(ConsultantAction action) async {
    final packageName = action.parameters['packageName'] as String?;
    final appName = action.parameters['appName'] as String?;

    if (packageName == null || appName == null) {
      throw 'Missing required parameters: packageName, appName';
    }

    try {
      final parentId = _auth.currentUser?.uid;
      if (parentId == null) {
        throw 'No authenticated user found';
      }

      await _blockedAppsService.upsertBlockedApp(
        parentId: parentId,
        childId: action.childId,
        appName: appName,
        packageName: packageName,
        blockedUntil: null, // Block forever
      );

      return '$appName has been blocked.';
    } catch (e) {
      throw 'Failed to block app: $e';
    }
  }

  Future<String> _unblockApp(ConsultantAction action) async {
    final packageName = action.parameters['packageName'] as String?;

    if (packageName == null) {
      throw 'Missing required parameter: packageName';
    }

    try {
      final parentId = _auth.currentUser?.uid;
      if (parentId == null) {
        throw 'No authenticated user found';
      }

      final blockedAppId = '${action.childId}_$packageName';
      await _blockedAppsService.removeBlockedApp(
        parentId: parentId,
        blockedAppId: blockedAppId,
      );

      return 'App has been unblocked.';
    } catch (e) {
      throw 'Failed to unblock app: $e';
    }
  }

  Future<String> _addReward(ConsultantAction action) async {
    final rewardText = action.parameters['rewardText'] as String? ?? 
                       action.parameters['title'] as String?;

    if (rewardText == null || rewardText.isEmpty) {
      throw 'Missing required parameter: rewardText or title';
    }

    try {
      await _marketService.addCustomReward(
        childId: action.childId,
        title: rewardText,
        price: 100, // Default cost
      );

      return 'Reward "$rewardText" has been added.';
    } catch (e) {
      throw 'Failed to add reward: $e';
    }
  }
}

