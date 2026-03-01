import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/child_model.dart';
import '../../../../services/protection_status_service.dart';
import '../../../shared/shared.dart';

/// Widget that displays a child's information in a square card format
/// Follows the wireframe design with centered avatar, name+age, and shield status
/// Includes 3 status states: Active, Enabled but inactive, Inactive
/// Includes elegant switch toggle to enable/disable protection at top-left
class ChildCard extends StatefulWidget {
  final ChildModel child;
  final String parentId;
  final VoidCallback? onTap;

  const ChildCard({
    super.key,
    required this.child,
    required this.parentId,
    this.onTap,
  });

  @override
  State<ChildCard> createState() => _ChildCardState();
}

class _ChildCardState extends State<ChildCard> {
  final ProtectionStatusService _protectionService = ProtectionStatusService();
  bool _isToggling = false;

  Future<void> _toggleProtection(bool currentShieldActive) async {
    final newState = !currentShieldActive;
    
    // Show confirmation dialog when turning OFF protection
    if (!newState) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Disable Protection?',
            style: AppTextStyles.titleLarge(context),
          ),
          content: Text(
            'Are you sure you want to disable protection for ${widget.child.name}? Their device will no longer be monitored.',
            style: AppTextStyles.bodyMedium(context),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: AppTextStyles.labelLarge(context),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(
                'Disable',
                style: AppTextStyles.labelLarge(context),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() => _isToggling = true);

    try {
      await _protectionService.setShieldActive(
        parentId: widget.parentId,
        childId: widget.child.id,
        enabled: newState,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update protection status'),
            backgroundColor: AppColors.error(context),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isToggling = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final hasPhoto = widget.child.profileImageUrl != null && widget.child.profileImageUrl!.isNotEmpty;
    final initials = widget.child.getInitials();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentId)
          .collection('children')
          .doc(widget.child.id)
          .collection('settings')
          .doc('protection_status')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final isShieldActive = data?['shieldActive'] as bool? ?? false;
        final isActive = data?['isActive'] as bool? ?? false;

        // Determine status
        final (statusText, statusColor, backgroundColor) = _getStatusInfo(
          isShieldActive,
          isActive,
          colorScheme,
        );

        return Card(
          elevation: 2,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: statusColor.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Main content area - centered
                InkWell(
                  onTap: widget.onTap,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Avatar
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasPhoto ? null : statusColor.withValues(alpha: 0.2),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.4),
                              width: 3,
                            ),
                            image: hasPhoto
                                ? DecorationImage(
                                    image: NetworkImage(widget.child.profileImageUrl!),
                                    fit: BoxFit.cover,
                                    onError: (exception, stackTrace) {},
                                  )
                                : null,
                          ),
                          child: hasPhoto
                              ? null
                              : Center(
                                  child: Text(
                                    initials,
                                    style: textTheme.headlineMedium?.copyWith(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        // Name and Age
                        Text(
                          _buildNameWithAge(),
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            statusText,
                            style: textTheme.bodyMedium?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Elegant toggle at top-left - integrated with card design
                Positioned(
                  top: 12,
                  left: 12,
                  child: _isToggling
                      ? Container(
                          width: 72,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                              ),
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: () => _toggleProtection(isShieldActive),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 72,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isShieldActive 
                                  ? statusColor.withValues(alpha: 0.2)
                                  : colorScheme.surface.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isShieldActive 
                                    ? statusColor
                                    : colorScheme.outline.withValues(alpha: 0.5),
                                width: 2,
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Background icons
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Icon(
                                      Icons.shield,
                                      size: 18,
                                      color: isShieldActive 
                                          ? statusColor
                                          : colorScheme.outline.withValues(alpha: 0.3),
                                    ),
                                    Icon(
                                      Icons.shield_outlined,
                                      size: 18,
                                      color: !isShieldActive 
                                          ? colorScheme.outline
                                          : statusColor.withValues(alpha: 0.3),
                                    ),
                                  ],
                                ),
                                // Sliding thumb
                                AnimatedAlign(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                  alignment: isShieldActive 
                                      ? Alignment.centerRight 
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.all(3),
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: isShieldActive ? statusColor : colorScheme.surface,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.shadow.withValues(alpha: 0.25),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      isShieldActive ? Icons.check : Icons.close,
                                      size: 18,
                                      color: isShieldActive 
                                          ? colorScheme.onPrimary
                                          : colorScheme.outline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  (String, Color, Color) _getStatusInfo(
    bool isShieldActive,
    bool isActive,
    ColorScheme colorScheme,
  ) {
    if (isShieldActive && isActive) {
      // Protection is enabled and child device is active
      return (
        'Active',
        colorScheme.primary,
        colorScheme.primaryContainer.withValues(alpha: 0.3),
      );
    } else if (isShieldActive && !isActive) {
      // Protection is enabled but child device is not active
      return (
        'Enabled but inactive',
        colorScheme.tertiary,
        colorScheme.tertiaryContainer.withValues(alpha: 0.3),
      );
    } else {
      // Protection is disabled
      return (
        'Inactive',
        colorScheme.error,
        colorScheme.errorContainer.withValues(alpha: 0.3),
      );
    }
  }

  String _buildNameWithAge() {
    if (widget.child.age != null) {
      return '${widget.child.name}, ${widget.child.age}';
    }
    return widget.child.name;
  }
}
