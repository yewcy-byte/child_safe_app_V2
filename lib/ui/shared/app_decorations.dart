import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';

class AppDecorations {
  static BoxDecoration cardDecoration(BuildContext context) {
    return BoxDecoration(
      color: AppColors.surface(context),
      borderRadius: const BorderRadius.all(Radius.circular(12.0)),
      border: Border.all(
        color: AppColors.outline(context).withValues(alpha: 0.2),
        width: 1.0,
      ),
    );
  }

  static BoxDecoration elevatedCardDecoration(BuildContext context) {
    return BoxDecoration(
      color: AppColors.surface(context),
      borderRadius: const BorderRadius.all(Radius.circular(12.0)),
      boxShadow: [
        BoxShadow(
          color: AppColors.onSurface(context).withValues(alpha: 0.05),
          blurRadius: 4.0,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  static InputDecoration inputDecoration(BuildContext context, {String? labelText, Widget? prefixIcon}) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: prefixIcon,
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8.0)),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
    );
  }

  static ButtonStyle primaryButtonStyle(BuildContext context) {
    return ElevatedButton.styleFrom(
      minimumSize: const Size(double.infinity, 48.0),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8.0)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
    );
  }

  static ButtonStyle textButtonStyle(BuildContext context) {
    return TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
    );
  }
}
