import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../parents/parent_dashboard.dart';
import '../child/child_dashboard.dart';
import '../../services/child_account_bootstrap_service.dart';

class RoleSelectionPage extends StatelessWidget {
  final String userId;
  static final ChildAccountBootstrapService _childBootstrapService =
      ChildAccountBootstrapService();

  const RoleSelectionPage({super.key, required this.userId});

  Future<void> _selectRole(BuildContext context, String role) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user is currently signed in');
      }

      String authProvider = 'email';
      for (final provider in user.providerData) {
        if (provider.providerId == 'google.com') {
          authProvider = 'google';
          break;
        }
      }

      final email = user.email?.trim() ?? '';
      final username = email.contains('@')
          ? email.split('@').first.trim()
          : (user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : user.uid);
      final name = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : username;

      await FirebaseFirestore.instance.collection('users').doc(userId).set(
        {
          'role': role,
          'authProvider': authProvider,
          'email': user.email ?? '',
          'photoUrl': user.photoURL,
          'username': username,
          'name': name,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (role == 'child') {
        await _childBootstrapService.ensureChildStructure(userId);
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => role == 'parent' 
              ? const ParentDashboard() 
              : const ChildDashboard(),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Your Role'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Who will be using this app?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                onPressed: () => _selectRole(context, 'parent'),
                icon: const Icon(Icons.family_restroom, size: 32),
                label: const Text('I am a Parent'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 80),
                  textStyle: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _selectRole(context, 'child'),
                icon: const Icon(Icons.child_care, size: 32),
                label: const Text('I am a Child'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 80),
                  textStyle: const TextStyle(fontSize: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
