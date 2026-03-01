import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../models/child_model.dart';
import '../../../models/blocked_app_model.dart';
import '../../../models/detection_model.dart';
import '../../../services/blocked_apps_service.dart';
import '../../../services/detections_service.dart';
import '../../../services/parent_children_service.dart';
import '../../../services/user_profile_service.dart';
import '../../../services/tomato_plant_service.dart';
import '../../../services/market_service.dart';
import '../../shared/shared.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TomatoPlantService _tomatoPlantService = TomatoPlantService();
  final UserProfileService _userProfileService = UserProfileService();
  final ParentChildrenService _childrenService = ParentChildrenService();
  final BlockedAppsService _blockedAppsService = BlockedAppsService();
  final MarketService _marketService = MarketService();

  late String _parentId;
  String? _selectedChildId;
  List<ChildModel> _children = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _parentId = FirebaseAuth.instance.currentUser?.uid ?? '';
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    try {
      final children = await _firestore
          .collection('users')
          .doc(_parentId)
          .collection('children')
          .get();

      setState(() {
        _children = children.docs
            .map((doc) => ChildModel.fromFirestore(doc))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading children: $e');
      setState(() => _isLoading = false);
    }
  }

  void _ensureSelectedChild(List<ChildModel> children) {
    if (_selectedChildId != null || children.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _selectedChildId = children.first.id;
        });
      }
    });
  }

  String _formatBlockedUntil(BuildContext context, DateTime? blockedUntil) {
    if (blockedUntil == null) return 'Forever';
    final formatter = DateFormat.yMMMd();
    return formatter.format(blockedUntil);
  }

  Future<void> _showError(BuildContext context, String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error(context),
      ),
    );
  }

  Future<_BlockDurationResult?> _pickBlockedUntil(
    BuildContext context, {
    DateTime? currentBlockedUntil,
  }) async {
    final result = await showDialog<_BlockDurationResult>(
      context: context,
      builder: (context) => _BlockDurationDialog(
        currentBlockedUntil: currentBlockedUntil,
      ),
    );
    return result;
  }

  Future<void> _blockApp({
    required BuildContext context,
    required String parentId,
    required String childId,
    required String appName,
    required String packageName,
  }) async {
    final result = await _pickBlockedUntil(context);
    if (result == null || result.cancelled) {
      return;
    }

    try {
      await _blockedAppsService.upsertBlockedApp(
        parentId: parentId,
        childId: childId,
        appName: appName,
        packageName: packageName,
        blockedUntil: result.blockedUntil,
      );
    } catch (e) {
      await _showError(context, 'Failed to block app');
    }
  }

  Future<void> _editBlock({
    required BuildContext context,
    required String parentId,
    required BlockedAppModel app,
  }) async {
    final result = await _pickBlockedUntil(
      context,
      currentBlockedUntil: app.blockedUntil,
    );
    if (result == null || result.cancelled) {
      return;
    }

    try {
      await _blockedAppsService.updateBlockedUntil(
        parentId: parentId,
        blockedAppId: app.id,
        blockedUntil: result.blockedUntil,
      );
    } catch (e) {
      await _showError(context, 'Failed to update block duration');
    }
  }

  Future<void> _unblockApp({
    required BuildContext context,
    required String parentId,
    required BlockedAppModel app,
  }) async {
    try {
      await _blockedAppsService.removeBlockedApp(
        parentId: parentId,
        blockedAppId: app.id,
      );
    } catch (e) {
      await _showError(context, 'Failed to remove block');
    }
  }

  void _showScreenTimeDialog(ChildModel child) {
    int minutes = 0;
    int seconds = 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Set Screen Time Allowance',
          style: AppTextStyles.titleLarge(context),
        ),
        content: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'For: ${child.name}',
                  style: AppTextStyles.bodyMedium(context),
                ),
                AppSpacing.gapMd,
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Minutes (0-999)',
                    labelStyle: AppTextStyles.bodySmall(context),
                  ),
                  onChanged: (value) => setState(() {
                    minutes = int.tryParse(value) ?? 0;
                  }),
                  style: AppTextStyles.bodyMedium(context),
                ),
                AppSpacing.gapSm,
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Seconds (0-59)',
                    labelStyle: AppTextStyles.bodySmall(context),
                  ),
                  onChanged: (value) => setState(() {
                    seconds = int.tryParse(value) ?? 0;
                  }),
                  style: AppTextStyles.bodyMedium(context),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelLarge(context),
            ),
          ),
          FilledButton(
            onPressed: () {
              _setScreenTime(child.id, minutes, seconds);
              Navigator.pop(context);
            },
            child: Text(
              'Set',
              style: AppTextStyles.labelLarge(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setScreenTime(String childId, int minutes, int seconds) async {
    try {
      final totalMinutes = minutes + (seconds / 60.0);
      await _firestore
          .collection('users')
          .doc(childId)
          .collection('gamification')
          .doc('tomatoPlant')
          .update({
        'screenTimeAllowanceMinutes': totalMinutes,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        final displaySeconds = seconds.toString().padLeft(2, '0');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Screen time set to ${minutes}m ${displaySeconds}s'),
            backgroundColor: AppColors.success(context),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error setting screen time: $e');
      await _showError(context, 'Failed to set screen time');
    }
  }

  List<_DetectedAppSummary> _summarizeDetections(List<DetectionModel> detections) {
    final map = <String, _DetectedAppSummary>{};

    for (final detection in detections) {
      final packageName = detection.packageName;
      final appName = detection.appName.isNotEmpty ? detection.appName : detection.packageName;
      final timestamp = detection.timestamp;

      if (packageName.isEmpty) continue;

      final existing = map[packageName];
      if (existing == null || timestamp.isAfter(existing.lastSeen ?? timestamp)) {
        map[packageName] = _DetectedAppSummary(
          packageName: packageName,
          appName: appName,
          lastSeen: timestamp,
        );
      }
    }

    final summaries = map.values.toList();
    summaries.sort((a, b) {
      final aTime = a.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return summaries;
  }

  @override
  Widget build(BuildContext context) {
    if (_parentId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Control', style: AppTextStyles.titleLarge(context)),
        ),
        body: Center(
          child: Text(
            'Please sign in again.',
            style: AppTextStyles.bodyMedium(context),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Control', style: AppTextStyles.titleLarge(context)),
      ),
      body: StreamBuilder<List<ChildModel>>(
        stream: _childrenService.watchChildren(_parentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load children',
                style: AppTextStyles.bodyMedium(context),
              ),
            );
          }

          final children = snapshot.data ?? [];
          _ensureSelectedChild(children);

          if (children.isEmpty) {
            return Center(
              child: Text(
                'No linked children found.',
                style: AppTextStyles.bodyMedium(context),
              ),
            );
          }

          final childId = _selectedChildId;

          return ListView(
            padding: AppSpacing.paddingMd,
            children: [
              // Child selector
              Text(
                'Child',
                style: AppTextStyles.labelMedium(context),
              ),
              AppSpacing.gapSm,
              DropdownButtonFormField<String>(
                value: childId,
                items: children
                    .map(
                      (child) => DropdownMenuItem<String>(
                        value: child.id,
                        child: Text(
                          child.name,
                          style: AppTextStyles.bodyMedium(context),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedChildId = value;
                  });
                },
              ),
              AppSpacing.gapLg,

              // Block Apps Section
              if (childId == null)
                Text(
                  'Select a child to view controls.',
                  style: AppTextStyles.bodyMedium(context),
                )
              else
                StreamBuilder<List<BlockedAppModel>>(
                  stream: _blockedAppsService.watchBlockedApps(
                    parentId: _parentId,
                    childId: childId,
                  ),
                  builder: (context, blockedSnapshot) {
                    if (blockedSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final blockedApps = (blockedSnapshot.data ?? [])
                        .where((app) => app.isActive)
                        .toList();

                    final blockedByPackage = {
                      for (final app in blockedApps) app.packageName: app,
                    };
                    final blockedByName = {
                      for (final app in blockedApps) app.appName: app,
                    };

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Blocked apps',
                          style: AppTextStyles.titleMedium(context),
                        ),
                        AppSpacing.gapSm,
                        if (blockedApps.isEmpty)
                          Text(
                            'No blocked apps yet.',
                            style: AppTextStyles.bodyMedium(context),
                          )
                        else
                          ...blockedApps.map((app) {
                            return Card(
                              margin: AppSpacing.verticalSm,
                              child: ListTile(
                                leading: Icon(
                                  Icons.block,
                                  size: AppSpacing.lg,
                                  color: AppColors.error(context),
                                ),
                                title: Text(
                                  app.appName,
                                  style: AppTextStyles.bodyLarge(context),
                                ),
                                subtitle: Text(
                                  'Until: ${_formatBlockedUntil(context, app.blockedUntil)}',
                                  style: AppTextStyles.bodySmall(context),
                                ),
                                trailing: Wrap(
                                  spacing: AppSpacing.sm,
                                  children: [
                                    TextButton(
                                      onPressed: () => _editBlock(
                                        context: context,
                                        parentId: _parentId,
                                        app: app,
                                      ),
                                      child: Text(
                                        'Edit',
                                        style: AppTextStyles.labelLarge(context),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => _unblockApp(
                                        context: context,
                                        parentId: _parentId,
                                        app: app,
                                      ),
                                      child: Text(
                                        'Unblock',
                                        style: AppTextStyles.labelLarge(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        AppSpacing.gapLg,
                        Text(
                          'Detected apps',
                          style: AppTextStyles.titleMedium(context),
                        ),
                        AppSpacing.gapSm,
                        StreamBuilder<List<DetectionModel>>(
                          stream: DetectionsService(childId: childId).getDetectionsStream(
                            limit: 200,
                          ),
                          builder: (context, detectionsSnapshot) {
                            if (detectionsSnapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            final detections = detectionsSnapshot.data ?? [];
                            final summaries = _summarizeDetections(detections);

                            if (summaries.isEmpty) {
                              return Text(
                                'No detections yet.',
                                style: AppTextStyles.bodyMedium(context),
                              );
                            }

                            return Column(
                              children: summaries.map((summary) {
                                final blocked = blockedByPackage[summary.packageName] ??
                                    blockedByName[summary.appName];

                                return Card(
                                  margin: AppSpacing.verticalSm,
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      radius: AppSpacing.lg,
                                      child: Text(
                                        summary.appName.isNotEmpty
                                            ? summary.appName[0].toUpperCase()
                                            : '?',
                                        style: AppTextStyles.labelLarge(context),
                                      ),
                                    ),
                                    title: Text(
                                      summary.appName,
                                      style: AppTextStyles.bodyLarge(context),
                                    ),
                                    subtitle: Text(
                                      summary.packageName,
                                      style: AppTextStyles.bodySmall(context),
                                    ),
                                    trailing: blocked != null
                                        ? Text(
                                            'Blocked',
                                            style: AppTextStyles.labelMedium(context).copyWith(
                                              color: AppColors.onSurfaceVariant(context),
                                            ),
                                          )
                                        : FilledButton(
                                            onPressed: () => _blockApp(
                                              context: context,
                                              parentId: _parentId,
                                              childId: childId,
                                              appName: summary.appName,
                                              packageName: summary.packageName,
                                            ),
                                            child: Text(
                                              'Block',
                                              style: AppTextStyles.labelLarge(context),
                                            ),
                                          ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),

              // Screen Time Control Section
              AppSpacing.gapLg,
              Divider(
                color: AppColors.outline(context),
              ),
              AppSpacing.gapLg,
              Text(
                'Screen Time Allowance',
                style: AppTextStyles.titleMedium(context),
              ),
              AppSpacing.gapMd,
              ...children.map((child) {
                return StreamBuilder<DocumentSnapshot>(
                  stream: _firestore
                      .collection('users')
                      .doc(child.id)
                      .collection('gamification')
                      .doc('tomatoPlant')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox.shrink();
                    }

                    final screenTimeMinutes =
                        (snapshot.data?.get('screenTimeAllowanceMinutes') as num?)?.toDouble() ?? 0.0;
                    final totalSeconds = (screenTimeMinutes * 60).toInt();
                    final minutes = totalSeconds ~/ 60;
                    final seconds = totalSeconds % 60;

                    return Card(
                      margin: AppSpacing.verticalSm,
                      child: Padding(
                        padding: AppSpacing.paddingSm,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      child.name,
                                      style: AppTextStyles.bodyLarge(context),
                                    ),
                                    AppSpacing.gapXs,
                                    Text(
                                      '${minutes}m ${seconds.toString().padLeft(2, '0')}s',
                                      style: AppTextStyles.bodyMedium(context),
                                    ),
                                  ],
                                ),
                                FilledButton(
                                  onPressed: () => _showScreenTimeDialog(child),
                                  child: Text(
                                    'Adjust',
                                    style: AppTextStyles.labelLarge(context),
                                  ),
                                ),
                              ],
                            ),
                            AppSpacing.gapSm,
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: (screenTimeMinutes / 120).clamp(0, 1),
                                minHeight: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }
}

class _BlockDurationDialog extends StatefulWidget {
  final DateTime? currentBlockedUntil;

  const _BlockDurationDialog({
    required this.currentBlockedUntil,
  });

  @override
  State<_BlockDurationDialog> createState() => _BlockDurationDialogState();
}

class _BlockDurationDialogState extends State<_BlockDurationDialog> {
  late final TextEditingController _controller;
  late bool _isForever;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _isForever = widget.currentBlockedUntil == null;
    _controller = TextEditingController();

    final blockedUntil = widget.currentBlockedUntil;
    if (blockedUntil != null) {
      final days = blockedUntil.difference(DateTime.now()).inDays;
      if (days > 0) {
        _controller.text = days.toString();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (_isForever) {
      Navigator.of(context).pop(const _BlockDurationResult(
        cancelled: false,
        blockedUntil: null,
      ));
      return;
    }

    final raw = _controller.text.trim();
    final days = int.tryParse(raw);
    if (days == null || days <= 0) {
      setState(() {
        _errorText = 'Enter a valid number of days';
      });
      return;
    }

    Navigator.of(context).pop(
      _BlockDurationResult(
        cancelled: false,
        blockedUntil: DateTime.now().add(Duration(days: days)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Block Duration',
        style: AppTextStyles.titleLarge(context),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioListTile<bool>(
              value: true,
              groupValue: _isForever,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _isForever = value;
                  _errorText = null;
                });
              },
              title: Text(
                'Block forever',
                style: AppTextStyles.bodyMedium(context),
              ),
            ),
            RadioListTile<bool>(
              value: false,
              groupValue: _isForever,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _isForever = value;
                  _errorText = null;
                });
              },
              title: Text(
                'Block for days',
                style: AppTextStyles.bodyMedium(context),
              ),
            ),
            if (!_isForever) ...[
              AppSpacing.gapSm,
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Number of days',
                  labelStyle: AppTextStyles.bodySmall(context),
                  errorText: _errorText,
                ),
                style: AppTextStyles.bodyMedium(context),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const _BlockDurationResult(
              cancelled: true,
              blockedUntil: null,
            ),
          ),
          child: Text(
            'Cancel',
            style: AppTextStyles.labelLarge(context),
          ),
        ),
        FilledButton(
          onPressed: _handleSave,
          child: Text(
            'Save',
            style: AppTextStyles.labelLarge(context),
          ),
        ),
      ],
    );
  }
}

class _BlockDurationResult {
  final bool cancelled;
  final DateTime? blockedUntil;

  const _BlockDurationResult({
    required this.cancelled,
    required this.blockedUntil,
  });
}

class _DetectedAppSummary {
  final String packageName;
  final String appName;
  final DateTime? lastSeen;

  const _DetectedAppSummary({
    required this.packageName,
    required this.appName,
    required this.lastSeen,
  });
}
