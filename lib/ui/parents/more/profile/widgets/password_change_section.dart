import 'package:flutter/material.dart';
import '../../../../shared/shared.dart';

class PasswordChangeSection extends StatefulWidget {
  final Future<void> Function(String oldPassword, String newPassword) onChangePassword;

  const PasswordChangeSection({
    super.key,
    required this.onChangePassword,
  });

  @override
  State<PasswordChangeSection> createState() => _PasswordChangeSectionState();
}

class _PasswordChangeSectionState extends State<PasswordChangeSection> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _showConfirmationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Change Password?',
          style: AppTextStyles.titleLarge(context),
        ),
        content: Text(
          'Are you sure you want to change your password? This action cannot be undone.',
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
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary(context),
              foregroundColor: AppColors.onPrimary(context),
            ),
            child: Text(
              'Confirm',
              style: AppTextStyles.labelLarge(context).copyWith(
                color: AppColors.onPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _changePassword();
    }
  }

  Future<void> _changePassword() async {
    final oldPassword = _oldPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // Validation
    if (oldPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
      _showError('Please fill in all password fields');
      return;
    }

    if (newPassword.length < 6) {
      _showError('New password must be at least 6 characters');
      return;
    }

    if (newPassword != confirmPassword) {
      _showError('New passwords do not match');
      return;
    }

    if (oldPassword == newPassword) {
      _showError('New password must be different from old password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await widget.onChangePassword(oldPassword, newPassword);
      
      // Clear fields on success
      _oldPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Password changed successfully'),
            backgroundColor: AppColors.primary(context),
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error(context),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Change Password',
          style: AppTextStyles.titleMedium(context).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildPasswordField(
          label: 'Old password:',
          controller: _oldPasswordController,
          hintText: 'Enter current password',
        ),
        const SizedBox(height: AppSpacing.md),
        _buildPasswordField(
          label: 'New password:',
          controller: _newPasswordController,
          hintText: 'Enter new password',
        ),
        const SizedBox(height: AppSpacing.md),
        _buildPasswordField(
          label: 'New password confirmation:',
          controller: _confirmPasswordController,
          hintText: 'Confirm new password',
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _showConfirmationDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary(context),
              foregroundColor: AppColors.onPrimary(context),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8.0)),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Change Password',
                    style: AppTextStyles.labelLarge(context).copyWith(
                      color: AppColors.onPrimary(context),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required String hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium(context),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            hintText: hintText,
            border: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(12.0)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
          ),
        ),
      ],
    );
  }
}
