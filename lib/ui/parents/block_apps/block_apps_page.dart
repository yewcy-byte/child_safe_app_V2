import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/blocked_app_model.dart';
import '../../../models/child_model.dart';
import '../../../services/blocked_apps_service.dart';
import '../../../services/parent_children_service.dart';
import '../../../services/user_profile_service.dart';
import '../../shared/shared.dart';

class BlockAppsPage extends StatefulWidget {
  const BlockAppsPage({super.key});

  @override
  State<BlockAppsPage> createState() => _BlockAppsPageState();
}

class _BlockAppsPageState extends State<BlockAppsPage> {
  final UserProfileService _userProfileService = UserProfileService();
  final ParentChildrenService _childrenService = ParentChildrenService();
  final BlockedAppsService _blockedAppsService = BlockedAppsService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _parentId;
  String? _selectedChildId;
  final Set<String> _pendingBlocks = <String>{};
  final Set<String> _optimisticBlockedPackages = <String>{};

  @override
  void initState() {
    super.initState();
    _parentId = _userProfileService.currentUser?.uid;
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
    final normalizedPackageName = _normalizePackageName(packageName);
    if (normalizedPackageName.isEmpty || _pendingBlocks.contains(normalizedPackageName)) {
      return;
    }

    final result = await _pickBlockedUntil(context);
    if (result == null || result.cancelled) {
      return;
    }

    if (mounted) {
      setState(() {
        _pendingBlocks.add(normalizedPackageName);
      });
    }

    try {
      await _blockedAppsService.upsertBlockedApp(
        parentId: parentId,
        childId: childId,
        appName: appName,
        packageName: normalizedPackageName,
        blockedUntil: result.blockedUntil,
      );

      if (mounted) {
        setState(() {
          _optimisticBlockedPackages.add(normalizedPackageName);
        });
      }
    } catch (e) {
      await _showError(context, 'Failed to block app: $e');
    } finally {
      if (mounted) {
        setState(() {
          _pendingBlocks.remove(normalizedPackageName);
        });
      }
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
      await _showError(context, 'Failed to update block duration: $e');
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

      if (mounted) {
        setState(() {
          _optimisticBlockedPackages.remove(_normalizePackageName(app.packageName));
        });
      }
    } catch (e) {
      await _showError(context, 'Failed to remove block: $e');
    }
  }

  String _normalizePackageName(String value) => value.trim().toLowerCase();

  String _normalizeAppName(String value) => value.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    if (_parentId == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Block Apps', style: AppTextStyles.titleLarge(context)),
        ),
        body: Center(
          child: Text(
            'Please sign in again to manage app blocks.',
            style: AppTextStyles.bodyMedium(context),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Block Apps', style: AppTextStyles.titleLarge(context)),
      ),
      body: StreamBuilder<List<ChildModel>>(
        stream: _childrenService.watchChildren(_parentId!),
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
              if (childId == null)
                Text(
                  'Select a child to view detected apps.',
                  style: AppTextStyles.bodyMedium(context),
                )
              else
                StreamBuilder<List<BlockedAppModel>>(
                  stream: _blockedAppsService.watchBlockedApps(
                    parentId: _parentId!,
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
                      for (final app in blockedApps)
                        _normalizePackageName(app.packageName): app,
                    };
                    final blockedByName = {
                      for (final app in blockedApps) _normalizeAppName(app.appName): app,
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
                                        parentId: _parentId!,
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
                                        parentId: _parentId!,
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
                          'Most used apps',
                          style: AppTextStyles.titleMedium(context),
                        ),
                        AppSpacing.gapSm,
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: _firestore
                              .collection('users')
                              .doc(childId)
                              .collection('appUsage')
                              .doc('current')
                              .snapshots(),
                          builder: (context, usageSnapshot) {
                            if (usageSnapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            final usageData = usageSnapshot.data?.data();
                            final apps = usageData?['apps'] as List<dynamic>? ?? <dynamic>[];
                            final summaries = _summarizeMostUsedApps(apps);

                            if (summaries.isEmpty) {
                              return Text(
                                'No app usage data yet.',
                                style: AppTextStyles.bodyMedium(context),
                              );
                            }

                            return Column(
                              children: summaries.map((summary) {
                                final normalizedPackage =
                                    _normalizePackageName(summary.packageName);
                                final normalizedAppName =
                                    _normalizeAppName(summary.appName);

                                final blocked = blockedByPackage[normalizedPackage] ??
                                    blockedByName[normalizedAppName];
                                final isBlocked = blocked != null ||
                                    _optimisticBlockedPackages
                                        .contains(normalizedPackage);
                                final isSaving = _pendingBlocks.contains(normalizedPackage);

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
                                      '${summary.packageName} • ${summary.minutesToday} min today',
                                      style: AppTextStyles.bodySmall(context),
                                    ),
                                    trailing: isBlocked
                                        ? Text(
                                            'Blocked',
                                            style: AppTextStyles.labelMedium(context).copyWith(
                                              color: AppColors.onSurfaceVariant(context),
                                            ),
                                          )
                                        : FilledButton(
                                            onPressed: isSaving
                                                ? null
                                                : () => _blockApp(
                                              context: context,
                                              parentId: _parentId!,
                                              childId: childId,
                                              appName: summary.appName,
                                              packageName: normalizedPackage,
                                            ),
                                            child: Text(
                                              isSaving ? 'Saving...' : 'Block',
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
            ],
          );
        },
      ),
    );
  }

  List<_MostUsedAppSummary> _summarizeMostUsedApps(List<dynamic> apps) {
    final summaries = apps
        .whereType<Map>()
        .map((raw) => raw.cast<String, dynamic>())
        .map((entry) {
          final packageName =
              _normalizePackageName(entry['packageName'] as String? ?? '');
          if (packageName.isEmpty) {
            return null;
          }

          final appNameRaw = (entry['appName'] as String?)?.trim() ?? '';
          final appName = appNameRaw.isEmpty ? packageName : appNameRaw;
          final minutesToday = (entry['minutesToday'] as num?)?.toInt() ?? 0;

          return _MostUsedAppSummary(
            packageName: packageName,
            appName: appName,
            minutesToday: minutesToday,
          );
        })
        .whereType<_MostUsedAppSummary>()
        .toList(growable: false);

    summaries.sort((a, b) {
      final minutesCompare = b.minutesToday.compareTo(a.minutesToday);
      if (minutesCompare != 0) {
        return minutesCompare;
      }
      return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
    });

    return summaries;
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

class _MostUsedAppSummary {
  final String packageName;
  final String appName;
  final int minutesToday;

  const _MostUsedAppSummary({
    required this.packageName,
    required this.appName,
    required this.minutesToday,
  });
}
