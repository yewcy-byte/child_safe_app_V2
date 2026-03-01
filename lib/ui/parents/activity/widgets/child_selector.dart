import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/child_model.dart';
import '../providers/activity_provider.dart';

/// Child selector dropdown widget
/// Shows avatar, name, and online status
class ChildSelector extends ConsumerWidget {
  final List<ChildModel> children;

  const ChildSelector({super.key, required this.children});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedChildId = ref.watch(selectedChildIdProvider);
    final colorScheme = Theme.of(context).colorScheme;

    if (children.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.child_care, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(
              'No children linked',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final selectedChild = children.firstWhere(
      (c) => c.id == selectedChildId,
      orElse: () => children.first,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedChild.id,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          items: children.map((child) {
            return DropdownMenuItem<String>(
              value: child.id,
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.primaryContainer,
                    backgroundImage: child.profileImageUrl != null
                        ? NetworkImage(child.profileImageUrl!)
                        : null,
                    child: child.profileImageUrl == null
                        ? Text(
                            child.getInitials(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // Name and status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          child.name.isNotEmpty ? child.name : 'Unnamed Child',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  // Online status dot
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (childId) {
            if (childId != null) {
              ref.read(selectedChildIdProvider.notifier).state = childId;
              // Load data for selected child
              ref.read(activityProvider.notifier).loadChildData(childId);
            }
          },
        ),
      ),
    );
  }
}
