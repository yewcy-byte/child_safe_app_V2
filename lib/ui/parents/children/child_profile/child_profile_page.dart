import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/child_model.dart';
import '../../../../services/child_profile_service.dart';
import '../../../shared/shared.dart';
import 'edit_profile_dialog.dart';
import 'filter_config_sheet.dart';
import 'widgets/device_info_card.dart';
import 'widgets/protection_card.dart';

class ChildProfilePage extends StatefulWidget {
  final String parentId;
  final ChildModel child;

  const ChildProfilePage({
    super.key,
    required this.parentId,
    required this.child,
  });

  @override
  State<ChildProfilePage> createState() => _ChildProfilePageState();
}

class _ChildProfilePageState extends State<ChildProfilePage> {
  final ChildProfileService _profileService = ChildProfileService();

  void _showEditProfile() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditProfileDialog(
        parentId: widget.parentId,
        child: widget.child,
        onProfileUpdated: () {
          // Refresh will happen automatically via stream
        },
      ),
    );
  }

  void _showFilterConfig() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FilterConfigSheet(
        parentId: widget.parentId,
        childId: widget.child.id,
        onSettingsUpdated: () {
          // Settings updated
        },
      ),
    );
  }

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
          'Child Profile',
          style: AppTextStyles.titleLarge(context),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: StreamBuilder<ChildModel>(
        stream: _profileService.getChildProfile(widget.parentId, widget.child.id),
        builder: (context, snapshot) {
          final child = snapshot.data ?? widget.child;

          return SingleChildScrollView(
            padding: AppSpacing.paddingMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Edit Button
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: _showEditProfile,
                    icon: const Icon(Icons.edit),
                    tooltip: 'Edit Profile',
                  ),
                ),
                
                // Profile Header (Avatar + Name + Age)
                Center(
                  child: Column(
                    children: [
                      // Avatar
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: child.profileImageUrl != null
                              ? null
                              : colorScheme.primaryContainer,
                          image: child.profileImageUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(child.profileImageUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: child.profileImageUrl == null
                            ? Center(
                                child: Text(
                                  child.getInitials(),
                                  style: AppTextStyles.headlineMedium(context).copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // Name and Age
                      Text(
                        _buildNameWithAge(child),
                        style: AppTextStyles.headlineSmall(context).copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: AppSpacing.xl),
                
                // Device Info Card
                DeviceInfoCard(
                  deviceModel: 'Device', // TODO: Get from child model
                ),
                
                const SizedBox(height: AppSpacing.lg),

                // Protection Card
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(widget.parentId)
                      .collection('children')
                      .doc(child.id)
                      .collection('settings')
                      .doc('protection_status')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data() as Map<String, dynamic>?;
                    final shieldActive = data?['shieldActive'] as bool? ?? false;
                    return ProtectionCard(
                      isActive: shieldActive,
                      onToggle: (enabled) => _profileService.toggleProtection(
                        parentId: widget.parentId,
                        childId: child.id,
                        enabled: enabled,
                      ),
                      onConfigureFilters: _showFilterConfig,
                    );
                  },
                ),
                
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          );
        },
      ),
    );
  }

  String _buildNameWithAge(ChildModel child) {
    if (child.age != null) {
      return '${child.name}, ${child.age}';
    }
    return child.name;
  }

  Widget _buildEmptySection(String message) {
    return Card(
      child: Padding(
        padding: AppSpacing.paddingLg,
        child: Center(
          child: Text(
            message,
            style: AppTextStyles.bodyMedium(context).copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
