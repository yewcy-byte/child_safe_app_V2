import 'package:flutter/material.dart';
import '../../../../../models/user_profile_model.dart';
import '../../../../shared/shared.dart';

class EmailDisplay extends StatelessWidget {
  final String email;
  final AuthProvider authProvider;

  const EmailDisplay({
    super.key,
    required this.email,
    required this.authProvider,
  });

  @override
  Widget build(BuildContext context) {
    final isGoogleUser = authProvider == AuthProvider.google;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email Address',
          style: AppTextStyles.labelLarge(context).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.outline(context).withValues(alpha: 0.3),
            ),
            borderRadius: const BorderRadius.all(Radius.circular(12.0)),
          ),
          child: Row(
            children: [
              if (isGoogleUser) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.all(Radius.circular(4.0)),
                    border: Border.all(
                      color: AppColors.outline(context).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Image.asset(
                    'assets/google_icon.png',
                    width: 20,
                    height: 20,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.g_mobiledata,
                        size: 20,
                        color: AppColors.onSurfaceVariant(context),
                      );
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  email,
                  style: AppTextStyles.bodyLarge(context).copyWith(
                    color: AppColors.onSurfaceVariant(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
