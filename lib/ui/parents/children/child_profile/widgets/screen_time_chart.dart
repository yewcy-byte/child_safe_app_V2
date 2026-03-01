import 'package:flutter/material.dart';
import '../../../../shared/shared.dart';
import '../models/screen_time_data.dart';

/// Widget displaying 7-day screen time as horizontal bar chart
/// Latest day is on top, bars scaled to the maximum value
class ScreenTimeChart extends StatelessWidget {
  final ScreenTimeData data;

  const ScreenTimeChart({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Screen Time Overview',
              style: AppTextStyles.titleMedium(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Daily Average
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily Average',
                      style: AppTextStyles.bodySmall(context).copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${data.dailyAverage.toStringAsFixed(1)}h',
                      style: AppTextStyles.headlineSmall(context).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            // 7-Day Chart
            Text(
              'Past 7 Days',
              style: AppTextStyles.bodyMedium(context).copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ...data.last7Days.reversed.map((day) {
              final percentage = day.minutes / data.maxMinutes;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        day.dayLabel,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          // Background bar
                          Container(
                            height: 24,
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          // Progress bar
                          FractionallySizedBox(
                            widthFactor: percentage,
                            child: Container(
                              height: 24,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          // Duration text
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  day.formattedDuration,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: percentage > 0.5
                                        ? colorScheme.onPrimary
                                        : colorScheme.onSurface,
                                    fontWeight: FontWeight.w500,
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
              );
            }),
          ],
        ),
      ),
    );
  }
}
