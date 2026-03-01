import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/material.dart';
import '../../../../models/user_profile_model.dart';
import '../../../../services/user_profile_service.dart';
import '../../../shared/shared.dart';
import '../../components/components.dart';
import '../../../auth/login_page.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/editable_name_field.dart';
import 'widgets/email_display.dart';
import 'widgets/password_change_section.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final UserProfileService _profileService = UserProfileService();
  UserProfileModel? _profile;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getCurrentUserProfile();
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _updateName(String name) async {
    try {
      await _profileService.updateUserName(name);
      setState(() {
        _profile = _profile?.copyWith(name: name);
      });
    } catch (e) {
      throw Exception('Failed to update name: $e');
    }
  }

  Future<void> _changePassword(String oldPassword, String newPassword) async {
    try {
      await _profileService.changePassword(oldPassword, newPassword);
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error logging out: $e'),
          backgroundColor: AppColors.error(context),
        ),
      );
    }
  }

  String _getInitials() {
    if (_profile?.name != null && _profile!.name!.isNotEmpty) {
      return _profileService.getInitials(_profile!.name);
    }
    return '??';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Parent Profile',
            style: AppTextStyles.titleLarge(context),
          ),
          backgroundColor: AppColors.surface(context),
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Your Profile',
            style: AppTextStyles.titleLarge(context),
          ),
          backgroundColor: AppColors.surface(context),
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Error loading profile',
                style: AppTextStyles.titleMedium(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: AppTextStyles.bodyMedium(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: _loadProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final isEmailUser = _profile?.authProvider == AuthProvider.email;

    return Scaffold(
      backgroundColor: AppColors.surface(context),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Parent Profile',
          style: AppTextStyles.titleLarge(context),
        ),
        backgroundColor: AppColors.surface(context),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.paddingMd,
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.lg),
            // Avatar
            ProfileAvatar(
              photoUrl: _profile?.photoUrl,
              initials: _getInitials(),
              size: 100,
            ),
            const SizedBox(height: AppSpacing.xl),
            // Name Field
            Container(
              width: double.infinity,
              padding: AppSpacing.paddingMd,
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: const BorderRadius.all(Radius.circular(12)),
              ),
              child: EditableNameField(
                initialName: _profile?.name,
                onNameChanged: _updateName,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Email Display
            Container(
              width: double.infinity,
              padding: AppSpacing.paddingMd,
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: const BorderRadius.all(Radius.circular(12)),
              ),
              child: EmailDisplay(
                email: _profile?.email ?? '',
                authProvider: _profile?.authProvider ?? AuthProvider.email,
              ),
            ),
            // Password Change Section (only for email users)
            if (isEmailUser) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: AppSpacing.paddingMd,
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                child: PasswordChangeSection(
                  onChangePassword: _changePassword,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            LogoutButton(onLogout: _handleLogout),
          ],
        ),
      ),
    );
  }
}
