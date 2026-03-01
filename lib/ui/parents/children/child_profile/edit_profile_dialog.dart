import 'package:flutter/material.dart';
import '../../../../models/child_model.dart';
import '../../../../services/child_profile_service.dart';
import '../../../shared/shared.dart';
import 'package:intl/intl.dart';

class EditProfileDialog extends StatefulWidget {
  final String parentId;
  final ChildModel child;
  final VoidCallback onProfileUpdated;

  const EditProfileDialog({
    super.key,
    required this.parentId,
    required this.child,
    required this.onProfileUpdated,
  });

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  final ChildProfileService _profileService = ChildProfileService();
  late TextEditingController _nameController;
  DateTime? _selectedDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.child.name);
    _selectedDate = widget.child.dateOfBirth;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().subtract(const Duration(days: 365 * 10)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _showImageSourceDialog() async {
    // TODO: Implement camera/gallery picker when image_picker is available
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Photo'),
        content: const Text('Photo upload will be available soon.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      _showError('Name cannot be empty');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _profileService.updateChildProfile(
        parentId: widget.parentId,
        childId: widget.child.id,
        name: _nameController.text.trim(),
        dateOfBirth: _selectedDate,
      );

      widget.onProfileUpdated();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('Failed to save changes: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: AppSpacing.paddingLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Edit Profile',
                      style: AppTextStyles.titleLarge(context),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                
                // Avatar with edit button
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.child.profileImageUrl != null
                              ? null
                              : colorScheme.primaryContainer,
                          image: widget.child.profileImageUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(widget.child.profileImageUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: widget.child.profileImageUrl == null
                            ? Center(
                                child: Text(
                                  widget.child.getInitials(),
                                  style: AppTextStyles.headlineMedium(context).copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _showImageSourceDialog,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.surface,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.edit,
                              size: 18,
                              color: colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: AppSpacing.xl),
                
                // Name Field
                Text(
                  'Name',
                  style: AppTextStyles.labelLarge(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: 'Enter name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
                
                const SizedBox(height: AppSpacing.lg),
                
                // Date of Birth Field
                Text(
                  'Date of Birth',
                  style: AppTextStyles.labelLarge(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedDate != null
                              ? DateFormat('MM/dd/yyyy').format(_selectedDate!)
                              : 'Select date',
                          style: AppTextStyles.bodyLarge(context).copyWith(
                            color: _selectedDate != null
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Icon(
                          Icons.calendar_today,
                          color: colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: AppSpacing.xl),
                
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isLoading ? null : _saveChanges,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
