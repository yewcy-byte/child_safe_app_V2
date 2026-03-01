import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../models/hive/app_usage_cache.dart';

/// Bottom sheet showing full list of apps
class AppListBottomSheet extends StatelessWidget {
  final List<AppUsageCache> apps;

  const AppListBottomSheet({
    super.key,
    required this.apps,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.apps,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'All Apps (${apps.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: colorScheme.outlineVariant),

          // App List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: apps.length,
              itemBuilder: (context, index) {
                final app = apps[index];
                return _buildAppListTile(context, app, index + 1);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppListTile(BuildContext context, AppUsageCache app, int rank) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rank
          Container(
            width: 24,
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Icon
          _buildAppIcon(context, app),
        ],
      ),
      title: Text(
        app.appName,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        'Avg: ${app.formattedWeeklyAverage}/day',
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            app.formattedToday,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            'Yesterday: ${app.minutesYesterday ~/ 60}h ${app.minutesYesterday % 60}m',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
}
