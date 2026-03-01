import 'package:flutter/material.dart';
import '../../shared/shared.dart';

class LogoutButton extends StatelessWidget {
  final VoidCallback onLogout;

  const LogoutButton({
    super.key,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: TextButton.icon(
        onPressed: onLogout,
        icon: Icon(
          Icons.logout,
          color: AppColors.error(context),
        ),
        label: Text(
          'Log Out',
          style: AppTextStyles.labelLarge(context).copyWith(
            color: AppColors.error(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          minimumSize: const Size(double.infinity, 48.0),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8.0)),
          ),
        ),
      ),
    );
  }
}
