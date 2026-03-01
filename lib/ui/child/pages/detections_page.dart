import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/detection_model.dart';
import '../../../services/detections_service.dart';
import '../../shared/widgets/detection_list_item.dart';
import '../../shared/app_spacing.dart';
import '../../../utils/time_formatter.dart';

class DetectionsPage extends StatefulWidget {
  final VoidCallback onProfileButtonPressed;

  const DetectionsPage({
    super.key,
    required this.onProfileButtonPressed,
  });

  @override
  State<DetectionsPage> createState() => _DetectionsPageState();
}

class _DetectionsPageState extends State<DetectionsPage> {
  late DetectionsService _detectionsService;
  String? _childId;

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  void _initializeService() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _childId = user.uid;
      _detectionsService = DetectionsService(childId: user.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    if (_childId == null) {
      return Scaffold(
        appBar: _buildAppBar(context),
        body: Center(
          child: Text(
            'Not logged in',
            style: textTheme.bodyLarge,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(context),
      body: StreamBuilder<List<DetectionModel>>(
        stream: _detectionsService.getDetectionsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: colorScheme.error,
                  ),
                  AppSpacing.gapMd,
                  Text(
                    'Error loading detections',
                    style: textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }

          final detections = snapshot.data ?? [];

          if (detections.isEmpty) {
            return _buildEmptyState(context, colorScheme, textTheme);
          }

          return _buildDetectionsList(context, detections, textTheme);
        },
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return AppBar(
      title: Text(
        'Detections',
        style: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
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
                  Text('Log out', style: textTheme.labelLarge),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 80,
            color: colorScheme.outline,
          ),
          AppSpacing.gapLg,
          Text(
            'No inappropriate content detected',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your device is safe and protected',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionsList(
    BuildContext context,
    List<DetectionModel> detections,
    TextTheme textTheme,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: detections.length,
      itemBuilder: (context, index) {
        final detection = detections[index];
        final showDateHeader = _shouldShowDateHeader(detections, index);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showDateHeader)
              _buildDateHeader(context, detection.timestamp, textTheme),
            DetectionListItem(
              detection: detection,
              showActions: false,
            ),
          ],
        );
      },
    );
  }

  bool _shouldShowDateHeader(List<DetectionModel> detections, int index) {
    if (index == 0) return true;
    
    final current = detections[index].timestamp;
    final previous = detections[index - 1].timestamp;
    
    return !_isSameDay(current, previous);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateHeader(
    BuildContext context,
    DateTime timestamp,
    TextTheme textTheme,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateText = TimeFormatter.formatDateOnly(timestamp);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        dateText,
        style: textTheme.labelLarge?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
