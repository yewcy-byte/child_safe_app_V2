import 'package:flutter/material.dart';
import '../../../../shared/shared.dart';

class ProfileAvatar extends StatelessWidget {
  final String? photoUrl;
  final String initials;
  final double size;

  const ProfileAvatar({
    super.key,
    this.photoUrl,
    required this.initials,
    this.size = 80.0,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasPhoto
            ? null
            : AppColors.primary(context).withValues(alpha: 0.1),
        image: hasPhoto
            ? DecorationImage(
                image: NetworkImage(photoUrl!),
                fit: BoxFit.cover,
                onError: (exception, stackTrace) {
                  // Error handled by fallback
                },
              )
            : null,
      ),
      child: hasPhoto
          ? null
          : Center(
              child: Text(
                initials,
                style: AppTextStyles.headlineMedium(context).copyWith(
                  color: AppColors.primary(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    );
  }
}
