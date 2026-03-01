import 'package:flutter/material.dart';
import '../../../../shared/shared.dart';

/// Card displaying child protection status with toggle and configure button
class ProtectionCard extends StatelessWidget {
  final bool isActive;
  final ValueChanged<bool> onToggle;
  final VoidCallback onConfigureFilters;

  const ProtectionCard({
    super.key,
    required this.isActive,
    required this.onToggle,
    required this.onConfigureFilters,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Child Protection Status',
              style: AppTextStyles.labelLarge(context).copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Protection',
                      style: AppTextStyles.titleMedium(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      isActive
                          ? 'Protection is currently active'
                          : 'Protection is currently inactive',
                      style: AppTextStyles.bodySmall(context).copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: isActive,
                  onChanged: onToggle,
                  activeTrackColor: colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onConfigureFilters,
                child: const Text('Configure Filters'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
