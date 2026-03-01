import 'package:flutter/material.dart';
import '../../shared/shared.dart';

class RuleTile extends StatelessWidget {
  final String title;
  final String text;

  const RuleTile({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTextStyles.titleSmall(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              text,
              style: AppTextStyles.bodySmall(context).copyWith(
                color: AppColors.onSurfaceVariant(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
