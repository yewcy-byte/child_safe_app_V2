import 'package:flutter/material.dart';
import '../../../../shared/shared.dart';

/// Card displaying device information
class DeviceInfoCard extends StatelessWidget {
  final String deviceModel;

  const DeviceInfoCard({
    super.key,
    required this.deviceModel,
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
              'Device',
              style: AppTextStyles.labelLarge(context).copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              deviceModel,
              style: AppTextStyles.titleMedium(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
