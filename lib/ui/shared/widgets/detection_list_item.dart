import 'package:flutter/material.dart';
import '../../../models/detection_model.dart';
import '../../../utils/time_formatter.dart';
import 'detection_type_badge.dart';
import '../app_spacing.dart';

class DetectionListItem extends StatelessWidget {
  final DetectionModel detection;
  final VoidCallback? onTap;
  final bool showActions;
  final VoidCallback? onDelete;

  const DetectionListItem({
    super.key,
    required this.detection,
    this.onTap,
    this.showActions = false,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: AppSpacing.paddingMd,
          child: Row(
            children: [
              DetectionTypeBadge(
                detectionType: detection.detectionType,
                size: 48,
              ),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detection.appName.isNotEmpty
                          ? detection.appName
                          : detection.packageName,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detection.packageName,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _detectionTypeLabel(),
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          TimeFormatter.formatDetectionTime(detection.timestamp),
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: _getConfidenceColor(colorScheme).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${(detection.confidenceScore * 100).toInt()}%',
                      style: textTheme.labelSmall?.copyWith(
                        color: _getConfidenceColor(colorScheme),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (showActions && onDelete != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: colorScheme.error,
                        size: 20,
                      ),
                      onPressed: onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getConfidenceColor(ColorScheme colorScheme) {
    if (detection.confidenceScore >= 0.8) {
      return colorScheme.error;
    } else if (detection.confidenceScore >= 0.6) {
      return colorScheme.tertiary;
    } else {
      return colorScheme.primary;
    }
  }

  String _detectionTypeLabel() {
    switch (detection.detectionType) {
      case DetectionType.nsfw:
        return 'PORN';
      case DetectionType.gun:
        return 'GUN';
      case DetectionType.gore:
        return 'GORE';
      case DetectionType.grooming:
        return 'GROOMING';
    }
  }
}
