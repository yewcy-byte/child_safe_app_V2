import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/filter_settings_model.dart';
import '../../models/blocked_app_model.dart';
import '../../models/detection_model.dart';
import '../../models/hive/app_usage_cache.dart';
import '../../services/filter_settings_service.dart';
import '../../services/nsfw_detection_service.dart';
import '../../services/detections_service.dart';
import '../../services/app_name_resolver_service.dart';
import '../../services/screen_monitor_service.dart';
import '../../services/protection_status_service.dart';
import '../../services/blocked_apps_service.dart';
import '../../services/permission_service.dart';
import '../../services/weapon_gore_detection_service.dart';
import '../../services/tomato_plant_service.dart';
import '../../services/gaming_apps_service.dart';
import '../../services/scan_exclusion_service.dart';
import '../../services/grooming_detection_apps_service.dart';
import '../../services/safety_model_service.dart';

class ChildProtectionRunner extends StatefulWidget {
  final FilterSettings settings;
  final String childId;

  const ChildProtectionRunner({
    super.key,
    required this.settings,
    required this.childId,
  });

  @override
  State<ChildProtectionRunner> createState() => _ChildProtectionRunnerState();
}

class _ChildProtectionRunnerState extends State<ChildProtectionRunner>
    with WidgetsBindingObserver {
  static const Duration _appChangeHealthCheckCooldown = Duration(seconds: 12);
  static const Duration _accessibilityReminderCooldown = Duration(minutes: 2);
  static const Duration _protectionWatchdogInterval = Duration(seconds: 45);
  static const Duration _scanRuntimeHeartbeatInterval = Duration(minutes: 2);
  static const Duration _appLimitWatchInterval = Duration(seconds: 3);
  static const Duration _projectionRecoveryCooldown = Duration(seconds: 20);

  Timer? _scanTimer;
  Timer? _protectionWatchdogTimer;
  Timer? _appLimitWatchTimer;
  Timer? _appBlockAlertTimer;
  Timer? _nsfwAlertTimer;
  final NSFWDetectionService _nsfwService = NSFWDetectionService();
  final WeaponGoreDetectionService _weaponGoreService =
      WeaponGoreDetectionService();
  late DetectionsService _detectionsService;
  late AppNameResolverService _appNameResolver;
  late ScreenMonitorService _screenMonitor;
  final TomatoPlantService _tomatoPlantService = TomatoPlantService();
  final BlockedAppsService _blockedAppsService = BlockedAppsService();
  final ProtectionStatusService _protectionStatusService =
      ProtectionStatusService();
  final FilterSettingsService _filterSettingsService = FilterSettingsService();
  final GamingAppsService _gamingAppsService = GamingAppsService();
  final ScanExclusionService _scanExclusionService = ScanExclusionService();
  final GroomingDetectionAppsService _groomingAppsService =
      GroomingDetectionAppsService();
  final SafetyModelService _safetyModelService = SafetyModelService.instance;
  final screenChannel = const MethodChannel('com.childsafe.app/screen_capture');
  final detectorChannel = const MethodChannel('com.safetyapp/detector');

  bool _isMonitoring = false;
  bool _hasPermission = false;
  bool _isInitializing = false;
  String? _parentId;
  StreamSubscription? _protectionStatusSubscription;
  StreamSubscription<List<BlockedAppModel>>? _blockedAppsSubscription;
  StreamSubscription<FilterSettings>? _filterSettingsSubscription;
  Timer? _filterSettingsReconnectTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _appTimeLimitsSubscription;
  StreamSubscription<Set<String>>? _groomingAppsSubscription;
  StreamSubscription<List<ScanExcludedApp>>? _scanExclusionsSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _nativeRecoverySubscription;
  bool _shieldActive = true; // Default to active
  bool _nsfwShieldActive = false;
  bool _appBlockShieldActive = false;
  bool _screenTimeShieldActive = false;
  bool _appTimeLimitShieldActive = false;
  bool _hasBlockedApps = false;
  bool _appBlockAlertShowing = false;
  bool _nsfwAlertShowing = false;
  bool _screenTimeAlertShowing = false;
  bool _scanInProgress = false;
  bool _appLimitCheckInProgress = false;
  bool _isGamingSession = false;
  DateTime? _lastProjectionRecoveryAttempt;
  DateTime? _lastBlockedAppAlertTime;
  String? _lastBlockedAppPackage;
  DateTime? _lastShieldDismissalTime; // Cooldown after shield dismissal
  Map<String, BlockedAppModel> _blockedAppsByPackage = {};
  Map<String, BlockedAppModel> _blockedAppsByName = {};
  late FilterSettings _activeSettings;
  double _screenTimeAllowanceMinutes = 0.0;
  double _bonusMinutes = 0.0;
  DateTime? _screenTimeDayStart;
  Map<String, int> _appTimeLimits = {}; // packageName -> limit in seconds
  Set<String> _scanExcludedAppsCache = {}; // Cache of excluded package names
  Set<String> _scanExcludedAppNamesCache =
      {}; // Cache of excluded app names (lowercase)
  DateTime? _lastExcludedAppsUpdate; // Track when cache was last updated
  DateTime? _lastAppChangeHealthCheck;
  DateTime? _lastAccessibilityReminder;
  bool? _lastPublishedScanRunningState;
  bool? _lastPublishedScanExpectedState;
  String? _lastPublishedScanReason;
  DateTime? _lastPublishedScanHeartbeatAt;
  Set<String> _groomingEnabledPackages = <String>{};
  String? _activeGroomingPackage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detectionsService = DetectionsService(childId: widget.childId);
    _appNameResolver = AppNameResolverService();
    _screenMonitor = ScreenMonitorService();
    _activeSettings = widget.settings;
    _setupChannelHandlers();
    _setupDetectorChannelHandler();
    _startProtectionWatchdog();

    PermissionService.initialize();

    // Listen for permission changes and auto-start when granted
    PermissionService.permissionStateStream.listen((state) {
      if (mounted &&
          _shouldBeMonitoring() &&
          state.allGranted &&
          !_isMonitoring &&
          !_isInitializing) {
        _initializeProtection();
      }
    });

    _loadParentAndStartListening();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_shouldBeMonitoring()) {
        unawaited(_requestProjectionRecoveryIfNeeded(bypassCooldown: true));
      }
    }
  }

  void _startProtectionWatchdog() {
    _protectionWatchdogTimer?.cancel();
    _protectionWatchdogTimer = Timer.periodic(_protectionWatchdogInterval, (_) {
      if (!mounted) {
        return;
      }
      _runProtectionHealthCheck(source: 'watchdog');
    });
  }

  void _setupChannelHandlers() {
    screenChannel.setMethodCallHandler((call) async {
      if (call.method == 'logDetection') {
        final packageName = call.arguments['packageName'] as String?;
        final reason = call.arguments['reason'] as String?;

        if (packageName != null && reason != null) {
          final appName = await _appNameResolver.getAppName(packageName);
          await _detectionsService.logDetection(
            packageName: packageName,
            appName: appName,
            detectionType: DetectionType.nsfw,
            confidenceScore: 1.0,
            metadata: {'reason': reason},
          );
          try {
            await _tomatoPlantService.deductWater(widget.childId);
          } catch (_) {
            // Ignore gamification updates if they fail
          }
        }
      } else if (call.method == 'shieldDismissed') {
        // Reset both alert flags when shield is dismissed
        debugPrint(
          'shieldDismissed: Resetting alert flags and clearing last blocked app',
        );
        _nsfwShieldActive = false;
        _appBlockShieldActive = false;
        _screenTimeShieldActive = false;
        _appTimeLimitShieldActive = false;
        _appBlockAlertShowing = false; // Allow next alert to show
        _nsfwAlertShowing = false; // Allow next alert to show
        _screenTimeAlertShowing = false; // Allow next alert to show
        _lastBlockedAppPackage = null; // Clear to allow re-blocking
        // DO NOT clear _lastBlockedAppAlertTime - keep it for cooldown
        _lastShieldDismissalTime = DateTime.now(); // Record dismissal time

        // Cancel any active timers
        _appBlockAlertTimer?.cancel();
        _nsfwAlertTimer?.cancel();
      } else if (call.method == 'onAppChanged') {
        // Immediately check if the app is blocked when app changes
        final packageName = call.arguments['packageName'] as String?;

        // Ignore app changes to the ChildSafe app itself (prevents flickering when shield shows)
        if (packageName == 'com.example.child_safe_app') {
          debugPrint('onAppChanged: Ignoring change to ChildSafe app itself');
          return;
        }

        if (packageName != null && mounted) {
          await _ensureProtectionHealthOnAppChange(packageName);
          _handleGroomingAppChange(packageName);
        }

        // Don't trigger if a shield is already active (prevents flickering)
        if (_appBlockShieldActive || _nsfwShieldActive) {
          debugPrint(
            'onAppChanged: Shield already active, ignoring app change to $packageName',
          );
          return;
        }

        if (packageName != null && mounted && _isMonitoring) {
          if (Platform.isAndroid &&
              _blockedAppsByPackage.containsKey(packageName)) {
            debugPrint(
              'onAppChanged: Android blocked app $packageName handled by native block screen',
            );
            return;
          }

          debugPrint('onAppChanged: Checking app $packageName immediately');
          if (!Platform.isAndroid) {
            _checkAndBlockApp(packageName);
          }
          unawaited(_handleAppChange(packageName));
        }
      }
    });
  }

  void _setupDetectorChannelHandler() {
    detectorChannel.setMethodCallHandler((call) async {
      if (call.method != 'onChatTextCaptured') {
        return;
      }

      final args = call.arguments as Map<Object?, Object?>?;
      final packageName = (args?['packageName'] as String?)?.trim();
      final messageText = (args?['text'] as String?)?.trim();
      final messageId = (args?['messageId'] as String?)?.trim();

      if (packageName == null || packageName.isEmpty) {
        return;
      }

      if (!_groomingEnabledPackages.contains(packageName)) {
        debugPrint(
          '_setupDetectorChannelHandler: skip package=$packageName messageId=$messageId reason=package_not_enabled',
        );
        return;
      }

      if (messageText == null || messageText.isEmpty) {
        debugPrint(
          '_setupDetectorChannelHandler: skip package=$packageName messageId=$messageId reason=empty_text',
        );
        return;
      }

      debugPrint(
        '_setupDetectorChannelHandler: analyzing package=$packageName messageId=$messageId chars=${messageText.length}',
      );

      try {
        final result = await _safetyModelService.analyzeText(
          packageName: packageName,
          messageText: messageText,
          messageId: messageId,
        );

        if (result == null) {
          debugPrint(
            '_setupDetectorChannelHandler: skipped package=$packageName messageId=$messageId reason=duplicate_or_empty',
          );
          return;
        }

        debugPrint(
          '_setupDetectorChannelHandler: result package=$packageName messageId=$messageId probability=${result.groomingProbability.toStringAsFixed(3)} threshold=${GroomingInferenceResult.detectionThreshold.toStringAsFixed(2)} isGrooming=${result.isGrooming}',
        );

        if (result.isGrooming) {
          final appName = await _appNameResolver.getAppName(packageName);
          await _detectionsService.logDetection(
            packageName: packageName,
            appName: appName,
            detectionType: DetectionType.grooming,
            confidenceScore: result.groomingProbability,
            metadata: {
              'source': 'chat_text_classifier',
              'messageId': messageId,
            },
          );
        }
      } catch (e) {
        debugPrint('_setupDetectorChannelHandler: safety scan error: $e');
      }
    });
  }

  Future<void> _ensureProtectionHealthOnAppChange(String packageName) async {
    await _runProtectionHealthCheck(source: 'app_change:$packageName');
  }

  Future<void> _runProtectionHealthCheck({required String source}) async {
    if (!mounted || !_shouldBeMonitoring()) {
      return;
    }

    final now = DateTime.now();
    if (_lastAppChangeHealthCheck != null &&
        now.difference(_lastAppChangeHealthCheck!) <
            _appChangeHealthCheckCooldown) {
      return;
    }
    _lastAppChangeHealthCheck = now;

    debugPrint(
      '_runProtectionHealthCheck: source=$source, monitoring=$_isMonitoring, hasPermission=$_hasPermission',
    );

    try {
      final isAccessibilityEnabled = await screenChannel.invokeMethod(
        'checkAccessibilityService',
      );
      if (isAccessibilityEnabled != true) {
        _showAccessibilityReminder();
      }
    } catch (e) {
      debugPrint('_runProtectionHealthCheck: accessibility check failed: $e');
    }

    final shouldBeRunning = _shouldBeMonitoring();

    await _checkScreenTimeExceeded();

    if (_isMonitoring) {
      final projectionActive = await _isProjectionActive();
      if (!projectionActive) {
        final nativeRunning = await _isNativeScanServiceRunning();
        if (nativeRunning) {
          _hasPermission = true;
          await _publishScanRuntimeStatus(
            isRunning: true,
            expectedRunning: shouldBeRunning,
            reason: 'active',
          );
          return;
        }

        _hasPermission = false;
        _scanTimer?.cancel();
        _scanTimer = null;
        if (mounted) {
          setState(() => _isMonitoring = false);
        }
        await _publishScanRuntimeStatus(
          isRunning: false,
          expectedRunning: shouldBeRunning,
          reason: 'projection_inactive',
        );
        final shouldAttemptRecovery =
            !_isInitializing &&
            (_lastProjectionRecoveryAttempt == null ||
                now.difference(_lastProjectionRecoveryAttempt!) >=
                    _projectionRecoveryCooldown);
        if (shouldAttemptRecovery) {
          _lastProjectionRecoveryAttempt = now;
          await _initializeProtection();
        }
        return;
      }

      _lastProjectionRecoveryAttempt = null;

      try {
        await screenChannel.invokeMethod('startService');
      } catch (e) {
        debugPrint(
          '_runProtectionHealthCheck: failed to ensure native service: $e',
        );
      }

      if (_scanTimer?.isActive != true &&
          _shouldScanContent() &&
          _hasPermission) {
        debugPrint(
          '_runProtectionHealthCheck: scan timer inactive, restarting scanner',
        );
        _startScanning();
        await _publishScanRuntimeStatus(
          isRunning: true,
          expectedRunning: shouldBeRunning,
          reason: 'active',
        );
      } else {
        await _publishScanRuntimeStatus(
          isRunning: true,
          expectedRunning: shouldBeRunning,
          reason: 'active',
        );
      }
      return;
    }

    if (!_isInitializing) {
      final nativeRunning = await _isNativeScanServiceRunning();
      if (nativeRunning) {
        await _publishScanRuntimeStatus(
          isRunning: true,
          expectedRunning: shouldBeRunning,
          reason: 'active',
        );
        return;
      }
      await _publishScanRuntimeStatus(
        isRunning: false,
        expectedRunning: shouldBeRunning,
        reason: 'monitoring_inactive',
      );
      debugPrint(
        '_runProtectionHealthCheck: monitoring not active, reinitializing',
      );
      await _initializeProtection();
      return;
    }
  }

  Future<void> _publishScanRuntimeStatus({
    required bool isRunning,
    required bool expectedRunning,
    required String reason,
  }) async {
    if (_parentId == null) {
      return;
    }

    const effectiveExpectedRunning = true;

    final hasChanged =
        _lastPublishedScanRunningState != isRunning ||
        _lastPublishedScanExpectedState != effectiveExpectedRunning ||
        _lastPublishedScanReason != reason;
    final now = DateTime.now();
    final shouldSendHeartbeat =
        _lastPublishedScanHeartbeatAt == null ||
        now.difference(_lastPublishedScanHeartbeatAt!) >=
            _scanRuntimeHeartbeatInterval;

    if (!hasChanged && !shouldSendHeartbeat) {
      return;
    }

    _lastPublishedScanRunningState = isRunning;
    _lastPublishedScanExpectedState = effectiveExpectedRunning;
    _lastPublishedScanReason = reason;
    _lastPublishedScanHeartbeatAt = now;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .collection('systemHealth')
          .doc('scanRuntimeStatus')
          .set({
            'childId': widget.childId,
            'parentId': _parentId,
            'isRunning': isRunning,
            'expectedRunning': effectiveExpectedRunning,
            'reason': reason,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      final shouldMarkRecovery = !isRunning;

      if (shouldMarkRecovery) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.childId)
            .collection('systemHealth')
            .doc('nativeScanRecovery')
            .set({
              'requiresRecovery': true,
              'reason': reason.isNotEmpty
                  ? reason
                  : 'Capture session unavailable',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('_publishScanRuntimeStatus: failed to publish status: $e');
    }
  }

  void _showAccessibilityReminder() {
    if (!mounted) {
      return;
    }

    final now = DateTime.now();
    if (_lastAccessibilityReminder != null &&
        now.difference(_lastAccessibilityReminder!) <
            _accessibilityReminderCooldown) {
      return;
    }
    _lastAccessibilityReminder = now;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Accessibility seems disabled. Re-enable it, then in App Info turn OFF "Pause app activity if unused" (or "Remove permissions if app is unused").',
          maxLines: 3,
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () async {
            try {
              await screenChannel.invokeMethod('openAccessibilitySettings');
            } catch (e) {
              debugPrint(
                '_showAccessibilityReminder: failed to open settings: $e',
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _loadParentAndStartListening() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .get();

      if (!mounted) return;

      _parentId = userDoc.data()?['parentId'] as String?;
      _syncNativeChildContext();
      _listenForScanExclusions(widget.childId);
      _listenForNativeScanRecovery(widget.childId);

      if (_parentId != null) {
        _listenForFilterSettings(_parentId!);
        _listenForBlockedApps(_parentId!);
        _listenForAppTimeLimits(_parentId!);
        _listenForGroomingApps(_parentId!);
        await _ensureScreenCastingPermissionReady();
        // Start listening to protection status changes
        _protectionStatusSubscription = _protectionStatusService
            .watchProtectionStatus(_parentId!, widget.childId)
            .listen((status) {
              if (!mounted) return;

              final newShieldActive = status['shieldActive'] as bool? ?? true;

              setState(() {
                _shieldActive = newShieldActive;
              });

              if (newShieldActive && _shouldBeMonitoring() && !_isMonitoring) {
                // Parent enabled protection - start monitoring
                _initializeProtection();
              }
            });

        // Check initial status
        if (_shouldBeMonitoring()) {
          _initializeProtection();
        }
      } else {
        await _ensureScreenCastingPermissionReady();
        // No parent - just check filter settings
        if (_shouldBeMonitoring()) {
          _initializeProtection();
        }
      }
    } catch (e) {
      debugPrint('Error loading parent ID: $e');
    }
  }

  void _listenForNativeScanRecovery(String childId) {
    _nativeRecoverySubscription?.cancel();
    _nativeRecoverySubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(childId)
        .collection('systemHealth')
        .doc('nativeScanRecovery')
        .snapshots()
        .listen(
          (snapshot) async {
            if (!mounted || !snapshot.exists) {
              return;
            }

            final data = snapshot.data();
            final requiresRecovery = data?['requiresRecovery'] == true;
            if (!requiresRecovery) {
              return;
            }

            await _requestProjectionRecoveryIfNeeded();
          },
          onError: (error) {
            debugPrint('_listenForNativeScanRecovery: stream error: $error');
          },
        );
  }

  Future<void> _checkNativeRecoveryOnAppOpen() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .collection('systemHealth')
          .doc('nativeScanRecovery')
          .get();

      if (!mounted || !snapshot.exists) {
        return;
      }

      final data = snapshot.data();
      final requiresRecovery = data?['requiresRecovery'] == true;
      if (!requiresRecovery) {
        return;
      }

      await _requestProjectionRecoveryIfNeeded(bypassCooldown: true);
    } catch (e) {
      debugPrint(
        '_checkNativeRecoveryOnAppOpen: failed to read recovery doc: $e',
      );
    }
  }

  Future<void> _requestProjectionRecoveryIfNeeded({
    bool bypassCooldown = false,
  }) async {
    if (!mounted) {
      return;
    }

    final now = DateTime.now();
    final inCooldown =
        _lastProjectionRecoveryAttempt != null &&
        now.difference(_lastProjectionRecoveryAttempt!) <
            _projectionRecoveryCooldown;
    if (!bypassCooldown && inCooldown) {
      return;
    }

    if (bypassCooldown) {
      _lastProjectionRecoveryAttempt = now;
      _hasPermission = false;
      await _publishScanRuntimeStatus(
        isRunning: false,
        expectedRunning: _shouldBeMonitoring(),
        reason: 'projection_inactive',
      );

      try {
        await screenChannel.invokeMethod('requestProjectionPermissionRecovery');
      } catch (e) {
        debugPrint(
          '_requestProjectionRecoveryIfNeeded: failed to request projection recovery: $e',
        );
      }
      return;
    }

    final projectionActive = await _isProjectionActive();
    if (projectionActive) {
      _hasPermission = true;
      await _publishScanRuntimeStatus(
        isRunning: true,
        expectedRunning: _shouldBeMonitoring(),
        reason: 'active',
      );
      return;
    }

    _lastProjectionRecoveryAttempt = now;

    _hasPermission = false;
    await _publishScanRuntimeStatus(
      isRunning: false,
      expectedRunning: _shouldBeMonitoring(),
      reason: 'projection_inactive',
    );

    try {
      await screenChannel.invokeMethod('requestProjectionPermissionRecovery');
    } catch (e) {
      debugPrint(
        '_requestProjectionRecoveryIfNeeded: failed to request projection recovery: $e',
      );
    }
  }

  void _listenForBlockedApps(String parentId) {
    // Listen for screen time allowance from Firestore
    FirebaseFirestore.instance
        .collection('users')
        .doc(widget.childId)
        .collection('gamification')
        .doc('tomatoPlant')
        .snapshots()
        .listen((snapshot) async {
          if (mounted && snapshot.exists) {
            final data = snapshot.data();
            final allowance =
                (data?['screenTimeAllowanceMinutes'] as num?)?.toDouble() ??
                0.0;
            final bonusMinutes =
                (data?['bonusMinutes'] as num?)?.toDouble() ?? 0.0;
            final dayStartTimestamp = data?['dayStart'] as Timestamp?;

            if (mounted) {
              setState(() {
                _screenTimeAllowanceMinutes = allowance;
                _bonusMinutes = bonusMinutes;
                _screenTimeDayStart = dayStartTimestamp?.toDate();
              });
              debugPrint(
                'Screen time updated: allowance=$_screenTimeAllowanceMinutes min, bonus=$_bonusMinutes min, dayStart=$_screenTimeDayStart',
              );

              // Apply screen-time enforcement immediately when parent updates limits.
              await _checkScreenTimeExceeded();

              // If parent increases allowance and time is now available, force-clear
              // stale daily screen-time shield state immediately.
              final remainingSeconds = await _currentDailyRemainingSeconds();
              if (remainingSeconds > 0 &&
                  _screenTimeShieldActive &&
                  !_nsfwShieldActive &&
                  !_appBlockShieldActive &&
                  !_appTimeLimitShieldActive) {
                debugPrint(
                  'Screen time update indicates balance available ($remainingSeconds s). Forcing shield hide.',
                );
                await _setScreenTimeExceededShield(false);
              }

              // Start/stop monitoring instantly when DB limit changes.
              if (_shouldBeMonitoring() && !_isMonitoring && !_isInitializing) {
                _initializeProtection();
              }
            }
          }
        });

    _blockedAppsSubscription?.cancel();
    _blockedAppsSubscription = _blockedAppsService
        .watchBlockedApps(parentId: parentId, childId: widget.childId)
        .listen((apps) {
          debugPrint('_listenForBlockedApps: Received ${apps.length} apps');
          for (var app in apps) {
            debugPrint(
              '  - ${app.appName} (${app.packageName}): isActive=${app.isActive}, blockedUntil=${app.blockedUntil}',
            );
          }

          final activeApps = apps.where((app) => app.isActive).toList();
          debugPrint('_listenForBlockedApps: ${activeApps.length} active apps');

          final byPackage = <String, BlockedAppModel>{
            for (final app in activeApps) app.packageName: app,
          };
          final byName = <String, BlockedAppModel>{
            for (final app in activeApps) app.appName.toLowerCase(): app,
          };

          debugPrint(
            '_listenForBlockedApps: byPackage keys: ${byPackage.keys}',
          );
          debugPrint('_listenForBlockedApps: byName keys: ${byName.keys}');

          if (!mounted) return;

          setState(() {
            _blockedAppsByPackage = byPackage;
            _blockedAppsByName = byName;
            _hasBlockedApps = activeApps.isNotEmpty;
          });

          unawaited(_checkScreenTimeExceeded());

          _syncBlockedAppsToNative(byPackage.keys);

          if (_shouldBeMonitoring() && !_isMonitoring && !_isInitializing) {
            _initializeProtection();
          }
        });
  }

  Future<void> _syncBlockedAppsToNative(Iterable<String> packageNames) async {
    try {
      await screenChannel.invokeMethod('updateNativeBlockedApps', {
        'packages': packageNames.toList(growable: false),
      });
    } catch (e) {
      debugPrint(
        '_syncBlockedAppsToNative: Failed to sync blocked packages: $e',
      );
    }
  }

  void _listenForAppTimeLimits(String parentId) {
    _appTimeLimitsSubscription?.cancel();
    _appTimeLimitsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(widget.childId)
        .collection('appTimeLimits')
        .snapshots()
        .listen((snapshot) async {
          if (!mounted) return;

          final limits = <String, int>{};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final packageName = data['packageName'] as String?;
            final totalSecondsLimit = (data['totalSecondsLimit'] as num?)
                ?.toInt();
            final minutesLimit = (data['minutesLimit'] as num?)?.toInt();
            final secondsLimit = ((data['secondsLimit'] as num?)?.toInt() ?? 0)
                .clamp(0, 59);

            if (packageName == null || packageName.isEmpty) {
              continue;
            }

            if (totalSecondsLimit != null && totalSecondsLimit > 0) {
              limits[packageName] = totalSecondsLimit;
            } else if (minutesLimit != null && minutesLimit >= 0) {
              limits[packageName] = (minutesLimit * 60) + secondsLimit;
            }
          }

          debugPrint(
            '_listenForAppTimeLimits: Received ${limits.length} app time limits',
          );

          setState(() {
            _appTimeLimits = limits;
          });

          await _reevaluateCurrentAppTimeLimitFromFirestore();
        });
  }

  Future<void> _reevaluateCurrentAppTimeLimitFromFirestore() async {
    try {
      final packageName = await _getForegroundApp();
      if (packageName == null || packageName.isEmpty) {
        return;
      }

      final limitSeconds = _appTimeLimits[packageName];
      if (limitSeconds == null) {
        if (_appTimeLimitShieldActive) {
          final appName = await _appNameResolver.getAppName(packageName);
          debugPrint(
            '_listenForAppTimeLimits: No limit for foreground app ($packageName). Hiding app-limit shield.',
          );
          await _setAppTimeLimitExceededShield(false, appName, 0);
        }
        return;
      }

      await _checkAppTimeLimitExceeded(packageName);
    } catch (e) {
      debugPrint('_reevaluateCurrentAppTimeLimitFromFirestore: $e');
    }
  }

  void _listenForGroomingApps(String parentId) {
    _groomingAppsSubscription?.cancel();
    _groomingAppsSubscription = _groomingAppsService
        .watchEnabledPackageNames(parentId: parentId, childId: widget.childId)
        .listen((packages) async {
          _groomingEnabledPackages = packages;
          if (_activeGroomingPackage != null &&
              !_groomingEnabledPackages.contains(_activeGroomingPackage)) {
            _activeGroomingPackage = null;
          }
          debugPrint(
            '_listenForGroomingApps: enabled packages=${_groomingEnabledPackages.length}',
          );

          try {
            await screenChannel.invokeMethod('updateNativeGroomingPackages', {
              'packages': packages.toList(growable: false),
            });
          } catch (e) {
            debugPrint(
              '_listenForGroomingApps: failed syncing grooming packages to native: $e',
            );
          }
        });
  }

  void _listenForFilterSettings(String parentId) {
    _filterSettingsSubscription?.cancel();
    _filterSettingsReconnectTimer?.cancel();
    _filterSettingsSubscription = _filterSettingsService
        .watchUserSettings(parentId, widget.childId)
        .listen(
          (settings) {
            if (!mounted) return;

            setState(() {
              _activeSettings = settings;
            });

            _syncScanConfigToNative(settings);
            _ensureScreenCastingPermissionReady();

            if (_isMonitoring) {
              _restartScanning();
            }

            if (_shouldBeMonitoring() && !_isMonitoring && !_isInitializing) {
              _initializeProtection();
            }
          },
          onError: (error) {
            debugPrint(
              '_listenForFilterSettings: stream error, retrying listener: $error',
            );
            if (!mounted) {
              return;
            }

            _filterSettingsReconnectTimer?.cancel();
            _filterSettingsReconnectTimer = Timer(
              const Duration(seconds: 2),
              () {
                if (!mounted) {
                  return;
                }
                _listenForFilterSettings(parentId);
              },
            );
          },
          onDone: () {
            debugPrint(
              '_listenForFilterSettings: stream closed, restarting listener',
            );
            if (!mounted) {
              return;
            }

            _filterSettingsReconnectTimer?.cancel();
            _filterSettingsReconnectTimer = Timer(
              const Duration(seconds: 2),
              () {
                if (!mounted) {
                  return;
                }
                _listenForFilterSettings(parentId);
              },
            );
          },
        );
  }

  Future<void> _ensureScreenCastingPermissionReady() async {
    if (!mounted || _hasPermission) {
      return;
    }

    try {
      final state = await PermissionService.checkAllPermissions();
      if (state.overlay != PermissionStatus.granted) {
        return;
      }

      await screenChannel.invokeMethod('startService');
      final projectionActive = await _isProjectionActive();
      _hasPermission = projectionActive;
      if (projectionActive) {
        debugPrint(
          '_ensureScreenCastingPermissionReady: media projection permission/service ready',
        );
      }
    } catch (e) {
      _hasPermission = false;
      debugPrint(
        '_ensureScreenCastingPermissionReady: unable to start media projection service: $e',
      );
    }
  }

  Future<void> _syncScanConfigToNative(FilterSettings settings) async {
    try {
      await screenChannel.invokeMethod('updateNativeScanConfig', {
        'pornEnabled': settings.pornFilterEnabled,
        'violenceEnabled': settings.violenceFilterEnabled,
        'scanIntervalSeconds': settings.scanIntervalSeconds,
      });
    } catch (e) {
      debugPrint('_syncScanConfigToNative: Failed to sync config: $e');
    }
  }

  Future<bool> _checkIfAppBlocked(String? packageName) async {
    if (Platform.isAndroid) {
      return false;
    }

    if (!_hasBlockedApps || packageName == null) {
      await _setAppBlockShield(false);
      return false;
    }

    debugPrint(
      '_checkIfAppBlocked: Checking $packageName. Blocked apps: ${_blockedAppsByPackage.keys}',
    );

    // Check by package name (exact match)
    if (_blockedAppsByPackage.containsKey(packageName)) {
      debugPrint('_checkIfAppBlocked: BLOCKED by package: $packageName');
      await _setAppBlockShield(true, packageName: packageName);
      return true;
    }

    // Check by app name (fallback)
    if (_blockedAppsByName.isNotEmpty) {
      final appName = await _appNameResolver.getAppName(packageName);
      debugPrint(
        '_checkIfAppBlocked: App name for $packageName is $appName. Blocked names: ${_blockedAppsByName.keys}',
      );
      if (_blockedAppsByName.containsKey(appName.toLowerCase())) {
        debugPrint('_checkIfAppBlocked: BLOCKED by name: $appName');
        await _setAppBlockShield(true, packageName: packageName);
        return true;
      }
    }

    await _setAppBlockShield(false);
    return false;
  }

  // Immediately check and block app without cooldown
  Future<void> _checkAndBlockApp(String packageName) async {
    if (!_hasBlockedApps) return;

    // Don't trigger if a shield is already showing
    if (_appBlockShieldActive) {
      debugPrint(
        '_checkAndBlockApp: Shield already active, skipping check for $packageName',
      );
      return;
    }

    // Check if app is blocked by package name
    if (_blockedAppsByPackage.containsKey(packageName)) {
      debugPrint('_checkAndBlockApp: Instantly blocking $packageName');
      _lastBlockedAppPackage = packageName;
      _lastBlockedAppAlertTime = DateTime.now();
      await _setAppBlockShield(true, packageName: packageName);
      return;
    }

    // Check by app name
    if (_blockedAppsByName.isNotEmpty) {
      final appName = await _appNameResolver.getAppName(packageName);
      if (_blockedAppsByName.containsKey(appName.toLowerCase())) {
        debugPrint('_checkAndBlockApp: Instantly blocking $appName');
        _lastBlockedAppPackage = packageName;
        _lastBlockedAppAlertTime = DateTime.now();
        await _setAppBlockShield(true, packageName: packageName);
        return;
      }
    }
  }

  Future<void> _applyAppBlock(String? packageName) async {
    if (!_hasBlockedApps) {
      await _setAppBlockShield(false);
      return;
    }

    if (packageName == null) {
      await _setAppBlockShield(false);
      return;
    }

    if (_blockedAppsByPackage.containsKey(packageName)) {
      await _setAppBlockShield(true, packageName: packageName);
      return;
    }

    if (_blockedAppsByName.isNotEmpty) {
      final appName = await _appNameResolver.getAppName(packageName);
      if (_blockedAppsByName.containsKey(appName.toLowerCase())) {
        await _setAppBlockShield(true, packageName: packageName);
        return;
      }
    }

    await _setAppBlockShield(false);
  }

  Future<void> _setAppBlockShield(bool show, {String? packageName}) async {
    if (Platform.isAndroid) {
      _appBlockShieldActive = false;
      _appBlockAlertShowing = false;
      return;
    }

    // Always allow re-showing shield even if already active (handles rapid re-open)
    // Skip only if trying to hide when already hidden
    if (!show && !_appBlockShieldActive) return;

    if (!show && _nsfwShieldActive) {
      _appBlockShieldActive = false;
      return;
    }

    _appBlockShieldActive = show;

    // Set flag early to prevent NSFW alerts from being shown
    if (show) {
      _appBlockAlertShowing = true;
      _nsfwAlertShowing = false;
    } else {
      _appBlockAlertShowing = false;
    }

    try {
      // Load the image as base64
      final imageBytes = await rootBundle.load('assets/images/blockApp.png');
      final base64Image = base64.encode(imageBytes.buffer.asUint8List());

      await screenChannel.invokeMethod('toggleShield', {
        'show': show,
        'type': 'app_block',
        'imageBase64': base64Image,
      });
    } catch (e) {
      debugPrint('_setAppBlockShield: Error loading image: $e');
      // Shield toggle failed
    }

    // Do not show a second Flutter dialog here.
    // Native overlay is the single source of app-block UI.
  }

  bool _shouldBeMonitoring() {
    // Keep monitoring infrastructure active whenever protection is enabled.
    // Content scanning itself is still controlled by _shouldScanContent().
    return _shieldActive;
  }

  bool _shouldScanContent() {
    // Don't scan if filters disabled, shield inactive, or gaming session
    if (!_activeSettings.anyEnabled || !_shieldActive || _isGamingSession) {
      return false;
    }
    // Also check if current foreground app is excluded from scanning
    // (Will be checked dynamically in _performScan)
    return true;
  }

  /// Refresh the cache of excluded apps periodically
  Future<void> _updateScanExclusionsCache() async {
    try {
      final now = DateTime.now();
      // Only update cache every 5 minutes to avoid excessive Firestore reads
      if (_lastExcludedAppsUpdate != null &&
          now.difference(_lastExcludedAppsUpdate!).inMinutes < 5) {
        return;
      }

      final excluded = await _scanExclusionService.getExcludedApps(
        widget.childId,
      );
      _scanExcludedAppsCache = excluded.map((e) => e.packageName).toSet();
      _scanExcludedAppNamesCache = excluded
          .map((e) => e.appName.trim().toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet();
      _lastExcludedAppsUpdate = now;
      debugPrint(
        'Updated scan exclusions cache: ${_scanExcludedAppsCache.length} apps',
      );
      await _syncScanExclusionsToNative(_scanExcludedAppsCache);
    } catch (e) {
      debugPrint('Error updating scan exclusions cache: $e');
    }
  }

  void _listenForScanExclusions(String childId) {
    _scanExclusionsSubscription?.cancel();
    _scanExclusionsSubscription = _scanExclusionService
        .watchExcludedApps(childId)
        .listen(
          (excludedApps) async {
            _scanExcludedAppsCache = excludedApps
                .map((e) => e.packageName)
                .where((packageName) => packageName.isNotEmpty)
                .toSet();
            _scanExcludedAppNamesCache = excludedApps
                .map((e) => e.appName.trim().toLowerCase())
                .where((name) => name.isNotEmpty)
                .toSet();
            _lastExcludedAppsUpdate = DateTime.now();
            debugPrint(
              '_listenForScanExclusions: synced ${_scanExcludedAppsCache.length} package exclusions and ${_scanExcludedAppNamesCache.length} app-name exclusions',
            );
            await _syncScanExclusionsToNative(_scanExcludedAppsCache);
          },
          onError: (error) {
            debugPrint('_listenForScanExclusions: stream error: $error');
          },
        );
  }

  Future<void> _syncScanExclusionsToNative(Set<String> packageNames) async {
    try {
      await screenChannel.invokeMethod('updateNativeScanExclusions', {
        'packages': packageNames.toList(growable: false),
      });
    } catch (e) {
      debugPrint('_syncScanExclusionsToNative: Failed to sync exclusions: $e');
    }
  }

  Future<void> _syncNativeChildContext() async {
    try {
      await screenChannel.invokeMethod('updateNativeChildContext', {
        'childId': widget.childId,
        'parentId': _parentId,
      });
    } catch (e) {
      debugPrint('_syncNativeChildContext: Failed to sync child context: $e');
    }
  }

  Future<bool> _isProjectionActive() async {
    try {
      final active = await screenChannel.invokeMethod<bool>(
        'isProjectionActive',
      );
      return active == true;
    } catch (_) {
      // If the native method is unavailable, avoid false down reports.
      return _hasPermission;
    }
  }

  Future<bool> _isNativeScanServiceRunning() async {
    try {
      final running = await screenChannel.invokeMethod<bool>(
        'isNativeScanServiceRunning',
      );
      return running == true;
    } catch (_) {
      return false;
    }
  }

  void _handleGroomingAppChange(String packageName) {
    if (_groomingEnabledPackages.contains(packageName)) {
      _activeGroomingPackage = packageName;
      unawaited(_warmUpGroomingModel());
      return;
    }

    if (_activeGroomingPackage == packageName) {
      _activeGroomingPackage = null;
    }
  }

  Future<void> _warmUpGroomingModel() async {
    try {
      await _safetyModelService.initialize();
    } catch (e) {
      debugPrint('_warmUpGroomingModel: grooming model unavailable: $e');
    }
  }

  Future<void> _handleAppChange(String packageName) async {
    // Check app-specific time limits first
    await _checkAppTimeLimitExceeded(packageName);

    final isGaming = _gamingAppsService.isKnownGamingApp(packageName);
    if (isGaming && !_isGamingSession) {
      _isGamingSession = true;
      _scanTimer?.cancel();
      _scanTimer = null;
      return;
    }

    if (!isGaming && _isGamingSession) {
      _isGamingSession = false;
      _startScanning();
    }

    if (_shouldScanContent()) {
      unawaited(_performScan());
    }
  }

  Future<void> _initializeProtection() async {
    if (_isInitializing || !mounted) return;
    if (!_shouldBeMonitoring()) return;

    setState(() => _isInitializing = true);

    try {
      // Check overlay permission first
      final state = await PermissionService.checkAllPermissions();
      if (state.overlay != PermissionStatus.granted) {
        setState(() => _isInitializing = false);
        return;
      }

      // Check if AccessibilityService is enabled for instant app blocking
      try {
        final isAccessibilityEnabled = await screenChannel.invokeMethod(
          'checkAccessibilityService',
        );
        debugPrint('AccessibilityService enabled: $isAccessibilityEnabled');

        if (isAccessibilityEnabled != true && mounted) {
          // Show warning to user
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'For instant app blocking, please enable ChildSafe Accessibility Service in Settings > Accessibility',
                maxLines: 3,
              ),
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () async {
                  // Open accessibility settings
                  try {
                    await screenChannel.invokeMethod(
                      'openAccessibilitySettings',
                    );
                  } catch (e) {
                    debugPrint('Error opening accessibility settings: $e');
                  }
                },
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error checking accessibility service: $e');
      }

      // Request media projection permission and start service through MainActivity
      // This will trigger the permission dialog and start the MediaProjectionService
      try {
        await screenChannel.invokeMethod('startService');
        final projectionActive = await _isProjectionActive();
        final nativeRunning = await _isNativeScanServiceRunning();
        _hasPermission = projectionActive || nativeRunning;
        if (!projectionActive) {
          if (nativeRunning) {
            await _publishScanRuntimeStatus(
              isRunning: true,
              expectedRunning: _shouldBeMonitoring(),
              reason: 'active',
            );
          } else {
            await _publishScanRuntimeStatus(
              isRunning: false,
              expectedRunning: _shouldBeMonitoring(),
              reason: 'projection_permission_required',
            );
          }
        } else {
          _lastProjectionRecoveryAttempt = null;
          debugPrint('Media projection service started and projection active');
        }
      } catch (e) {
        debugPrint('Error starting media projection service: $e');
        _hasPermission = false;
      }

      if (!_hasPermission || !mounted) {
        setState(() => _isInitializing = false);
        return;
      }

      // Initialize NSFW detection with error handling
      try {
        if (_activeSettings.pornFilterEnabled) {
          await _nsfwService.initialize();
        }
      } catch (e) {
        debugPrint('Error initializing NSFW detection: $e');
        // Continue without NSFW detection
      }

      // Initialize violence detection with error handling
      try {
        if (_activeSettings.violenceFilterEnabled) {
          await _weaponGoreService.initialize();
        }
      } catch (e) {
        debugPrint('Error initializing violence detection: $e');
        // Continue without violence detection
      }

      // Start monitoring
      if (mounted && _hasPermission) {
        await _startMonitoring();
      }
    } catch (e) {
      debugPrint('Error initializing protection: $e');
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  Future<void> _startMonitoring() async {
    if (_isMonitoring) return;

    // Start native service for screen capture
    try {
      await screenChannel.invokeMethod('startService');
    } catch (e) {
      debugPrint('Error starting screen service: $e');
      return;
    }

    final projectionActive = await _isProjectionActive();
    if (!projectionActive) {
      _hasPermission = false;
      await _publishScanRuntimeStatus(
        isRunning: false,
        expectedRunning: _shouldBeMonitoring(),
        reason: 'projection_inactive',
      );
      return;
    }
    _hasPermission = true;

    // Start screen monitor service
    final success = await _screenMonitor.startService();
    if (success && mounted) {
      setState(() => _isMonitoring = true);
      _updateIsActive(true);
      _startScanning();
      _startAppLimitWatcher();
      await _publishScanRuntimeStatus(
        isRunning: true,
        expectedRunning: _shouldBeMonitoring(),
        reason: 'active',
      );
    } else {
      final nativeRunning = await _isNativeScanServiceRunning();
      if (nativeRunning) {
        _hasPermission = true;
        await _publishScanRuntimeStatus(
          isRunning: true,
          expectedRunning: _shouldBeMonitoring(),
          reason: 'active',
        );
      } else {
        await _publishScanRuntimeStatus(
          isRunning: false,
          expectedRunning: _shouldBeMonitoring(),
          reason: 'start_failed',
        );
      }
    }
  }

  Future<void> _stopMonitoring() async {
    if (!_isMonitoring) return;

    // Cancel timer
    _scanTimer?.cancel();
    _scanTimer = null;
    _appLimitWatchTimer?.cancel();
    _appLimitWatchTimer = null;

    _appBlockShieldActive = false;
    _nsfwShieldActive = false;
    _screenTimeShieldActive = false;
    _appTimeLimitShieldActive = false;
    _isGamingSession = false;

    // Stop native service
    try {
      await screenChannel.invokeMethod('stopService', {'force': true});
    } catch (e) {
      debugPrint('Error stopping screen service: $e');
    }

    // Hide shield if shown
    try {
      await screenChannel.invokeMethod('toggleShield', {'show': false});
    } catch (e) {
      debugPrint('Error hiding shield: $e');
    }

    if (mounted) {
      setState(() => _isMonitoring = false);
    }

    _updateIsActive(false);
    await _publishScanRuntimeStatus(
      isRunning: false,
      expectedRunning: false,
      reason: 'stopped',
    );
  }

  void _startScanning() {
    if (_scanTimer?.isActive == true) return;
    if (!_shouldScanContent() || !_hasPermission) return;

    _scanTimer = Timer.periodic(
      _activeSettings.scanInterval,
      (_) => _performScan(),
    );
  }

  void _restartScanning() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _startScanning();
  }

  void _startAppLimitWatcher() {
    _appLimitWatchTimer?.cancel();
    if (Platform.isAndroid) {
      return;
    }
    _appLimitWatchTimer = Timer.periodic(_appLimitWatchInterval, (_) {
      if (!mounted || !_isMonitoring || !_hasPermission) {
        return;
      }
      unawaited(_checkActiveAppTimeLimitInstant());
    });
    unawaited(_checkActiveAppTimeLimitInstant());
  }

  Future<void> _checkActiveAppTimeLimitInstant() async {
    if (_appLimitCheckInProgress) {
      return;
    }
    if (_appBlockShieldActive || _nsfwShieldActive || _screenTimeShieldActive) {
      return;
    }

    _appLimitCheckInProgress = true;
    try {
      final packageName = await _getForegroundApp();
      if (packageName == null || packageName.isEmpty) {
        return;
      }
      await _checkAppTimeLimitExceeded(packageName);
    } finally {
      _appLimitCheckInProgress = false;
    }
  }

  Future<void> _performScan() async {
    if (!mounted || !_shouldScanContent() || !_hasPermission) return;

    // Check screen time exceeded first
    await _checkScreenTimeExceeded();

    // Skip scanning if a shield is already active (prevents interference)
    if (_appBlockShieldActive ||
        _nsfwShieldActive ||
        _screenTimeShieldActive ||
        _appTimeLimitShieldActive) {
      debugPrint('_performScan: Shield active, skipping scan');
      return;
    }

    if (_scanInProgress) {
      debugPrint('_performScan: Scan already running, skipping');
      return;
    }

    _scanInProgress = true;

    try {
      final packageName = await _getForegroundApp();

      // Prevent immediate re-trigger loops right after child dismisses shield.
      final now = DateTime.now();
      if (_lastShieldDismissalTime != null &&
          now.difference(_lastShieldDismissalTime!).inSeconds < 4) {
        debugPrint('_performScan: In post-dismiss cooldown, skipping scan');
        return;
      }

      // Skip noisy system surfaces that commonly cause false positives
      // (home launcher, system UI, keyboard overlays).
      if (_shouldSkipPackageForContentScan(packageName)) {
        debugPrint('_performScan: Skipping system/noise package: $packageName');
        return;
      }

      if (Platform.isAndroid &&
          packageName != null &&
          _blockedAppsByPackage.containsKey(packageName)) {
        debugPrint(
          '_performScan: Android blocked app $packageName handled by native block screen; skipping content scan',
        );
        return;
      }

      // Update exclusions cache periodically
      await _updateScanExclusionsCache();

      // IMPORTANT: Check if app is excluded from scanning
      if (packageName != null && _scanExcludedAppsCache.contains(packageName)) {
        debugPrint(
          '_performScan: Scanner stopped for excluded package from Firestore: $packageName',
        );
        return;
      }

      if (packageName != null && _scanExcludedAppNamesCache.isNotEmpty) {
        final appName = (await _appNameResolver.getAppName(
          packageName,
        )).trim().toLowerCase();
        if (appName.isNotEmpty &&
            _scanExcludedAppNamesCache.contains(appName)) {
          debugPrint(
            '_performScan: Scanner stopped for excluded app name from Firestore: $appName ($packageName)',
          );
          await _syncScanExclusionsToNative(_scanExcludedAppsCache);
          return;
        }
      }

      // Check if app is blocked FIRST - always do this check
      final isBlocked = await _checkIfAppBlocked(packageName);
      if (isBlocked) {
        debugPrint(
          '_performScan: App is blocked; native shield path already handled',
        );
        return;
      }

      if (!_activeSettings.pornFilterEnabled &&
          !_activeSettings.violenceFilterEnabled) {
        return;
      }

      // Don't run NSFW if an app block alert is showing
      if (_appBlockAlertShowing) {
        debugPrint(
          '_performScan: App block alert showing, skipping NSFW detection',
        );
        return;
      }

      debugPrint('_performScan: Starting scan...');
      final filePath = await screenChannel.invokeMethod<String>(
        'captureScreen',
      );
      if (filePath == null) {
        debugPrint('_performScan: No file path returned from screen capture');
        _attemptProjectionRecovery();
        return;
      }
      debugPrint('_performScan: Captured screen to: $filePath');

      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('_performScan: File does not exist: $filePath');
        return;
      }

      bool shouldAlert = false;
      double? nsfwScore;
      WeaponGoreResult? violenceResult;

      if (_activeSettings.violenceFilterEnabled) {
        debugPrint('_performScan: Running weapon/gore detection...');
        violenceResult = await _weaponGoreService.detect(file);
        debugPrint(
          '_performScan: Weapon/gore result: ${violenceResult.label} (${violenceResult.confidence})',
        );
        if (violenceResult.label.isUnsafe) {
          shouldAlert = true;
          debugPrint(
            '_performScan: Violence detected! Result: ${violenceResult.label}',
          );
        } else {
          debugPrint('_performScan: No violence detected');
        }
      }

      if (!shouldAlert && _activeSettings.pornFilterEnabled) {
        debugPrint('_performScan: Running NSFW detection...');
        nsfwScore = await _nsfwService.detectNSFW(file);
        if (nsfwScore != null && nsfwScore > 0.7) {
          shouldAlert = true;
        }
      }

      if (shouldAlert && mounted) {
        debugPrint('_performScan: Foreground app: $packageName');

        if (packageName != null &&
            violenceResult != null &&
            violenceResult.label.isUnsafe) {
          final appName = await _appNameResolver.getAppName(packageName);
          final detectionType = violenceResult.label == WeaponGoreLabel.weapon
              ? DetectionType.gun
              : DetectionType.gore;
          try {
            await _detectionsService.logDetection(
              packageName: packageName,
              appName: appName,
              detectionType: detectionType,
              confidenceScore: violenceResult.confidence,
              metadata: {
                'violenceLabel': violenceResult.label.name,
                'violenceScore': violenceResult.confidence,
                'violenceScores': violenceResult.scores,
              },
            );
            await _tomatoPlantService.deductWater(widget.childId);
          } catch (_) {
            // Ignore logging errors to avoid blocking UI
          }
        } else if (packageName != null && _activeSettings.pornFilterEnabled) {
          final appName = await _appNameResolver.getAppName(packageName);
          try {
            await _detectionsService.logDetection(
              packageName: packageName,
              appName: appName,
              detectionType: DetectionType.nsfw,
              confidenceScore: nsfwScore ?? 0.0,
              metadata: {'nsfwScore': nsfwScore},
            );
            await _tomatoPlantService.deductWater(widget.childId);
          } catch (_) {
            // Ignore logging errors to avoid blocking UI
          }
        }

        _nsfwShieldActive = true;
        try {
          final shieldType =
              violenceResult != null && violenceResult.label.isUnsafe
              ? (violenceResult.label == WeaponGoreLabel.weapon
                    ? 'weapon'
                    : 'gore')
              : 'nsfw';

          await screenChannel.invokeMethod('toggleShield', {
            'show': true,
            'type': shieldType,
          });
        } catch (e) {
          debugPrint('_performScan: Error loading NSFW image: $e');
          await screenChannel.invokeMethod('toggleShield', {
            'show': true,
            'type': 'nsfw',
          });
        }
        _showContentAlert();
      }

      // Clean up
      try {
        await file.delete();
        debugPrint('_performScan: Temp file deleted');
      } catch (e) {
        debugPrint('_performScan: Error deleting temp file: $e');
      }
    } catch (e, stackTrace) {
      debugPrint('_performScan: ERROR during scan: $e');
      debugPrint('_performScan: Stack trace: $stackTrace');
    } finally {
      _scanInProgress = false;
    }
  }

  void _attemptProjectionRecovery() {
    final now = DateTime.now();
    if (_lastProjectionRecoveryAttempt != null &&
        now.difference(_lastProjectionRecoveryAttempt!).inSeconds < 8) {
      return;
    }

    _lastProjectionRecoveryAttempt = now;

    Future<void>(() async {
      try {
        debugPrint(
          '_attemptProjectionRecovery: requesting native startService recovery',
        );
        await screenChannel.invokeMethod('startService');
      } catch (e) {
        debugPrint('_attemptProjectionRecovery: recovery failed: $e');
      }
    });
  }

  Future<String?> _getForegroundApp() async {
    try {
      return await screenChannel.invokeMethod<String>('getForegroundApp');
    } catch (e) {
      return null;
    }
  }

  bool _shouldSkipPackageForContentScan(String? packageName) {
    if (packageName == null || packageName.isEmpty) {
      return true;
    }

    const exactSkips = {
      'com.example.child_safe_app',
      'com.android.systemui',
      'com.android.launcher3',
    };

    if (exactSkips.contains(packageName)) {
      return true;
    }

    final lower = packageName.toLowerCase();
    if (lower.contains('swiftkey') ||
        lower.contains('gboard') ||
        lower.contains('inputmethod') ||
        lower.contains('keyboard') ||
        lower.contains('launcher')) {
      return true;
    }

    return false;
  }

  void _showContentAlert() {
    // Don't show NSFW alert popup - only the native shield will be displayed
    // The native shield is already shown in _performScan() before calling this
    debugPrint(
      '_showContentAlert: Inappropriate content detected - native shield active',
    );

    // Set flag to prevent multiple detections
    _nsfwAlertShowing = true;

    // No popup dialog shown - user will only see the native shield screen
    return;
  }

  Future<void> _updateIsActive(bool active) async {
    if (_parentId == null) return;

    try {
      await _protectionStatusService.setIsActive(
        parentId: _parentId!,
        childId: widget.childId,
        enabled: active,
      );
    } catch (e) {
      debugPrint('Error updating isActive status: $e');
    }
  }

  Future<void> _checkScreenTimeExceeded() async {
    final totalAllowance = _screenTimeAllowanceMinutes + _bonusMinutes;
    final elapsedSeconds = await _getElapsedScreenTimeSeconds();

    final totalAllowanceSeconds = (totalAllowance * 60).round().clamp(
      0,
      1 << 30,
    );
    final remainingSeconds = totalAllowanceSeconds - elapsedSeconds;

    debugPrint(
      'Screen time check: Elapsed=${elapsedSeconds}s, TotalAllowance=${totalAllowanceSeconds}s, Remaining=${remainingSeconds}s',
    );

    // If no seconds remain (including zero), show shield.
    if (remainingSeconds <= 0 && !_screenTimeShieldActive) {
      debugPrint('Screen time exceeded! Showing shield...');
      await _setScreenTimeExceededShield(true);
    } else if (remainingSeconds > 0 && _screenTimeShieldActive) {
      // If back within limit, hide shield
      debugPrint('Screen time within limit, hiding shield...');
      await _setScreenTimeExceededShield(false);
    }
  }

  Future<int> _currentDailyRemainingSeconds() async {
    final totalAllowanceSeconds =
        ((_screenTimeAllowanceMinutes + _bonusMinutes) * 60).round().clamp(
          0,
          1 << 30,
        );
    final elapsedSeconds = await _getElapsedScreenTimeSeconds();
    return totalAllowanceSeconds - elapsedSeconds;
  }

  Future<int> _getElapsedScreenTimeSeconds() async {
    final now = DateTime.now();
    final effectiveDayStart =
        _screenTimeDayStart ?? DateTime(now.year, now.month, now.day);

    var elapsedSeconds = now.difference(effectiveDayStart).inSeconds;
    try {
      final liveTotalSeconds = await screenChannel.invokeMethod<dynamic>(
        'getTodayTotalUsageSeconds',
      );
      final parsed = (liveTotalSeconds as num?)?.toInt();
      if (parsed != null && parsed >= 0) {
        elapsedSeconds = parsed;
      }
    } catch (e) {
      debugPrint(
        '_getElapsedScreenTimeSeconds: live total usage unavailable, using fallback elapsed clock: $e',
      );
    }
    return elapsedSeconds;
  }

  Future<void> _checkAppTimeLimitExceeded(String packageName) async {
    if (Platform.isAndroid) {
      return;
    }

    // Check if this app has a time limit
    final limitSeconds = _appTimeLimits[packageName];
    if (limitSeconds == null) return;

    try {
      var appName = 'Unknown App';
      var usedSeconds = 0;
      var usageResolved = false;

      // Fast path: direct native query for current-day usage seconds of this package.
      try {
        final liveUsageSeconds = await screenChannel.invokeMethod<dynamic>(
          'getTodayUsageSecondsForPackage',
          {'packageName': packageName},
        );
        final parsedLiveSeconds = (liveUsageSeconds as num?)?.toInt();
        if (parsedLiveSeconds != null && parsedLiveSeconds >= 0) {
          usedSeconds = parsedLiveSeconds;
          appName = await _appNameResolver.getAppName(packageName);
          usageResolved = true;
        }
      } catch (e) {
        debugPrint(
          '_checkAppTimeLimitExceeded: Live native usage read failed, will fallback: $e',
        );
      }

      // Primary source: Android native usage snapshot (today-only minutesToday)
      if (!usageResolved) {
        try {
          final nativeUsageData = await screenChannel.invokeMethod<dynamic>(
            'getAppUsageData',
          );
          if (nativeUsageData is Map) {
            final appsData = nativeUsageData['apps'];
            if (appsData is List) {
              for (final appEntry in appsData) {
                if (appEntry is! Map) continue;
                final package = appEntry['packageName'] as String?;
                if (package != packageName) continue;

                appName = appEntry['appName'] as String? ?? 'Unknown App';
                final minutesToday =
                    (appEntry['minutesToday'] as num?)?.toInt() ?? 0;
                usedSeconds = minutesToday * 60;
                usageResolved = true;
                break;
              }
            }
          }
        } catch (e) {
          debugPrint(
            '_checkAppTimeLimitExceeded: Native usage read failed, will fallback to Firestore: $e',
          );
        }
      }

      // Fallback source: Firestore cache (minutesToday only)
      if (!usageResolved) {
        final usageDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.childId)
            .collection('appUsage')
            .doc('current')
            .get();

        if (usageDoc.exists) {
          final usageData = usageDoc.data() as Map<String, dynamic>?;
          final appsData = usageData?['apps'] as List<dynamic>? ?? const [];

          for (final appEntry in appsData) {
            if (appEntry is! Map<String, dynamic>) continue;
            final package = appEntry['packageName'] as String?;
            if (package != packageName) continue;

            appName = appEntry['appName'] as String? ?? 'Unknown App';
            final minutesToday =
                (appEntry['minutesToday'] as num?)?.toInt() ?? 0;
            usedSeconds = minutesToday * 60;
            usageResolved = true;
            break;
          }
        }
      }

      if (!usageResolved) {
        debugPrint(
          'App time limit check: No daily usage found for $packageName yet.',
        );
        return;
      }

      debugPrint(
        'App time limit check (today-only): $appName - Used=${usedSeconds}s, Limit=${limitSeconds}s',
      );

      // If exceeded and shield not already active, show app time limit shield
      if (usedSeconds >= limitSeconds && !_appTimeLimitShieldActive) {
        debugPrint('App time limit exceeded for $appName! Showing shield...');
        await _setAppTimeLimitExceededShield(true, appName, limitSeconds);
      } else if (usedSeconds < limitSeconds && _appTimeLimitShieldActive) {
        // If back within limit, hide shield
        debugPrint(
          'App time limit within limit for $appName, hiding shield...',
        );
        await _setAppTimeLimitExceededShield(false, appName, limitSeconds);
      }
    } catch (e) {
      debugPrint(
        '_checkAppTimeLimitExceeded: Error checking app time limit: $e',
      );
    }
  }

  Future<void> _setScreenTimeExceededShield(
    bool show, {
    bool force = false,
  }) async {
    if (!show && !_screenTimeShieldActive && !force) return;

    _screenTimeShieldActive = show;

    if (show) {
      _screenTimeAlertShowing = true;
      _appBlockAlertShowing = false;
      _nsfwAlertShowing = false;
    } else {
      _screenTimeAlertShowing = false;
    }

    if (!show) {
      try {
        await screenChannel.invokeMethod('toggleShield', {
          'show': false,
          'type': 'screen_time',
        });
        await screenChannel.invokeMethod('hideNativeServiceShield');
      } catch (e) {
        debugPrint('_setScreenTimeExceededShield: Failed to hide shield: $e');
      }
      return;
    }

    try {
      // Load the image as base64
      final imageBytes = await rootBundle.load(
        'assets/images/screenTimeExceeded.png',
      );
      final base64Image = base64.encode(imageBytes.buffer.asUint8List());

      await screenChannel.invokeMethod('toggleShield', {
        'show': show,
        'type': 'screen_time',
        'imageBase64': base64Image,
      });
    } catch (e) {
      debugPrint('_setScreenTimeExceededShield: Error loading image: $e');
      // Shield toggle failed, try without custom image
      try {
        await screenChannel.invokeMethod('toggleShield', {
          'show': show,
          'type': 'screen_time',
        });
      } catch (e2) {
        debugPrint(
          '_setScreenTimeExceededShield: Failed to toggle shield: $e2',
        );
      }
    }
  }

  Future<void> _setAppTimeLimitExceededShield(
    bool show,
    String appName,
    int limitSeconds,
  ) async {
    if (!show && !_appTimeLimitShieldActive) return;

    _appTimeLimitShieldActive = show;

    if (show) {
      _screenTimeAlertShowing = true;
      _appBlockAlertShowing = false;
      _nsfwAlertShowing = false;
    } else {
      _screenTimeAlertShowing = false;
    }

    if (!show) {
      try {
        await screenChannel.invokeMethod('toggleShield', {
          'show': false,
          'type': 'app_time_limit',
        });
        await screenChannel.invokeMethod('hideNativeServiceShield');
      } catch (e) {
        debugPrint('_setAppTimeLimitExceededShield: Failed to hide shield: $e');
      }
      return;
    }

    try {
      await screenChannel.invokeMethod('toggleShield', {
        'show': show,
        'type': 'app_time_limit',
      });
    } catch (e) {
      debugPrint('_setAppTimeLimitExceededShield: Failed to toggle shield: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanTimer?.cancel();
    _protectionWatchdogTimer?.cancel();
    _appLimitWatchTimer?.cancel();
    _appBlockAlertTimer?.cancel();
    _nsfwAlertTimer?.cancel();
    _protectionStatusSubscription?.cancel();
    _blockedAppsSubscription?.cancel();
    _filterSettingsSubscription?.cancel();
    _filterSettingsReconnectTimer?.cancel();
    _appTimeLimitsSubscription?.cancel();
    _groomingAppsSubscription?.cancel();
    _scanExclusionsSubscription?.cancel();
    _nativeRecoverySubscription?.cancel();
    detectorChannel.setMethodCallHandler(null);
    _nsfwService.dispose();
    _weaponGoreService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_activeSettings.anyEnabled) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        backgroundColor: Colors.transparent,
        valueColor: AlwaysStoppedAnimation<Color>(
          _isMonitoring
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
        ),
        value: 1.0,
      ),
    );
  }
}
