import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../shared/shared.dart';
import '../../../services/pairing_service.dart';
import '../../../services/permission_service.dart';
import '../../../models/filter_settings_model.dart';
import '../../../services/filter_settings_service.dart';
import 'vivo_setup_helper_page.dart';

class StatusPage extends StatefulWidget {
  final VoidCallback onProfileButtonPressed;

  const StatusPage({super.key, required this.onProfileButtonPressed});

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> with WidgetsBindingObserver {
  final PairingService _pairingService = PairingService();
  final FilterSettingsService _filterSettingsService = FilterSettingsService();
  final TextEditingController _codeController = TextEditingController();
  bool _isLinking = false;
  PermissionState? _permissionState;
  bool _isCheckingPermissions = true;
  StreamSubscription<PermissionState>? _permissionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPermissions();
    
    // Listen to permission state changes
    _permissionSubscription = PermissionService.permissionStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _permissionState = state;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _permissionSubscription?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh permissions when app resumes
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _refreshPermissions();
      });
    }
  }

  Future<void> _refreshPermissions() async {
    setState(() => _isCheckingPermissions = true);
    final state = await PermissionService.checkAllPermissions();
    if (mounted) {
      setState(() {
        _permissionState = state;
        _isCheckingPermissions = false;
      });
    }
  }

  Future<void> _initPermissions() async {
    PermissionService.initialize();
    await _refreshPermissions();
  }

  void _showAddParentDialog() {
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
                controller: _codeController,
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
              onPressed: _isLinking
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: AppTextStyles.labelLarge(dialogContext),
              ),
            ),
            FilledButton(
              onPressed: _isLinking
                  ? null
                  : () => _linkParent(dialogContext),
              child: Text(
                _isLinking ? 'Linking...' : 'Link Parent',
                style: AppTextStyles.labelLarge(dialogContext),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _linkParent(BuildContext dialogContext) async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _showError('Please enter a valid 6-digit code.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('No user is currently signed in.');
      return;
    }

    final childName = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? 'Child');

    setState(() => _isLinking = true);
    try {
      final success = await _pairingService.pairChildWithCode(
        code: code,
        childId: user.uid,
        childName: childName,
        childPhotoUrl: user.photoURL,
      );

      if (!success) {
        _showError('Invalid or expired code.');
        return;
      }

      if (!mounted) return;
      
      _codeController.clear();
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    } catch (e) {
      _showError('Unable to link parent. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLinking = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showVivoSetupHelperAgain() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('deviceSettings')
          .doc('vivoSetupHelper')
          .set({
        'dontShowAgain': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VivoSetupHelperPage(
            childId: user.uid,
            initialDontShowAgain: false,
          ),
        ),
      );
    } catch (e) {
      _showError('Unable to open Vivo setup helper.');
    }
  }

  Widget _buildParentCard(String? parentName, String? parentEmail) {
    final theme = Theme.of(context);
    final displayName = parentName?.isNotEmpty == true 
        ? parentName! 
        : (parentEmail?.isNotEmpty == true ? parentEmail! : 'Unknown Parent');
    
    return Card(
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Parent',
                    style: AppTextStyles.labelMedium(context).copyWith(
                      color: AppColors.onSurfaceVariant(context),
                    ),
                  ),
                  Text(
                    displayName,
                    style: AppTextStyles.titleMedium(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.check_circle,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveFiltersSection(bool pornEnabled, bool violenceEnabled) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Active Filters',
          style: AppTextStyles.labelLarge(context),
        ),
        AppSpacing.gapSm,
        Row(
          children: [
            Expanded(
              child: _buildFilterChip(
                Icons.block,
                'Adult Content',
                pornEnabled,
                theme.colorScheme.error,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _buildFilterChip(
                Icons.bloodtype,
                'Gore & Gun',
                violenceEnabled,
                theme.colorScheme.error,
                trailingIcon: Icons.gps_fixed,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterChip(
    IconData icon,
    String label,
    bool isEnabled,
    Color color, {
    IconData? trailingIcon,
  }) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isEnabled 
            ? color.withValues(alpha: 0.1) 
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEnabled ? color : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: isEnabled ? color : theme.colorScheme.onSurfaceVariant,
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 4),
            Icon(
              trailingIcon,
              size: 16,
              color: isEnabled ? color : theme.colorScheme.onSurfaceVariant,
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isEnabled ? color : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Icon(
            isEnabled ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: isEnabled ? color : theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }


  Widget _buildScanIntervalSection(int intervalSeconds) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Scan Interval',
          style: AppTextStyles.labelLarge(context),
        ),
        AppSpacing.gapSm,
        Container(
          padding: AppSpacing.paddingMd,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.timer,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '$intervalSeconds seconds',
                style: AppTextStyles.titleMedium(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConfigurationCard(FilterSettings settings) {
    return Card(
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Protection Configuration',
              style: AppTextStyles.titleMedium(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            AppSpacing.gapMd,
            const Divider(),
            AppSpacing.gapMd,
            _buildActiveFiltersSection(
              settings.pornEnabled,
              settings.violenceEnabled,
            ),
            AppSpacing.gapLg,
            _buildScanIntervalSection(settings.scanIntervalSeconds),
          ],
        ),
      ),
    );
  }

  Widget _buildAddParentButton() {
    return FilledButton.icon(
      onPressed: _isLinking ? null : _showAddParentDialog,
      icon: const Icon(Icons.link),
      label: Text(
        'Add Parent',
        style: AppTextStyles.labelLarge(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Status'),
        ),
        body: Center(
          child: Text(
            'Please sign in to continue.',
            style: AppTextStyles.bodyMedium(context),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Status'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshPermissions,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (value) {
              if (value == 'logout') {
                widget.onProfileButtonPressed();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: AppSpacing.lg),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Log out',
                      style: AppTextStyles.labelLarge(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshPermissions,
        child: ListView(
          padding: AppSpacing.paddingMd,
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, userSnapshot) {
                final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                final fallbackParentId = userData?['parentId'] as String?;

                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .collection('parents')
                      .limit(1)
                      .snapshots(),
                  builder: (context, parentsSnapshot) {
                    final linkedParentDoc = parentsSnapshot.data?.docs
                        .where((doc) => doc.id != '_bootstrap')
                        .cast<QueryDocumentSnapshot<Map<String, dynamic>>?>()
                        .firstWhere(
                          (doc) => doc != null,
                          orElse: () => null,
                        );

                    final linkedParentId = linkedParentDoc?.id;
                    final parentId = linkedParentId ?? fallbackParentId;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (parentId == null)
                          Card(
                            child: Padding(
                              padding: AppSpacing.paddingMd,
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.link_off,
                                    size: 48,
                                    color: AppColors.onSurfaceVariant(context),
                                  ),
                                  AppSpacing.gapMd,
                                  Text(
                                    'No Parent Linked',
                                    style: AppTextStyles.titleMedium(context).copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  AppSpacing.gapSm,
                                  Text(
                                    'Link a parent to enable protection',
                                    style: AppTextStyles.bodyMedium(context).copyWith(
                                      color: AppColors.onSurfaceVariant(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            future: FirebaseFirestore.instance
                                .collection('users')
                                .doc(parentId)
                                .get(),
                            builder: (context, parentSnapshot) {
                              final parentData = parentSnapshot.data?.data();
                              final parentName = parentData?['name'] as String?;
                              final parentUsername = parentData?['username'] as String?;
                              final parentEmail = parentData?['email'] as String?;

                              return _buildParentCard(
                                parentName?.isNotEmpty == true
                                    ? parentName
                                    : (parentUsername?.isNotEmpty == true
                                        ? parentUsername
                                        : parentEmail),
                                parentEmail,
                              );
                            },
                          ),
                        AppSpacing.gapMd,
                        if (parentId != null)
                          StreamBuilder<FilterSettings>(
                            stream: _filterSettingsService.watchUserSettings(
                              parentId,
                              user.uid,
                            ),
                            builder: (context, settingsSnapshot) {
                              final settings = settingsSnapshot.data
                                  ?? FilterSettings.disabled(user.uid);

                              return _buildConfigurationCard(settings);
                            },
                          ),
                        AppSpacing.gapLg,
                        OutlinedButton.icon(
                          onPressed: _showVivoSetupHelperAgain,
                          icon: const Icon(Icons.lock_reset),
                          label: Text(
                            'Show Vivo Setup Helper Again',
                            style: AppTextStyles.labelLarge(context),
                          ),
                        ),
                        AppSpacing.gapMd,
                        _buildAddParentButton(),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
