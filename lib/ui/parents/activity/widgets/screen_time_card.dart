import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../models/hive/screen_time_cache.dart';

/// Screen time card with iOS-style 7-day bar chart
class ScreenTimeCard extends StatelessWidget {
  final ScreenTimeCache screenTime;
  final bool isLoading;

  const ScreenTimeCard({
    super.key,
    required this.screenTime,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalWeek = screenTime.totalWeekMinutes;
    final hours = totalWeek ~/ 60;
    final minutes = totalWeek % 60;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.smartphone,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Screen Time',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        'Total: ${hours}h ${minutes}m (7 days)',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Chart
            if (isLoading)
              _buildLoadingState(context)
            else if (screenTime.dailyMinutes.every((m) => m == 0))
              _buildEmptyState(context)
            else
              _buildChart(context),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.access_time,
              size: 48,
              color: colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No screen time data available',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Data will appear once the child device syncs',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dailyMinutes = screenTime.dailyMinutes;
    final maxMinutes = dailyMinutes.isNotEmpty 
        ? dailyMinutes.reduce((a, b) => a > b ? a : b)
        : 1;
    
    // Day labels (Mon-Sun)
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    
    // Create bar groups
    final barGroups = dailyMinutes.asMap().entries.map((entry) {
      final index = entry.key;
      final minutes = entry.value;
      final isToday = index == dailyMinutes.length - 1;
      final hours = minutes / 60;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: hours,
            color: isToday ? colorScheme.primary : colorScheme.surfaceContainerHighest,
            width: 22,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(4),
            ),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxMinutes / 60,
              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            ),
          ),
        ],
      );
    }).toList();

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (maxMinutes / 60) * 1.2, // Add 20% padding
          barGroups: barGroups,
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= days.length) {
                    return const SizedBox.shrink();
                  }
                  
                  final isToday = index == dailyMinutes.length - 1;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      days[index],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                        color: isToday 
                            ? colorScheme.primary 
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
                reservedSize: 30,
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipPadding: const EdgeInsets.all(8),
              tooltipMargin: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final minutes = dailyMinutes[groupIndex];
                final hours = minutes ~/ 60;
                final mins = minutes % 60;
                
                String timeText;
                if (hours > 0) {
                  timeText = '${hours}h ${mins}m';
                } else {
                  timeText = '${mins}m';
                }

                return BarTooltipItem(
                  timeText,
                  TextStyle(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
        ),
        swapAnimationDuration: const Duration(milliseconds: 500),
        swapAnimationCurve: Curves.easeInOut,
      ),
    );
  }
}
