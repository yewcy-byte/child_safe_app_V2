import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../shared/shared.dart';
import '../auth/login_page.dart';
import 'pages/pages.dart';
import 'pages/detections_page.dart';
import '../../models/filter_settings_model.dart';
import '../../services/filter_settings_service.dart';
import '../../services/permission_service.dart';
import '../../services/usage_tracking_coordinator.dart';
import '../../services/location_tracking_service.dart';
import '../../services/background_protection_service.dart';
import '../../services/pairing_service.dart';
import 'child_protection_runner.dart';

class ChildDashboard extends StatefulWidget {
  const ChildDashboard({super.key});

  @override
  State<ChildDashboard> createState() => _ChildDashboardState();
}

class _ChildDashboardState extends State<ChildDashboard>
  with WidgetsBindingObserver {
  int _index = 0; // Garden tab is index 0 (default)

  late final List<Widget> _pages;
  final FilterSettingsService _filterSettingsService = FilterSettingsService();
  final UsageTrackingCoordinator _usageTracking = UsageTrackingCoordinator();
  final LocationTrackingService _locationTracking = LocationTrackingService();
  final PairingService _pairingService = PairingService();
  final TextEditingController _pairingCodeController = TextEditingController();

  Stream<FilterSettings>? _settingsStream;
  String? _parentId;
  String? _childId;
  bool _isResolvingParent = true;
  bool _isLinkingParent = false;
  bool _hasStartedUsageTracking = false;
  bool _hasStartedLocationTracking = false;
  PermissionState? _permissionState;
  bool _isCheckingPermissions = true;
  bool _permissionGateCompleted = false;
  StreamSubscription<PermissionState>? _permissionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PermissionService.initialize();
    _refreshPermissions();
    _permissionSubscription =
        PermissionService.permissionStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _permissionState = state;
          if (!state.allGranted) {
            _permissionGateCompleted = false;
          }
        });
      }
    });
    _pages = [
      GardenPage(
        onProfileButtonPressed: _signOut,
        backgroundImagePath: 'assets/images/gardenBackground.png',
      ),
      const MarketPage(),
      StatusPage(onProfileButtonPressed: _signOut),
      DetectionsPage(onProfileButtonPressed: _signOut),
    ];

    _childId = FirebaseAuth.instance.currentUser?.uid;
    if (_childId != null) {
      _loadParentIdAndSettings();
    }
  }

  Future<void> _loadParentIdAndSettings() async {
    final userId = _childId;
    if (userId == null || !mounted) return;

    setState(() {
      _isResolvingParent = true;
    });

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      var parentId = userDoc.data()?['parentId'] as String?;

      if (parentId == null) {
        final parentsQuery = await FirebaseFirestore.instance
            .collectionGroup('children')
            .where('deviceId', isEqualTo: userId)
            .limit(1)
            .get();

        if (parentsQuery.docs.isNotEmpty) {
          final parentDocRef = parentsQuery.docs.first.reference.parent.parent;
          if (parentDocRef != null) {
            parentId = parentDocRef.id;
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .set({'parentId': parentId}, SetOptions(merge: true));
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _parentId = parentId;
        if (parentId != null) {
          _settingsStream = _filterSettingsService.watchUserSettings(
            parentId,
            userId,
          );
        } else {
          _settingsStream = const Stream.empty();
        }
      });

      // Ensure background protection services are active
      // This keeps scanning running even if app is closed/removed from recents
      await BackgroundProtectionService.startBackgroundProtection();
      await BackgroundProtectionService.ensureForegroundService();

      // Start usage tracking after a short delay
      if (!_hasStartedUsageTracking) {
        _hasStartedUsageTracking = true;
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            _usageTracking.startTracking();
          }
        });
      }

      if (!_hasStartedLocationTracking) {
        _hasStartedLocationTracking = true;
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _startLocationTracking();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _settingsStream = const Stream.empty();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingParent = false;
        });
      }
    }
  }

  void _showLinkParentDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Link Parent',
            style: AppTextStyles.titleLarge(dialogContext),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter the 6-digit code from your parent.',
                style: AppTextStyles.bodyMedium(dialogContext),
              ),
              AppSpacing.gapMd,
              TextField(
                controller: _pairingCodeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Pairing code',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _isLinkingParent
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: AppTextStyles.labelLarge(dialogContext),
              ),
            ),
            FilledButton(
              onPressed: _isLinkingParent
                  ? null
                  : () => _linkParent(dialogContext),
              child: Text(
                _isLinkingParent ? 'Linking...' : 'Link Parent',
                style: AppTextStyles.labelLarge(dialogContext),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _linkParent(BuildContext dialogContext) async {
    final code = _pairingCodeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit code.')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user is currently signed in.')),
      );
      return;
    }

    final childName = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? 'Child');

    setState(() => _isLinkingParent = true);
    try {
      final success = await _pairingService.pairChildWithCode(
        code: code,
        childId: user.uid,
        childName: childName,
        childPhotoUrl: user.photoURL,
      );

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid or expired code.')),
        );
        return;
      }

      if (!mounted) return;
      _pairingCodeController.clear();
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }

      await _loadParentIdAndSettings();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to link parent. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLinkingParent = false);
      }
    }
  }

  Widget _buildParentLinkGate() {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: AppSpacing.paddingLg,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.link_outlined,
                      size: AppSpacing.xl,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    AppSpacing.gapMd,
                    Text(
                      'Link your parent account',
                      style: AppTextStyles.headlineSmall(context).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.gapSm,
                    Text(
                      'You need to link a parent account before using Garden and protection features.',
                      style: AppTextStyles.bodyMedium(context).copyWith(
                        color: AppColors.onSurfaceVariant(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.gapLg,
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isLinkingParent ? null : _showLinkParentDialog,
                        icon: const Icon(Icons.qr_code_2_outlined),
                        label: const Text('Link Parent Account'),
                      ),
                    ),
                    AppSpacing.gapSm,
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isResolvingParent
                            ? null
                            : () => _loadParentIdAndSettings(),
                        child: const Text('I already linked, refresh'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions();
      // Re-ensure background services when app resumes
      BackgroundProtectionService.ensureForegroundService();
    } else if (state == AppLifecycleState.paused || 
               state == AppLifecycleState.detached) {
      // App was closed or sent to background
      // Native services will continue scanning
      BackgroundProtectionService.handleAppRemovedFromRecents();
    }
  }

  Future<void> _refreshPermissions() async {
    setState(() => _isCheckingPermissions = true);
    final state = await PermissionService.checkAllPermissions();
    if (mounted) {
      setState(() {
        _permissionState = state;
        _isCheckingPermissions = false;
        if (!state.allGranted) {
          _permissionGateCompleted = false;
        }
      });
    }
  }

  Future<void> _startLocationTracking() async {
    try {
      debugPrint('ChildDashboard: Starting location tracking');

      // Check if location service is enabled
      final serviceEnabled = await _locationTracking.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('ChildDashboard: Location service is disabled');
        return;
      }

      // Check and request permissions
      var permission = await _locationTracking.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await _locationTracking.requestPermission();
      }

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        debugPrint(
          'ChildDashboard: Location permission not granted: $permission',
        );
        return;
      }

      final ignoringBatteryOptimizations =
          await _locationTracking.isIgnoringBatteryOptimizations();
      if (!ignoringBatteryOptimizations) {
        await _locationTracking.requestIgnoreBatteryOptimizations();
      }

      // Start background location service
      final started = await _locationTracking.startBackgroundService();
      debugPrint(
        'ChildDashboard: Background location service started: $started',
      );

      if (started) {
        // Also start foreground tracking for more frequent updates
        await _locationTracking.startTracking();
        debugPrint('ChildDashboard: Foreground location tracking started');
      }
    } catch (e) {
      debugPrint('ChildDashboard: Error starting location tracking: $e');
    }
  }

  void _showUsageAccessInstructions() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Enable Usage Access',
          style: AppTextStyles.titleLarge(dialogContext),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To enable Usage Access:',
              style: AppTextStyles.bodyMedium(dialogContext),
            ),
            AppSpacing.gapSm,
            Text(
              '1. Find "Guarden" in the list',
              style: AppTextStyles.bodySmall(dialogContext),
            ),
            Text(
              '2. Tap on it',
              style: AppTextStyles.bodySmall(dialogContext),
            ),
            Text(
              '3. Turn on "Allow usage tracking"',
              style: AppTextStyles.bodySmall(dialogContext),
            ),
            AppSpacing.gapSm,
            Text(
              'Then return to this app.',
              style: AppTextStyles.bodySmall(dialogContext),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              PermissionService.requestUsageStatsPermission();
            },
            child: Text(
              'OK',
              style: AppTextStyles.labelLarge(dialogContext),
            ),
          ),
        ],
      ),
    );
  }

  void _showAccessibilityInstructions() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Enable Accessibility',
          style: AppTextStyles.titleLarge(dialogContext),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To enable Accessibility:',
              style: AppTextStyles.bodyMedium(dialogContext),
            ),
            AppSpacing.gapSm,
            Text(
              '1. Open Accessibility settings',
              style: AppTextStyles.bodySmall(dialogContext),
            ),
            Text(
              '2. Find "Guarden"',
              style: AppTextStyles.bodySmall(dialogContext),
            ),
            Text(
              '3. Turn on the service',
              style: AppTextStyles.bodySmall(dialogContext),
            ),
            AppSpacing.gapSm,
            Text(
              'Then return to this app.',
              style: AppTextStyles.bodySmall(dialogContext),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              PermissionService.requestAccessibilityPermission();
            },
            child: Text(
              'OK',
              style: AppTextStyles.labelLarge(dialogContext),
            ),
          ),
        ],
      ),
    );
  }

  void _showBatteryManagementInstructions() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Background Power Management',
          style: AppTextStyles.titleLarge(dialogContext),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To keep Guarden running in background:',
              style: AppTextStyles.bodyMedium(dialogContext),
            ),
            AppSpacing.gapSm,
            Text(
              '1. Open Battery settings',
              style: AppTextStyles.bodySmall(dialogContext),
            ),
            Text(
              '2. Open Background power consumption management',
              style: AppTextStyles.bodySmall(dialogContext),
            ),
            Text(
              '3. Find Guarden app',
              style: AppTextStyles.bodySmall(dialogContext),
            ),
            Text(
              '4. Set to "Don\'t restrict background usage"',
              style: AppTextStyles.bodySmall(dialogContext),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              PermissionService.openBatteryBackgroundManagementSettings();
            },
            child: Text(
              'OPEN SETTINGS',
              style: AppTextStyles.labelLarge(dialogContext),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildPermissionCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onGrant,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Row(
          children: [
            Container(
              padding: AppSpacing.paddingSm,
              decoration: BoxDecoration(
                color: isGranted
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isGranted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            AppSpacing.gapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.titleSmall(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    description,
                    style: AppTextStyles.bodySmall(context).copyWith(
                      color: AppColors.onSurfaceVariant(context),
                    ),
                  ),
                ],
              ),
            ),
            if (isGranted)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
              )
            else
              FilledButton.tonal(
                onPressed: onGrant,
                child: const Text('GRANT'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsGate(PermissionState state) {
    final theme = Theme.of(context);
    final grantedCount =
        [
          state.usageStats,
          state.accessibility,
          state.overlay,
          state.notifications,
        ].where((status) => status == PermissionStatus.granted).length;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: AppSpacing.paddingLg,
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Permissions required',
                style: AppTextStyles.headlineSmall(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              AppSpacing.gapSm,
              Text(
                'Enable these permissions to activate full protection.',
                style: AppTextStyles.bodyMedium(context).copyWith(
                  color: AppColors.onSurfaceVariant(context),
                ),
              ),
              AppSpacing.gapMd,
              Card(
                child: Padding(
                  padding: AppSpacing.paddingMd,
                  child: Row(
                    children: [
                      Container(
                        padding: AppSpacing.paddingSm,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.shield_outlined,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      AppSpacing.gapMd,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$grantedCount / 4 permissions enabled',
                              style: AppTextStyles.titleSmall(context).copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            AppSpacing.gapXs,
                            Text(
                              state.allGranted
                                  ? 'All required permissions are granted.'
                                  : 'Grant all permissions to continue.',
                              style: AppTextStyles.bodySmall(context).copyWith(
                                color: AppColors.onSurfaceVariant(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AppSpacing.gapLg,
              Expanded(
                child: ListView(
                  children: [
                    _buildPermissionCard(
                      title: 'Usage Access',
                      description:
                          'Required to monitor app usage for your safety.',
                      icon: Icons.analytics_outlined,
                      isGranted: state.usageStats == PermissionStatus.granted,
                      onGrant: () {
                        if (state.usageStats != PermissionStatus.granted) {
                          _showUsageAccessInstructions();
                        }
                      },
                    ),
                    AppSpacing.gapSm,
                    _buildPermissionCard(
                      title: 'Accessibility Service',
                      description:
                          'Required for instant app blocking and monitoring.',
                      icon: Icons.accessibility_new_outlined,
                      isGranted:
                          state.accessibility == PermissionStatus.granted,
                      onGrant: () async {
                        if (state.accessibility !=
                            PermissionStatus.granted) {
                          _showAccessibilityInstructions();
                        }
                      },
                    ),
                    AppSpacing.gapSm,
                    _buildPermissionCard(
                      title: 'Display Over Apps',
                      description:
                          'Required to block inappropriate content instantly.',
                      icon: Icons.layers_outlined,
                      isGranted: state.overlay == PermissionStatus.granted,
                      onGrant: () async {
                        await PermissionService.requestOverlayPermission();
                      },
                    ),
                    AppSpacing.gapSm,
                    _buildPermissionCard(
                      title: 'Notifications',
                      description:
                          'Required to alert you when content is detected.',
                      icon: Icons.notifications_outlined,
                      isGranted:
                          state.notifications == PermissionStatus.granted,
                      onGrant: () async {
                        await PermissionService.requestNotificationPermission();
                      },
                    ),
                    AppSpacing.gapSm,
                    Card(
                      child: Padding(
                        padding: AppSpacing.paddingMd,
                        child: Row(
                          children: [
                            Container(
                              padding: AppSpacing.paddingSm,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.battery_alert_outlined,
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                            AppSpacing.gapMd,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Battery Background Usage',
                                    style: AppTextStyles.titleSmall(context).copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Open battery settings and set Guarden to "Don\'t restrict background usage" in background power management.',
                                    style: AppTextStyles.bodySmall(context).copyWith(
                                      color: AppColors.onSurfaceVariant(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: _showBatteryManagementInstructions,
                              child: const Text('OPEN'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: state.allGranted
                      ? () {
                          setState(() {
                            _permissionGateCompleted = true;
                          });
                        }
                      : null,
                  child: const Text('CONTINUE'),
                ),
              ),
            ],
          ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    // Stop usage tracking before signing out
    await _usageTracking.stopTracking();
    await _locationTracking.stopTracking();
    await _locationTracking.stopBackgroundService();

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _permissionSubscription?.cancel();
    _pairingCodeController.dispose();
    _usageTracking.stopTracking();
    _locationTracking.stopTracking();
    _locationTracking.stopBackgroundService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    final permissionState = _permissionState;

    if (_isCheckingPermissions || permissionState == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isResolvingParent) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_parentId == null || _parentId!.isEmpty) {
      return _buildParentLinkGate();
    }

    if (!permissionState.allGranted || !_permissionGateCompleted) {
      return _buildPermissionsGate(permissionState);
    }

    return StreamBuilder<FilterSettings>(
      stream: _settingsStream ?? const Stream.empty(),
      builder: (context, snapshot) {
        final settings = snapshot.data ?? FilterSettings.disabled(userId);

        return Scaffold(
          body: Stack(
            children: [
              Column(
                children: [
                  SizedBox(
                    child: ChildProtectionRunner(
                      childId: userId,
                      settings: settings,
                    ),
                  ),
                  Expanded(child: _pages[_index]),
                ],
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.local_florist_outlined),
                label: 'Garden',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.storefront_outlined),
                label: 'Market',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.shield_outlined),
                label: 'Status',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.warning_amber_outlined),
                label: 'Detections',
              ),
            ],
          ),
        );
      },
    );
  }
}
