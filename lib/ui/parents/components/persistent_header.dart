import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../shared/shared.dart';
import '../more/profile/profile_page.dart';
import '../../auth/login_page.dart';

class PersistentHeader extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onInfoPressed;

  const PersistentHeader({
    super.key,
    this.onInfoPressed,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Guarden',
                    style: AppTextStyles.headlineSmall(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'profile') {
                        if (!context.mounted) {
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ProfilePage(),
                          ),
                        );
                      } else if (value == 'logout') {
                        try {
                          await FirebaseAuth.instance.signOut();
                          if (context.mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (context) => const LoginPage()),
                              (Route<dynamic> route) => false,
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error logging out: $e')),
                            );
                          }
                        }
                      }
                    },
                    itemBuilder: (BuildContext context) => [
                      PopupMenuItem<String>(
                        value: 'profile',
                        child: Row(
                          children: [
                            Icon(Icons.person_outline, color: colorScheme.onSurface),
                            const SizedBox(width: 12),
                            Text('Your Profile', style: AppTextStyles.bodyMedium(context)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout, size: 20, color: colorScheme.error),
                            const SizedBox(width: 12),
                            Text(
                              'Logout',
                              style: AppTextStyles.bodyMedium(context).copyWith(
                                color: colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        user?.email?.substring(0, 1).toUpperCase() ?? 'P',
                        style: AppTextStyles.labelLarge(context).copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              thickness: 1,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(65.0);
}
