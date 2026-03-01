import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/widgets.dart';

/// Garden page displaying the gamified tomato plant dashboard.
/// 
/// To use a custom background image:
/// 1. Add your image to assets/images/ folder
/// 2. Register it in pubspec.yaml under assets
/// 3. Pass the path to GardenPage constructor:
///    ```dart
///    GardenPage(
///      onProfileButtonPressed: _signOut,
///      backgroundImagePath: 'assets/images/garden_bg.png',
///    )
///    ```
class GardenPage extends StatelessWidget {
  final VoidCallback onProfileButtonPressed;
  final String? backgroundImagePath;

  const GardenPage({
    super.key,
    required this.onProfileButtonPressed,
    this.backgroundImagePath,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: const Center(
          child: Text('Please sign in to view your garden'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: backgroundImagePath != null
            ? BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(backgroundImagePath!),
                  fit: BoxFit.cover,
                ),
              )
            : null,
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              top: 16.0,
              bottom: 0,
            ),
            child: GamifiedDashboardSection(
              childId: user.uid,
            ),
          ),
        ),
      ),
    );
  }
}
