import 'package:flutter/material.dart';
import '../../shared/shared.dart';

class FilterIcon extends StatelessWidget {
  final IconData icon;
  final String label;

  const FilterIcon(this.icon, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          size: AppSpacing.lg,
          color: AppColors.onSurfaceVariant(context),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          style: AppTextStyles.labelSmall(context),
        ),
      ],
    );
  }
}
