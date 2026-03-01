import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/activity_provider.dart';

/// Date range filter widget with segmented control
class DateRangeFilterWidget extends ConsumerWidget {
  const DateRangeFilterWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFilter = ref.watch(dateRangeFilterProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: DateRangeFilter.values.map((filter) {
          final isSelected = filter == selectedFilter;
          return GestureDetector(
            onTap: () {
              ref.read(dateRangeFilterProvider.notifier).state = filter;
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                filter.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected 
                      ? colorScheme.onPrimary 
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Error banner widget
class ErrorBanner extends ConsumerWidget {
  final String? errorMessage;
  final DateTime? lastSyncTime;

  const ErrorBanner({
    super.key,
    this.errorMessage,
    this.lastSyncTime,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (errorMessage == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    
    String subtitle = 'Pull down to retry';
    if (lastSyncTime != null) {
      final timeAgo = _formatTimeAgo(lastSyncTime!);
      subtitle = 'Last successful sync: $timeAgo';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sync failed',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onErrorContainer.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: colorScheme.onErrorContainer),
            onPressed: () {
              ref.read(activityProvider.notifier).clearError();
            },
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
