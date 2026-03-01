import 'package:flutter/material.dart';
import '../../../../shared/shared.dart';
import '../models/app_usage_data.dart';

/// Widget displaying top 3 most used apps with bar chart
class AppUsageChart extends StatelessWidget {
  final AppUsageData data;
  final VoidCallback onShowMore;

  const AppUsageChart({
    super.key,
    required this.data,
    required this.onShowMore,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final topApps = data.top3Apps;

    return Card(
      elevation: 0,
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Most Used Apps',
                  style: AppTextStyles.titleMedium(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  onPressed: onShowMore,
                  child: const Text('Show More'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...topApps.map((app) {
              final percentage = app.minutesToday / data.maxMinutes;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    // App Icon placeholder
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          app.appName.substring(0, 1).toUpperCase(),
                          style: textTheme.titleMedium?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.appName,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Stack(
                            children: [
                              // Background bar
                              Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              // Progress bar
                              FractionallySizedBox(
                                widthFactor: percentage,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: colorScheme.tertiary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      app.formattedToday,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
