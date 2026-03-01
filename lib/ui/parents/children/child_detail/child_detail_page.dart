import 'package:flutter/material.dart';
import '../../../../models/child_model.dart';
import '../../../shared/shared.dart';

/// Empty page for child details
/// Will be implemented with full features later
class ChildDetailPage extends StatelessWidget {
  final ChildModel child;

  const ChildDetailPage({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          child.name,
          style: AppTextStyles.titleLarge(context),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primaryContainer,
              ),
              child: Center(
                child: Text(
                  child.getInitials(),
                  style: AppTextStyles.headlineMedium(context).copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              child.name,
              style: AppTextStyles.headlineSmall(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Child details coming soon',
              style: AppTextStyles.bodyLarge(context).copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
