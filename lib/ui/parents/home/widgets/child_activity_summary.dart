import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../shared/shared.dart';
import '../../../../models/child_model.dart';
import '../../../../models/detection_model.dart';
import '../../../../models/hive/screen_time_cache.dart';

class ChildActivitySummary extends StatefulWidget {
  final ChildModel child;
  final String parentId;
  final ScrollController scrollController;

  const ChildActivitySummary({
    super.key,
    required this.child,
    required this.parentId,
    required this.scrollController,
  });

  @override
  State<ChildActivitySummary> createState() => _ChildActivitySummaryState();
}

class _ChildActivitySummaryState extends State<ChildActivitySummary> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: AppSpacing.paddingMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${widget.child.name} - Activity Details',
                    style: AppTextStyles.titleMedium(
                      context,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              AppSpacing.gapMd,
              // Tab selector
              Row(
                children: [
                  _buildTabButton('Detections', 0),
                  AppSpacing.gapMd,
                  _buildTabButton('Screen Time', 1),
                  AppSpacing.gapMd,
                  _buildTabButton('App Usage', 2),
                ],
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: AppSpacing.paddingMd.copyWith(top: 0),
            children: [
              if (_selectedTabIndex == 0) _buildDetectionsTab(),
              if (_selectedTabIndex == 1) _buildScreenTimeTab(),
              if (_selectedTabIndex == 2) _buildAppUsageTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedTabIndex == index;
    final primary = Theme.of(context).colorScheme.primary;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Column(
          children: [
            Text(
              label,
              style: AppTextStyles.labelMedium(context)?.copyWith(
                color: isSelected ? primary : null,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(height: 2, color: primary),
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .doc(widget.child.id)
          .collection('detections')
          .where('timestamp', isGreaterThanOrEqualTo: _getTodayStart())
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'No detections today',
                style: AppTextStyles.bodyMedium(context),
              ),
            ),
          );
        }

        final detections = snapshot.data!.docs
            .map((doc) => DetectionModel.fromFirestore(doc))
            .toList();

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: detections.length,
          itemBuilder: (context, index) {
            return _buildDetectionCard(detections[index]);
          },
        );
      },
    );
  }

  Widget _buildDetectionCard(DetectionModel detection) {
    final typeLabel = detection.detectionType.value.toUpperCase();
    final typeColor = _getDetectionColor(detection.detectionType);

    return Card(
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    typeLabel,
                    style: AppTextStyles.labelSmall(
                      context,
                    )?.copyWith(color: typeColor, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTime(detection.timestamp),
                  style: AppTextStyles.bodySmall(context),
                ),
              ],
            ),
            AppSpacing.gapMd,
            Text(detection.appName, style: AppTextStyles.titleSmall(context)),
            AppSpacing.gapSm,
            Row(
              children: [
                Icon(Icons.bar_chart, size: 16, color: Colors.orange),
                AppSpacing.gapXs,
                Text(
                  'Confidence: ${(detection.confidenceScore * 100).toStringAsFixed(1)}%',
                  style: AppTextStyles.bodySmall(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenTimeTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore
          .collection('users')
          .doc(widget.child.id)
          .collection('screenTime')
          .doc('current')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final screenTimeMinutes = data?['totalToday'] as int? ?? 0;
        final screenTimeHours = screenTimeMinutes ~/ 60;
        final remainingMinutes = screenTimeMinutes % 60;

        return Card(
          child: Padding(
            padding: AppSpacing.paddingLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Screen Time Today',
                  style: AppTextStyles.titleMedium(context),
                ),
                AppSpacing.gapLg,
                Container(
                  padding: AppSpacing.paddingLg,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$screenTimeHours h ${remainingMinutes}m',
                        style: AppTextStyles.headlineSmall(context)?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      AppSpacing.gapSm,
                      Text(
                        'Total screen time',
                        style: AppTextStyles.bodyMedium(context)?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppUsageTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore
          .collection('users')
          .doc(widget.child.id)
          .collection('appUsage')
          .doc('current')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'No app usage data',
                style: AppTextStyles.bodyMedium(context),
              ),
            ),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final apps = data?['apps'] as List<dynamic>? ?? [];

        if (apps.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'No app usage data',
                style: AppTextStyles.bodyMedium(context),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: apps.length,
          itemBuilder: (context, index) {
            final appData = apps[index] as Map<String, dynamic>;
            final appName = appData['appName'] as String? ?? 'Unknown App';
            final usageMinutes = appData['minutesToday'] as int? ?? 0;
            final iconBytes = appData['icon'] as List<dynamic>?;

            return _buildAppUsageCard(appName, usageMinutes, iconBytes);
          },
        );
      },
    );
  }

  Widget _buildAppUsageCard(
    String appName,
    int usageMinutes,
    List<dynamic>? iconBytes,
  ) {
    return Card(
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Row(
          children: [
            // App Icon
            if (iconBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  Uint8List.fromList(iconBytes.cast<int>()),
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.apps,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    );
                  },
                ),
              )
            else
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.apps,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            AppSpacing.gapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appName,
                    style: AppTextStyles.bodyMedium(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AppSpacing.gapXs,
                  Text(
                    '${(usageMinutes / 60).toStringAsFixed(1)}h',
                    style: AppTextStyles.bodySmall(context),
                  ),
                  AppSpacing.gapXs,
                  // Progress bar aligned to left
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (usageMinutes / 600).clamp(0.05, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getDetectionColor(DetectionType type) {
    switch (type) {
      case DetectionType.nsfw:
        return Colors.red;
      case DetectionType.gun:
        return Colors.orange;
      case DetectionType.gore:
        return Colors.purple;
      case DetectionType.grooming:
        return Colors.deepOrange;
    }
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Timestamp _getTodayStart() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return Timestamp.fromDate(todayStart);
  }

  String _getFormattedToday() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
