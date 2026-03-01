import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/detection_model.dart';
import '../../../../ui/shared/widgets/detection_list_item.dart';
import '../../../../ui/shared/widgets/detection_type_badge.dart';
import '../providers/activity_provider.dart';
import 'error_banner.dart';

/// Detections card with filtering and sorting
class DetectionsCard extends ConsumerWidget {
  final List<DetectionModel> detections;
  final bool isLoading;

  const DetectionsCard({
    super.key,
    required this.detections,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredDetections = ref.watch(filteredDetectionsProvider);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with filters
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Detections',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Text(
                  '${filteredDetections.length}',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Filters Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Type Filter Dropdown
                  _buildTypeFilterChip(context, ref),
                  const SizedBox(width: 8),
                  // Sort Dropdown
                  _buildSortChip(context, ref),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Content
            if (isLoading)
              _buildLoadingState(context)
            else if (filteredDetections.isEmpty)
              _buildEmptyState(context)
            else
              _buildDetectionsList(context, filteredDetections),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeFilterChip(BuildContext context, WidgetRef ref) {
    final selectedType = ref.watch(detectionTypeFilterProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return ActionChip(
      avatar: Icon(
        Icons.filter_list,
        size: 18,
        color: selectedType != null 
            ? colorScheme.onPrimary 
            : colorScheme.onSurfaceVariant,
      ),
      label: Text(
        selectedType?.value.toUpperCase() ?? 'All Types',
        style: TextStyle(
          fontSize: 12,
          color: selectedType != null 
              ? colorScheme.onPrimary 
              : colorScheme.onSurface,
        ),
      ),
      backgroundColor: selectedType != null 
          ? colorScheme.primary 
          : colorScheme.surfaceContainerHighest,
      side: BorderSide.none,
      onPressed: () => _showTypeFilterMenu(context, ref),
    );
  }

  Widget _buildSortChip(BuildContext context, WidgetRef ref) {
    final sortOrder = ref.watch(sortOrderProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return ActionChip(
      avatar: Icon(
        sortOrder == SortOrder.newestFirst 
            ? Icons.arrow_downward 
            : Icons.arrow_upward,
        size: 18,
        color: colorScheme.onSurfaceVariant,
      ),
      label: Text(
        sortOrder.label,
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurface,
        ),
      ),
      backgroundColor: colorScheme.surfaceContainerHighest,
      side: BorderSide.none,
      onPressed: () {
        ref.read(sortOrderProvider.notifier).state = 
            sortOrder == SortOrder.newestFirst 
                ? SortOrder.oldestFirst 
                : SortOrder.newestFirst;
      },
    );
  }

  void _showTypeFilterMenu(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Filter by Type',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.clear_all),
                title: const Text('All Types'),
                trailing: ref.watch(detectionTypeFilterProvider) == null 
                    ? Icon(Icons.check, color: colorScheme.primary)
                    : null,
                onTap: () {
                  ref.read(detectionTypeFilterProvider.notifier).state = null;
                  Navigator.pop(context);
                },
              ),
              ...DetectionType.values.map((type) {
                final isSelected = ref.watch(detectionTypeFilterProvider) == type;
                return ListTile(
                  leading: DetectionTypeBadge(detectionType: type),
                  title: Text(type.value.toUpperCase()),
                  trailing: isSelected 
                      ? Icon(Icons.check, color: colorScheme.primary)
                      : null,
                  onTap: () {
                    ref.read(detectionTypeFilterProvider.notifier).state = type;
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateRange = DateRangeFilter.sevenDays;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'No detections found',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Great! No inappropriate content detected in the ${dateRange.label.toLowerCase()}.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionsList(BuildContext context, List<DetectionModel> detections) {
    return SizedBox(
      height: 280,
      child: ListView.separated(
        itemCount: detections.length,
        itemBuilder: (context, index) {
          return DetectionListItem(detection: detections[index]);
        },
        separatorBuilder: (context, index) => const SizedBox(height: 8),
      ),
    );
  }
}
