import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/hive/app_usage_cache.dart';
import 'app_list_bottom_sheet.dart';

/// App usage card showing top 5 apps with horizontal bar charts
class AppUsageCard extends StatelessWidget {
  final AppUsageCacheList appUsage;
  final bool isLoading;

  const AppUsageCard({
    super.key,
    required this.appUsage,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final top5Apps = appUsage.top5Apps;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.bar_chart,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Most Used',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                if (appUsage.apps.length > 5)
                  TextButton(
                    onPressed: () => _showFullList(context),
                    child: const Text('Show More'),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Content
            if (isLoading)
              _buildLoadingState(context)
            else if (top5Apps.isEmpty)
              _buildEmptyState(context)
            else
              _buildAppList(context, top5Apps),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Column(
      children: List.generate(
        5,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 100,
                      height: 12,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.apps_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No app usage data available',
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

  Widget _buildAppList(BuildContext context, List<AppUsageCache> apps) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxMinutes = appUsage.maxMinutes;

    return Column(
      children: apps.map((app) {
        final percentage = maxMinutes > 0 ? app.minutesToday / maxMinutes : 0.0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              // App Icon
              _buildAppIcon(context, app),
              const SizedBox(width: 12),

              // App Info and Bar
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // App Name
                    Text(
                      app.appName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // Progress Bar
                    Stack(
                      children: [
                        // Background
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        // Progress
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

              // Time Label
              Text(
                app.formattedToday,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAppIcon(BuildContext context, AppUsageCache app) {
    final colorScheme = Theme.of(context).colorScheme;

    if (app.iconUrl != null && app.iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: app.iconUrl!,
          width: 40,
          height: 40,
          placeholder: (context, url) => _buildPlaceholderIcon(context, app),
          errorWidget: (context, url, error) => _buildPlaceholderIcon(context, app),
          fit: BoxFit.cover,
        ),
      );
    }

    return _buildPlaceholderIcon(context, app);
  }

  Widget _buildPlaceholderIcon(BuildContext context, AppUsageCache app) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = app.appName.isNotEmpty ? app.appName[0].toUpperCase() : '?';

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  void _showFullList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AppListBottomSheet(
        apps: appUsage.allAppsSorted,
      ),
    );
  }
}
