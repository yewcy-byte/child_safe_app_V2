import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/shared.dart';
import '../../../../models/child_model.dart';
import '../../../../models/detection_model.dart';
import '../../../../services/filter_settings_service.dart';
import '../../../../services/ai_summary_service.dart';
import '../../filter_settings/filter_settings_page.dart';
import '../../activity/providers/activity_provider.dart';
import '../../parent_dashboard_scope.dart';
import '../../chatbot/chatbot_page.dart';

class EnhancedChildCard extends ConsumerStatefulWidget {
  final ChildModel child;
  final String parentId;

  const EnhancedChildCard({
    super.key,
    required this.child,
    required this.parentId,
  });

  @override
  ConsumerState<EnhancedChildCard> createState() => _EnhancedChildCardState();
}

class _EnhancedChildCardState extends ConsumerState<EnhancedChildCard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FilterSettingsService _filterSettingsService = FilterSettingsService();
  final AISummaryService _summaryService = AISummaryService();

  DateTime _startOfCurrentWeek(DateTime value) {
    final dateOnly = DateTime(value.year, value.month, value.day);
    return dateOnly.subtract(Duration(days: dateOnly.weekday - DateTime.monday));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.1),
            Theme.of(context).colorScheme.primary.withOpacity(0.05),
            Theme.of(context).colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.transparent,
        child: Padding(
          padding: AppSpacing.paddingMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with child name and protection status
              _buildHeader(context),
              AppSpacing.gapMd,
              const Divider(),
              AppSpacing.gapMd,

              // Detection summary
              _buildDetectionSummary(context),
              AppSpacing.gapMd,

              // Native scanner recovery warning
              _buildNativeScanRecoveryWarning(context),
              _buildScanRuntimeWarning(context),
              AppSpacing.gapLg,

              // Action buttons
              _buildActionButtons(context),
              AppSpacing.gapMd,
              Align(
                alignment: Alignment.centerRight,
                child: _RainbowBorderButton(
                  onPressed: () async {
                    try {
                      final docRef = await _summaryService.startConsultantSession(
                        childId: widget.child.id,
                        childName: widget.child.name,
                      );

                      if (mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatbotPage(
                              childId: widget.child.id,
                              childName: widget.child.name,
                              sessionId: docRef.id,
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (!mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Unable to start session: $e'),
                          backgroundColor: AppColors.error(context),
                        ),
                      );
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome, size: 18),
                      AppSpacing.gapXs,
                      const Text('Talk to AI Consultant'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Child name and info
        Expanded(
          child: Row(
            children: [
              // Profile avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  widget.child.name[0].toUpperCase(),
                  style: AppTextStyles.titleMedium(
                    context,
                  )?.copyWith(color: colorScheme.onPrimaryContainer),
                ),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.child.name,
                      style: AppTextStyles.titleMedium(
                        context,
                      ).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Protection status badge
        StreamBuilder<DocumentSnapshot>(
          stream: _firestore
              .collection('users')
              .doc(widget.parentId)
              .collection('children')
              .doc(widget.child.id)
              .collection('settings')
              .doc('protection_status')
              .snapshots(),
          builder: (context, protectionSnapshot) {
            final protectionData =
                protectionSnapshot.data?.data() as Map<String, dynamic>?;
            final isActive =
                (protectionData?['shieldActive'] as bool? ?? false) ||
                (protectionData?['isActive'] as bool? ?? false);

            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: isActive
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isActive ? 'Protected' : 'Inactive',
                style: AppTextStyles.labelSmall(context).copyWith(
                  color: isActive
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDetectionSummary(BuildContext context) {
    final now = DateTime.now();
    final weekStart = _startOfCurrentWeek(now);

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .doc(widget.child.id)
          .collection('detections')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: const SizedBox(
              height: 40,
              child: Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return InkWell(
            onTap: () => _navigateToActivityPage(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: AppSpacing.paddingMd,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: Colors.green, size: 24),
                  AppSpacing.gapMd,
                  Expanded(
                    child: Text(
                      'Your child is protected: No harmful content detected this week',
                      style: AppTextStyles.bodyMedium(context)?.copyWith(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Count detections by type
        int nsfwCount = 0;
        int gunCount = 0;
        int goreCount = 0;
        int groomingCount = 0;

        for (final doc in snapshot.data!.docs) {
          final detection = DetectionModel.fromFirestore(doc);
          switch (detection.detectionType) {
            case DetectionType.nsfw:
              nsfwCount++;
            case DetectionType.gun:
              gunCount++;
            case DetectionType.gore:
              goreCount++;
            case DetectionType.grooming:
              groomingCount++;
          }
        }

        return InkWell(
          onTap: () => _navigateToActivityPage(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: AppSpacing.paddingMd,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_outlined,
                      color: Colors.orange,
                      size: 24,
                    ),
                    AppSpacing.gapMd,
                    Expanded(
                      child: Text(
                        'Protection Summary',
                        style: AppTextStyles.bodyMedium(
                          context,
                        )?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                AppSpacing.gapSm,
                Text(
                  'Blocked: $nsfwCount adult, $gunCount weapons, $goreCount gore, $groomingCount child grooming detected this week',
                  style: AppTextStyles.bodyMedium(context)?.copyWith(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNativeScanRecoveryWarning(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('users')
          .doc(widget.child.id)
          .collection('systemHealth')
          .doc('nativeScanRecovery')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final needsRecovery = data?['requiresRecovery'] as bool? ?? false;
        if (!needsRecovery) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          padding: AppSpacing.paddingSm,
          decoration: BoxDecoration(
            color: colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.error.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colorScheme.onErrorContainer),
              AppSpacing.gapSm,
              Expanded(
                child: Text(
                  'Scanner needs recovery on ${widget.child.name}\'s phone. Ask child to open the app once.',
                  style: AppTextStyles.bodySmall(
                    context,
                  )?.copyWith(color: colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScanRuntimeWarning(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const staleThreshold = Duration(minutes: 4);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('users')
          .doc(widget.child.id)
          .collection('systemHealth')
          .doc('scanRuntimeStatus')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data == null) {
          return const SizedBox.shrink();
        }

        final expectedRunning = data['expectedRunning'] as bool? ?? false;
        final isRunning = data['isRunning'] as bool? ?? true;
        final reason = (data['reason'] as String?) ?? 'unknown';
        final updatedAt = data['updatedAt'] as Timestamp?;
        final heartbeatMissing = updatedAt == null
            ? expectedRunning
            : DateTime.now().difference(updatedAt.toDate()) > staleThreshold;

        if (!expectedRunning || (isRunning && !heartbeatMissing)) {
          return const SizedBox.shrink();
        }

        final reasonText = reason.replaceAll('_', ' ').trim();

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: AppSpacing.sm),
          padding: AppSpacing.paddingSm,
          decoration: BoxDecoration(
            color: colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.error.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.sync_problem_rounded, color: colorScheme.onErrorContainer),
              AppSpacing.gapSm,
              Expanded(
                child: Text(
                  'Scanner is not active on ${widget.child.name}\'s phone. Please restart the app.${reasonText.isNotEmpty ? ' ($reasonText)' : ''}',
                  style: AppTextStyles.bodySmall(
                    context,
                  )?.copyWith(color: colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        // Configure Filter Settings button
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => FilterSettingsPage(
                    parentId: widget.parentId,
                    childId: widget.child.id,
                    childName: widget.child.name,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Configure'),
          ),
        ),
        AppSpacing.gapMd,

        // View Activity Details button
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _navigateToActivityPage(context),
            icon: const Icon(Icons.analytics_outlined),
            label: const Text('Activity'),
          ),
        ),
      ],
    );
  }

  void _navigateToActivityPage(BuildContext context) {
    // Set the selected child in the activity provider
    ref.read(selectedChildIdProvider.notifier).state = widget.child.id;
    ref.read(activityProvider.notifier).loadChildData(widget.child.id);

    ParentDashboardScope.of(context).openActivity(widget.child.id);
  }

  Timestamp _getTodayStart() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return Timestamp.fromDate(todayStart);
  }
}

class _RainbowBorderButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;

  const _RainbowBorderButton({
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(AppSpacing.xl);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.secondary,
            colorScheme.tertiary,
            colorScheme.error,
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
            colorScheme.tertiaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: borderRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.0), // Thinner border
        child: ClipRRect(
          borderRadius: borderRadius,
          child: FilledButton.icon(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.surface,
              foregroundColor: colorScheme.onSurface,
              shape: RoundedRectangleBorder(borderRadius: borderRadius),
              padding: AppSpacing.horizontalMd,
            ),
            icon: const SizedBox(),
            label: child,
          ),
        ),
      ),
    );
  }
}
