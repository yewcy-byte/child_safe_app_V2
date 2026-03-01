import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import '../../../models/child_model.dart';
import '../../../models/blocked_app_model.dart';
import '../../../models/detection_model.dart';
import '../../../models/hive/app_usage_cache.dart';
import '../../../services/blocked_apps_service.dart';
import '../../../services/detections_service.dart';
import '../../../services/parent_children_service.dart';
import '../../../services/market_service.dart';
import '../../../services/app_time_limits_service.dart';
import '../../../services/scan_exclusion_service.dart';
import '../../../services/grooming_detection_apps_service.dart';
import '../block_apps/block_apps_page.dart';
import '../../shared/shared.dart';
import 'qr_scanner_page.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ParentChildrenService _childrenService = ParentChildrenService();
  final MarketService _marketService = MarketService();

  late String _parentId;
  String? _selectedChildId;

  @override
  void initState() {
    super.initState();
    _parentId = _auth.currentUser?.uid ?? '';
  }

  @override
  Widget build(BuildContext context) {
    if (_parentId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Control', style: AppTextStyles.titleLarge(context))),
        body: Center(
          child: Text('Please sign in again.', style: AppTextStyles.bodyMedium(context)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Control', style: AppTextStyles.titleLarge(context))),
      body: StreamBuilder<List<ChildModel>>(
        stream: _childrenService.watchChildren(_parentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final children = snapshot.data ?? [];
          if (children.isEmpty) {
            return Center(
              child: Text('No linked children found.', style: AppTextStyles.bodyMedium(context)),
            );
          }

          // Auto-select first child
          if (_selectedChildId == null && children.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedChildId = children.first.id);
            });
          }

          final selectedChildId = _selectedChildId ?? children.first.id;
          final selectedChild = children.firstWhere(
            (c) => c.id == selectedChildId,
            orElse: () => children.first,
          );

          return SingleChildScrollView(
            padding: AppSpacing.paddingMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select Child', style: AppTextStyles.labelMedium(context)),
                AppSpacing.gapSm,
                DropdownButtonFormField<String>(
                  value: selectedChildId,
                  items: children
                      .map((child) => DropdownMenuItem(
                            value: child.id,
                            child: Text(child.name, style: AppTextStyles.bodyMedium(context)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedChildId = value);
                  },
                ),
                AppSpacing.gapLg,

                // Block Apps Section
                _SectionButton(
                  title: 'Block Apps',
                  icon: Icons.block,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const BlockAppsPage(),
                    ),
                  ),
                ),
                AppSpacing.gapMd,

                // Screen Time Section
                _SectionButton(
                  title: 'Screen Time',
                  icon: Icons.schedule,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          _ScreenTimePage(child: selectedChild, parentId: _parentId),
                    ),
                  ),
                ),
                AppSpacing.gapMd,

                // Custom Rewards Section
                _SectionButton(
                  title: 'Custom Rewards',
                  icon: Icons.card_giftcard,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          _CustomRewardsPage(child: selectedChild, parentId: _parentId),
                    ),
                  ),
                ),
                AppSpacing.gapMd,

                // Scan Exclusions Section
                _SectionButton(
                  title: 'Content Scan Exclusions',
                  icon: Icons.visibility_off,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          _ScanExclusionsPage(childId: selectedChildId, parentId: _parentId),
                    ),
                  ),
                ),
                AppSpacing.gapMd,

                _SectionButton(
                  title: 'Child Grooming Detection',
                  icon: Icons.mark_chat_unread,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          _GroomingDetectionPage(child: selectedChild, parentId: _parentId),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Simple section button
class _SectionButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _SectionButton({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: AppTextStyles.titleSmall(context)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}

// Block Apps detail page
class _BlockAppsPage extends StatefulWidget {
  final String childId;
  final String parentId;

  const _BlockAppsPage({required this.childId, required this.parentId});

  @override
  State<_BlockAppsPage> createState() => _BlockAppsPageState();
}

class _BlockAppsPageState extends State<_BlockAppsPage> {
  final BlockedAppsService _blockedAppsService = BlockedAppsService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Block Apps', style: AppTextStyles.titleLarge(context))),
      body: StreamBuilder<List<DetectionModel>>(
        stream: DetectionsService(childId: widget.childId).getDetectionsStream(limit: 200),
        builder: (context, detectionsSnapshot) {
          if (detectionsSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final detections = detectionsSnapshot.data ?? [];
          final map = <String, _DetectionSummary>{};

          for (final detection in detections) {
            if (detection.packageName.isEmpty) continue;
            final appName =
                detection.appName.isNotEmpty ? detection.appName : detection.packageName;
            final existing = map[detection.packageName];
            if (existing == null || detection.timestamp.isAfter(existing.timestamp)) {
              map[detection.packageName] = _DetectionSummary(
                packageName: detection.packageName,
                appName: appName,
                timestamp: detection.timestamp,
              );
            }
          }

          final summaries = map.values.toList();
          summaries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          if (summaries.isEmpty) {
            return Center(
              child: Text('No detections yet', style: AppTextStyles.bodyMedium(context)),
            );
          }

          return StreamBuilder<List<BlockedAppModel>>(
            stream: _blockedAppsService.watchBlockedApps(
              parentId: widget.parentId,
              childId: widget.childId,
            ),
            builder: (context, blockedSnapshot) {
              final blockedApps = (blockedSnapshot.data ?? []).where((app) => app.isActive).toList();
              final blockedByPackage = {
                for (final app in blockedApps) app.packageName: app,
              };

              return ListView.builder(
                padding: AppSpacing.paddingMd,
                itemCount: summaries.length,
                itemBuilder: (context, index) {
                  final summary = summaries[index];
                  final blocked = blockedByPackage[summary.packageName];

                  return Card(
                    margin: AppSpacing.verticalSm,
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(summary.appName.isNotEmpty ? summary.appName[0].toUpperCase() : '?'),
                      ),
                      title: Text(summary.appName),
                      subtitle: Text(summary.packageName, style: AppTextStyles.bodySmall(context)),
                      trailing: blocked != null
                          ? Text('Blocked', style: AppTextStyles.labelSmall(context))
                          : FilledButton(
                              onPressed: () async {
                                final result = await showDialog<Duration?>(
                                  context: context,
                                  builder: (context) => _BlockDurationDialog(),
                                );
                                if (result != null && mounted) {
                                  try {
                                    await _blockedAppsService.upsertBlockedApp(
                                      parentId: widget.parentId,
                                      childId: widget.childId,
                                      appName: summary.appName,
                                      packageName: summary.packageName,
                                      blockedUntil: DateTime.now().add(result),
                                    );
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error: $e')),
                                      );
                                    }
                                  }
                                }
                              },
                              child: Text('Block', style: AppTextStyles.labelSmall(context)),
                            ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// Screen Time detail page
class _ScreenTimePage extends StatefulWidget {
  final ChildModel child;
  final String parentId;

  const _ScreenTimePage({required this.child, required this.parentId});

  @override
  State<_ScreenTimePage> createState() => _ScreenTimePageState();
}

class _ScreenTimePageState extends State<_ScreenTimePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AppTimeLimitsService _appTimeLimitsService = AppTimeLimitsService();

  int _todayMinutesForApp(AppUsageCache app) {
    return app.minutesToday;
  }

  int _weekMinutesForApp(AppUsageCache app) {
    if (app.weeklyAverage > 0) {
      return (app.weeklyAverage * 7).round();
    }
    return app.minutesToday;
  }

  int _limitSecondsFromDoc(Map<String, dynamic> data) {
    final totalSecondsLimit = (data['totalSecondsLimit'] as num?)?.toInt();
    if (totalSecondsLimit != null && totalSecondsLimit > 0) {
      return totalSecondsLimit;
    }

    final minutesLimit = (data['minutesLimit'] as num?)?.toInt();
    final secondsLimit = ((data['secondsLimit'] as num?)?.toInt() ?? 0).clamp(0, 59);
    if (minutesLimit == null || minutesLimit < 0) {
      return 0;
    }
    return (minutesLimit * 60) + secondsLimit;
  }

  String _formatLimit(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  String _formatAllowanceMinutesWithSeconds(double allowanceMinutes) {
    final totalSeconds = (allowanceMinutes * 60).round().clamp(0, 1 << 30);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Screen Time', style: AppTextStyles.titleLarge(context))),
      body: SingleChildScrollView(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Child: ${widget.child.name}', style: AppTextStyles.titleSmall(context)),
            AppSpacing.gapLg,

            // Total Screen Time and 7-Day Breakdown
            StreamBuilder<DocumentSnapshot>(
              stream: _firestore
                  .collection('users')
                  .doc(widget.child.id)
                  .collection('screenTime')
                  .doc('current')
                  .snapshots(),
              builder: (context, screenTimeSnapshot) {
                final screenTimeData = screenTimeSnapshot.data?.data() as Map<String, dynamic>?;
              final last7DaysRaw = (screenTimeData?['last7Days'] as List<dynamic>?) ?? [];
              final last7DayPoints = _buildScreenTimePoints(last7DaysRaw);
              final last7Days = last7DayPoints
                .map((point) => point.minutes)
                .toList();

                final totalWeekMinutes = last7Days.reduce((a, b) => a + b);
                final hours = totalWeekMinutes ~/ 60;
                final minutes = totalWeekMinutes % 60;

                return Card(
                  child: Padding(
                    padding: AppSpacing.paddingMd,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.smartphone,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            AppSpacing.gapSm,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Screen Time',
                                    style: AppTextStyles.titleSmall(context),
                                  ),
                                  Text(
                                    'Total: ${hours}h ${minutes}m (7 days)',
                                    style: AppTextStyles.bodySmall(context)?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        AppSpacing.gapMd,
                        _buildScreenTimeChart(context, last7DayPoints),
                      ],
                    ),
                  ),
                );
              },
            ),

            AppSpacing.gapLg,

            // Daily Screen Time Limit
            StreamBuilder<DocumentSnapshot>(
              stream: _firestore
                  .collection('users')
                  .doc(widget.child.id)
                  .collection('gamification')
                  .doc('tomatoPlant')
                  .snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>?;
                final screenTimeAllowanceMinutes =
                    (data?['screenTimeAllowanceMinutes'] as num?)?.toDouble() ?? 0.0;
                final screenTimeDisplay =
                    _formatAllowanceMinutesWithSeconds(screenTimeAllowanceMinutes);
                final screenTimeProgress = (screenTimeAllowanceMinutes / 120).clamp(0.0, 1.0);

                return Card(
                  child: Padding(
                    padding: AppSpacing.paddingMd,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Daily Screen Time Limit', style: AppTextStyles.titleSmall(context)),
                        AppSpacing.gapMd,
                        Text(screenTimeDisplay, style: AppTextStyles.headlineMedium(context)),
                        AppSpacing.gapMd,
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: screenTimeProgress,
                            minHeight: 12,
                          ),
                        ),
                        AppSpacing.gapMd,
                        FilledButton.icon(
                          onPressed: () => _showScreenTimeDialog(),
                          icon: const Icon(Icons.edit),
                          label: const Text('Adjust'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            AppSpacing.gapLg,

            // App-Specific Time Limits
            StreamBuilder<DocumentSnapshot>(
              stream: _firestore
                  .collection('users')
                  .doc(widget.child.id)
                  .collection('appUsage')
                  .doc('current')
                  .snapshots(),
              builder: (context, usageSnapshot) {
                final usageData = usageSnapshot.data?.data() as Map<String, dynamic>?;
                final appUsageList = usageData != null
                    ? _createAppUsageCacheListFromFirestore(usageData)
                    : AppUsageCacheList.empty();

                return Card(
                  child: Padding(
                    padding: AppSpacing.paddingMd,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Daily App Time Limits', style: AppTextStyles.titleSmall(context)),
                        AppSpacing.gapMd,
                        if (appUsageList.apps.isEmpty)
                          Text(
                            'No app usage data available yet',
                            style: AppTextStyles.bodyMedium(context)?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          )
                        else
                          _buildAppUsageList(context, appUsageList),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showScreenTimeDialog() {
    int minutes = 0;
    int seconds = 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set Screen Time Allowance', style: AppTextStyles.titleLarge(context)),
        content: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Minutes (0-999)',
                    labelStyle: AppTextStyles.bodySmall(context),
                  ),
                  onChanged: (value) => setState(() => minutes = int.tryParse(value) ?? 0),
                  style: AppTextStyles.bodyMedium(context),
                ),
                AppSpacing.gapSm,
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Seconds (0-59)',
                    labelStyle: AppTextStyles.bodySmall(context),
                  ),
                  onChanged: (value) => setState(() => seconds = int.tryParse(value) ?? 0),
                  style: AppTextStyles.bodyMedium(context),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppTextStyles.labelLarge(context)),
          ),
          FilledButton(
            onPressed: () async {
              final totalMinutes = minutes + (seconds / 60.0);
              try {
                await _firestore
                    .collection('users')
                    .doc(widget.child.id)
                    .collection('gamification')
                    .doc('tomatoPlant')
                    .update({
                  'screenTimeAllowanceMinutes': totalMinutes,
                  'lastUpdated': FieldValue.serverTimestamp(),
                });

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Screen time set to ${minutes}m ${seconds.toString().padLeft(2, '0')}s'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: Text('Set', style: AppTextStyles.labelLarge(context)),
          ),
        ],
      ),
    );
  }

  void _showQuickAddAppTimeLimitDialog(AppUsageCache app) async {
    int minutes = 30;
    int seconds = 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set Daily Time Limit', style: AppTextStyles.titleLarge(context)),
        content: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(app.appName[0].toUpperCase(), style: AppTextStyles.labelSmall(context)),
                  ),
                  title: Text(app.appName, style: AppTextStyles.bodyMedium(context)),
                  subtitle: Text(
                    '${_todayMinutesForApp(app)}m today • ${_weekMinutesForApp(app)}m this week',
                    style: AppTextStyles.bodySmall(context),
                  ),
                ),
                AppSpacing.gapMd,
                TextFormField(
                  keyboardType: TextInputType.number,
                  initialValue: minutes.toString(),
                  decoration: InputDecoration(
                    labelText: 'Minutes',
                    labelStyle: AppTextStyles.bodySmall(context),
                  ),
                  onChanged: (value) => setState(() => minutes = int.tryParse(value) ?? 30),
                  style: AppTextStyles.bodyMedium(context),
                ),
                AppSpacing.gapSm,
                TextFormField(
                  keyboardType: TextInputType.number,
                  initialValue: seconds.toString(),
                  decoration: InputDecoration(
                    labelText: 'Seconds (0-59)',
                    labelStyle: AppTextStyles.bodySmall(context),
                  ),
                  onChanged: (value) => setState(
                    () => seconds = (int.tryParse(value) ?? 0).clamp(0, 59),
                  ),
                  style: AppTextStyles.bodyMedium(context),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppTextStyles.labelLarge(context)),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await _appTimeLimitsService.setAppTimeLimit(
                  childId: widget.child.id,
                  packageName: app.packageName,
                  appName: app.appName,
                  minutesLimit: minutes,
                  secondsLimit: seconds,
                );

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Time limit set for ${app.appName}: ${minutes}m ${seconds.toString().padLeft(2, '0')}s',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: Text('Set Daily Limit', style: AppTextStyles.labelLarge(context)),
          ),
        ],
      ),
    );
  }

  void _showEditAppTimeLimitDialog(AppUsageCache app, int currentLimitSeconds) {
    int minutes = currentLimitSeconds ~/ 60;
    int seconds = currentLimitSeconds % 60;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Daily Time Limit', style: AppTextStyles.titleLarge(context)),
        content: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(app.appName[0].toUpperCase()),
                  ),
                  title: Text(app.appName, style: AppTextStyles.bodyMedium(context)),
                  subtitle: Text(
                    '${_todayMinutesForApp(app)}m today • ${_weekMinutesForApp(app)}m this week',
                    style: AppTextStyles.bodySmall(context),
                  ),
                ),
                AppSpacing.gapMd,
                TextFormField(
                  keyboardType: TextInputType.number,
                  initialValue: minutes.toString(),
                  decoration: InputDecoration(
                    labelText: 'Minutes',
                    labelStyle: AppTextStyles.bodySmall(context),
                  ),
                  onChanged: (value) => setState(() => minutes = int.tryParse(value) ?? minutes),
                  style: AppTextStyles.bodyMedium(context),
                ),
                AppSpacing.gapSm,
                TextFormField(
                  keyboardType: TextInputType.number,
                  initialValue: seconds.toString(),
                  decoration: InputDecoration(
                    labelText: 'Seconds (0-59)',
                    labelStyle: AppTextStyles.bodySmall(context),
                  ),
                  onChanged: (value) => setState(
                    () => seconds = (int.tryParse(value) ?? seconds).clamp(0, 59),
                  ),
                  style: AppTextStyles.bodyMedium(context),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppTextStyles.labelLarge(context)),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await _appTimeLimitsService.setAppTimeLimit(
                  childId: widget.child.id,
                  packageName: app.packageName,
                  appName: app.appName,
                  minutesLimit: minutes,
                  secondsLimit: seconds,
                );

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Time limit updated for ${app.appName}: ${minutes}m ${seconds.toString().padLeft(2, '0')}s',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: Text('Update', style: AppTextStyles.labelLarge(context)),
          ),
        ],
      ),
    );
  }

  void _removeAppTimeLimit(String packageName) async {
    try {
      await _appTimeLimitsService.removeAppTimeLimit(
        childId: widget.child.id,
        packageName: packageName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Time limit removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _buildAppUsageList(BuildContext context, AppUsageCacheList appUsageList) {
    // Sort apps by usage time (most used first)
    final sortedApps = appUsageList.apps.toList()
      ..sort((a, b) => _todayMinutesForApp(b).compareTo(_todayMinutesForApp(a)));

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('children')
          .doc(widget.child.id)
          .collection('appTimeLimits')
          .snapshots(),
      builder: (context, limitsSnapshot) {
        final limitsData = limitsSnapshot.data?.docs ?? [];
        final appLimits = <String, int>{};

        for (final doc in limitsData) {
          final data = doc.data() as Map<String, dynamic>;
          final packageName = data['packageName'] as String?;
          final limitSeconds = _limitSecondsFromDoc(data);
          if (packageName != null && limitSeconds > 0) {
            appLimits[packageName] = limitSeconds;
          }
        }

        return Column(
          children: sortedApps.map((app) {
            final limitSeconds = appLimits[app.packageName];
            final usagePercent = limitSeconds != null
                ? ((app.minutesToday * 60) / limitSeconds).clamp(0.0, 1.0)
                : 0.0;

            return Card(
              margin: AppSpacing.paddingSm,
              child: Padding(
                padding: AppSpacing.paddingMd,
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            app.appName[0].toUpperCase(),
                            style: AppTextStyles.labelMedium(context),
                          ),
                        ),
                        AppSpacing.gapMd,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                app.appName,
                                style: AppTextStyles.bodyMedium(context),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${_todayMinutesForApp(app)}m today • ${_weekMinutesForApp(app)}m this week',
                                style: AppTextStyles.bodySmall(context),
                              ),
                            ],
                          ),
                        ),
                        if (limitSeconds != null) ...[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${_formatLimit(limitSeconds)} limit',
                                style: AppTextStyles.bodySmall(context),
                              ),
                              Text(
                                '${(usagePercent * 100).round()}% used',
                                style: AppTextStyles.bodySmall(context)?.copyWith(
                                  color: usagePercent > 0.8
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Text(
                            'No limit',
                            style: AppTextStyles.bodySmall(context)?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (limitSeconds != null) ...[
                      AppSpacing.gapMd,
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: usagePercent,
                          minHeight: 8,
                          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            usagePercent > 0.8
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                    AppSpacing.gapSm,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (limitSeconds != null)
                          OutlinedButton.icon(
                            onPressed: () => _showEditAppTimeLimitDialog(app, limitSeconds),
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Edit'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: () => _showQuickAddAppTimeLimitDialog(app),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Set Daily Limit'),
                          ),
                        if (limitSeconds != null) ...[
                          AppSpacing.gapSm,
                          OutlinedButton.icon(
                            onPressed: () => _removeAppTimeLimit(app.packageName),
                            icon: const Icon(Icons.delete, size: 16),
                            label: const Text('Remove'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  List<_ScreenTimePoint> _buildScreenTimePoints(List<dynamic> last7DaysRaw) {
    final now = DateTime.now();
    final parsed = last7DaysRaw.whereType<Map>().map((raw) {
      final item = raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final dateString = (item['date'] as String?) ?? '';
      final date = DateTime.tryParse(dateString) ?? now;
      final minutes = (item['minutes'] as num?)?.toInt() ?? 0;
      return _ScreenTimePoint(date: date, minutes: minutes);
    }).toList();

    if (parsed.length == 7) {
      return parsed;
    }

    return List.generate(7, (index) {
      final date = DateTime(now.year, now.month, now.day).subtract(
        Duration(days: 6 - index),
      );
      return _ScreenTimePoint(date: date, minutes: 0);
    });
  }

  Widget _buildScreenTimeChart(BuildContext context, List<_ScreenTimePoint> points) {
    final dailyMinutes = points.map((point) => point.minutes).toList();
    if (dailyMinutes.isEmpty || dailyMinutes.every((m) => m == 0)) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.access_time,
                size: 32,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
              AppSpacing.gapSm,
              Text(
                'No screen time data available',
                style: AppTextStyles.bodySmall(context)?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxMinutes = dailyMinutes.reduce((a, b) => a > b ? a : b);
    final today = DateTime.now();
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(points.length, (index) {
          final point = points[index];
          final minutes = point.minutes;
          final height = maxMinutes > 0 ? (minutes / maxMinutes) * 80.0 : 0.0;
          final isToday = point.date.year == today.year &&
              point.date.month == today.month &&
              point.date.day == today.day;
          final dayLabel = dayLabels[(point.date.weekday - 1).clamp(0, 6)];

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (minutes > 0) ...[
                Text(
                  '${minutes ~/ 60}h${minutes % 60}',
                  style: AppTextStyles.labelSmall(context)?.copyWith(
                    color: isToday
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                AppSpacing.gapXs,
              ],
              Container(
                width: 24,
                height: height.clamp(4.0, 80.0),
                decoration: BoxDecoration(
                  color: isToday
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              AppSpacing.gapXs,
              Text(
                dayLabel,
                style: AppTextStyles.labelSmall(context)?.copyWith(
                  color: isToday
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  AppUsageCacheList _createAppUsageCacheListFromFirestore(Map<String, dynamic> data) {
    final appsData = data['apps'] as List<dynamic>? ?? [];
    final lastUpdated = (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now();

    final apps = appsData.map((appData) {
      final appMap = appData as Map<String, dynamic>;
      return AppUsageCache(
        packageName: appMap['packageName'] as String? ?? '',
        appName: appMap['appName'] as String? ?? 'Unknown App',
        minutesToday: (appMap['minutesToday'] as num?)?.toInt() ?? 0,
        minutesYesterday: (appMap['minutesYesterday'] as num?)?.toInt() ?? 0,
        weeklyAverage: (appMap['weeklyAverage'] as num?)?.toDouble() ?? 0.0,
        iconUrl: appMap['iconUrl'] as String?,
        lastUpdated: (appMap['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();

    return AppUsageCacheList(
      apps: apps,
      lastUpdated: lastUpdated,
      lastSyncAttempt: lastUpdated,
      syncError: null,
    );
  }
}

class _ScreenTimePoint {
  final DateTime date;
  final int minutes;

  const _ScreenTimePoint({required this.date, required this.minutes});
}

class _GroomingDetectionPage extends StatefulWidget {
  final ChildModel child;
  final String parentId;

  const _GroomingDetectionPage({required this.child, required this.parentId});

  @override
  State<_GroomingDetectionPage> createState() => _GroomingDetectionPageState();
}

class _GroomingDetectionPageState extends State<_GroomingDetectionPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GroomingDetectionAppsService _groomingAppsService =
      GroomingDetectionAppsService();

  int _weeklyMinutesForApp(AppUsageCache app) {
    if (app.weeklyAverage > 0) {
      return (app.weeklyAverage * 7).round();
    }
    return app.minutesToday;
  }

  AppUsageCacheList _createAppUsageCacheListFromFirestore(Map<String, dynamic> data) {
    final appsData = data['apps'] as List<dynamic>? ?? [];
    final lastUpdated = (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now();

    final apps = appsData.map((appData) {
      final appMap = appData as Map<String, dynamic>;
      return AppUsageCache(
        packageName: appMap['packageName'] as String? ?? '',
        appName: appMap['appName'] as String? ?? 'Unknown App',
        minutesToday: (appMap['minutesToday'] as num?)?.toInt() ?? 0,
        minutesYesterday: (appMap['minutesYesterday'] as num?)?.toInt() ?? 0,
        weeklyAverage: (appMap['weeklyAverage'] as num?)?.toDouble() ?? 0.0,
        iconUrl: appMap['iconUrl'] as String?,
        lastUpdated: (appMap['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();

    return AppUsageCacheList(
      apps: apps,
      lastUpdated: lastUpdated,
      lastSyncAttempt: lastUpdated,
      syncError: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Child Grooming Detection', style: AppTextStyles.titleLarge(context)),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore
            .collection('users')
            .doc(widget.child.id)
            .collection('appUsage')
            .doc('current')
            .snapshots(),
        builder: (context, usageSnapshot) {
          final usageData = usageSnapshot.data?.data() as Map<String, dynamic>?;
          final appUsageList = usageData != null
              ? _createAppUsageCacheListFromFirestore(usageData)
              : AppUsageCacheList.empty();
          final sortedApps = appUsageList.apps.toList()
            ..sort((a, b) => _weeklyMinutesForApp(b).compareTo(_weeklyMinutesForApp(a)));

          return StreamBuilder<List<GroomingDetectionApp>>(
            stream: _groomingAppsService.watchApps(
              parentId: widget.parentId,
              childId: widget.child.id,
            ),
            builder: (context, selectedSnapshot) {
              final selectedApps = selectedSnapshot.data ?? const <GroomingDetectionApp>[];
              final selectedByPackage = <String, GroomingDetectionApp>{
                for (final app in selectedApps) app.packageName: app,
              };

              if (sortedApps.isEmpty) {
                return Center(
                  child: Text(
                    'No app usage data available yet.',
                    style: AppTextStyles.bodyMedium(context),
                  ),
                );
              }

              return ListView.builder(
                padding: AppSpacing.paddingMd,
                itemCount: sortedApps.length,
                itemBuilder: (context, index) {
                  final app = sortedApps[index];
                  final selected = selectedByPackage[app.packageName]?.enabled ?? false;

                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: SwitchListTile(
                      secondary: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Text(
                          app.appName.isNotEmpty ? app.appName[0].toUpperCase() : '?',
                          style: AppTextStyles.labelSmall(context),
                        ),
                      ),
                      title: Text(
                        app.appName,
                        style: AppTextStyles.bodyMedium(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_weeklyMinutesForApp(app)}m used this week',
                        style: AppTextStyles.bodySmall(context),
                      ),
                      value: selected,
                      onChanged: (enabled) async {
                        try {
                          await _groomingAppsService.setAppEnabled(
                            parentId: widget.parentId,
                            childId: widget.child.id,
                            packageName: app.packageName,
                            appName: app.appName,
                            enabled: enabled,
                          );
                        } catch (e) {
                          if (!mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to update app scanner: $e')),
                          );
                        }
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// Custom Rewards detail page
class _CustomRewardsPage extends StatefulWidget {
  final ChildModel child;
  final String parentId;

  const _CustomRewardsPage({required this.child, required this.parentId});

  @override
  State<_CustomRewardsPage> createState() => _CustomRewardsPageState();
}

class _CustomRewardsPageState extends State<_CustomRewardsPage> {
  final TextEditingController _controller = TextEditingController();
  final MarketService _marketService = MarketService();
  bool _saving = false;

  static const List<String> _presets = [
    'Movie Night',
    'New Toy',
    'Ice Cream Trip',
    'Park Adventure',
    'Favorite Dinner',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Custom Rewards', style: AppTextStyles.titleLarge(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            onPressed: _openQRScanner,
            tooltip: 'Scan Reward QR Code',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('For: ${widget.child.name}', style: AppTextStyles.bodyMedium(context)),
            AppSpacing.gapLg,
            Card(
              child: Padding(
                padding: AppSpacing.paddingMd,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create Custom Reward', style: AppTextStyles.titleSmall(context)),
                    AppSpacing.gapMd,
                    TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Enter reward text',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    AppSpacing.gapMd,
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _controller.text =
                                    _presets[Random().nextInt(_presets.length)],
                            icon: const Icon(Icons.casino_outlined),
                            label: const Text('Randomize'),
                          ),
                        ),
                        AppSpacing.gapSm,
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _addReward,
                            icon: const Icon(Icons.add),
                            label: Text(_saving ? 'Saving...' : 'Add Reward'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            AppSpacing.gapLg,
            Text('Existing Rewards', style: AppTextStyles.titleSmall(context)),
            AppSpacing.gapMd,
            StreamBuilder<List<CustomReward>>(
              stream: _marketService.watchAvailableCustomRewards(widget.child.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final rewards = snapshot.data ?? [];
                if (rewards.isEmpty) {
                  return Text('No custom rewards yet', style: AppTextStyles.bodyMedium(context));
                }

                return Column(
                  children: rewards
                      .map((reward) => Card(
                            child: Padding(
                              padding: AppSpacing.paddingMd,
                              child: Text(reward.title, style: AppTextStyles.bodyMedium(context)),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
            AppSpacing.gapLg,
            Center(
              child: FilledButton.icon(
                onPressed: _openQRScanner,
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Scan Reward QR Code'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addReward() async {
    final reward = _controller.text.trim();
    if (reward.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Reward text is required'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _marketService.addCustomReward(childId: widget.child.id, title: reward);

      if (!mounted) return;
      _controller.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom reward added')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openQRScanner() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => QRScannerPage(
          child: widget.child,
          parentId: widget.parentId,
        ),
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reward scanned successfully! ✓'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

// Block duration dialog
class _BlockDurationDialog extends StatefulWidget {
  @override
  State<_BlockDurationDialog> createState() => _BlockDurationDialogState();
}

class _BlockDurationDialogState extends State<_BlockDurationDialog> {
  late TextEditingController _controller;
  bool _isForever = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Block Duration', style: AppTextStyles.titleLarge(context)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<bool>(
              value: true,
              groupValue: _isForever,
              onChanged: (value) => setState(() {
                _isForever = value ?? true;
                _errorText = null;
              }),
              title: Text('Block forever', style: AppTextStyles.bodyMedium(context)),
            ),
            RadioListTile<bool>(
              value: false,
              groupValue: _isForever,
              onChanged: (value) => setState(() {
                _isForever = value ?? true;
                _errorText = null;
              }),
              title: Text('Block for days', style: AppTextStyles.bodyMedium(context)),
            ),
            if (!_isForever) ...[
              AppSpacing.gapSm,
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Number of days',
                  errorText: _errorText,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: AppTextStyles.labelLarge(context)),
        ),
        FilledButton(
          onPressed: () {
            if (_isForever) {
              Navigator.pop(context);
              return;
            }

            final days = int.tryParse(_controller.text.trim());
            if (days == null || days <= 0) {
              setState(() => _errorText = 'Enter a valid number');
              return;
            }

            Navigator.pop(context, Duration(days: days));
          },
          child: Text('Save', style: AppTextStyles.labelLarge(context)),
        ),
      ],
    );
  }
}

class _DetectionSummary {
  final String packageName;
  final String appName;
  final DateTime timestamp;
  final int minutesToday;

  _DetectionSummary({
    required this.packageName,
    required this.appName,
    required this.timestamp,
    this.minutesToday = 0,
  });
}

// Scan Exclusions page
class _ScanExclusionsPage extends StatefulWidget {
  final String childId;
  final String parentId;

  const _ScanExclusionsPage({
    required this.childId,
    required this.parentId,
  });

  @override
  State<_ScanExclusionsPage> createState() => _ScanExclusionsPageState();
}

class _ScanExclusionsPageState extends State<_ScanExclusionsPage> {
  final ScanExclusionService _scanExclusionService = ScanExclusionService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Content Scan Exclusions', style: AppTextStyles.titleLarge(context)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            padding: AppSpacing.paddingMd,
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            child: Text(
              'Select apps where content scanning should be paused. This is useful for apps that don\'t need monitoring.',
              style: AppTextStyles.bodySmall(context),
            ),
          ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.childId)
                  .collection('appUsage')
                  .doc('current')
                  .snapshots(),
              builder: (context, appUsageSnapshot) {
                if (appUsageSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final userData = appUsageSnapshot.data?.data() as Map<String, dynamic>?;
                final apps = (userData?['apps'] as List<dynamic>? ?? const [])
                    .whereType<Map>()
                    .map(
                      (raw) => raw.map(
                        (key, value) => MapEntry(key.toString(), value),
                      ),
                    )
                    .toList(growable: false);

                final appList = <_DetectionSummary>[];
                for (final app in apps) {
                  final packageName = (app['packageName'] as String?)?.trim() ?? '';
                  if (packageName.isEmpty) {
                    continue;
                  }

                  final appNameRaw = (app['appName'] as String?)?.trim() ?? '';
                  final appName = appNameRaw.isNotEmpty ? appNameRaw : packageName;
                  final minutesToday = (app['minutesToday'] as num?)?.toInt() ?? 0;

                  appList.add(
                    _DetectionSummary(
                      packageName: packageName,
                      appName: appName,
                      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
                      minutesToday: minutesToday,
                    ),
                  );
                }

                if (appList.isEmpty) {
                  return Center(
                    child: Text(
                      'No app usage data yet',
                      style: AppTextStyles.bodyMedium(context),
                    ),
                  );
                }

                final sortedApps = appList.toList()
                  ..sort((a, b) => b.minutesToday.compareTo(a.minutesToday));

                // Show excluded apps separately
                return StreamBuilder<List<ScanExcludedApp>>(
                  stream: _scanExclusionService.watchExcludedApps(widget.childId),
                  builder: (context, exclusionsSnapshot) {
                    final excluded = (exclusionsSnapshot.data ?? [])
                        .map((e) => e.packageName)
                        .toSet();

                    return ListView.builder(
                      padding: AppSpacing.paddingMd,
                      itemCount: sortedApps.length,
                      itemBuilder: (context, index) {
                        final app = sortedApps[index];
                        final isExcluded = excluded.contains(app.packageName);

                        return Card(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: CheckboxListTile(
                            value: isExcluded,
                            onChanged: (value) async {
                              if (value == true) {
                                await _scanExclusionService.excludeAppFromScanning(
                                  childId: widget.childId,
                                  packageName: app.packageName,
                                  appName: app.appName,
                                  reason: 'user_choice',
                                );
                              } else {
                                await _scanExclusionService.removeExclusionFromScanning(
                                  childId: widget.childId,
                                  packageName: app.packageName,
                                );
                              }
                            },
                            title: Text(
                              app.appName,
                              style: AppTextStyles.bodyMedium(context),
                            ),
                            subtitle: Text(
                              '${app.packageName} • ${app.minutesToday}m today',
                              style: AppTextStyles.bodySmall(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            secondary: Icon(
                              isExcluded ? Icons.visibility_off : Icons.visibility,
                              color: isExcluded
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
