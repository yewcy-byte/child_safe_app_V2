import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/child_model.dart';
import '../../../services/pairing_service.dart';
import '../../shared/shared.dart';
import 'child_profile/child_profile_page.dart';
import 'widgets/child_card.dart';
import 'widgets/add_child_card.dart';
import 'widgets/pairing_code_dialog.dart';

class ChildrenPage extends StatefulWidget {
  const ChildrenPage({super.key});

  @override
  State<ChildrenPage> createState() => _ChildrenPageState();
}

class _ChildrenPageState extends State<ChildrenPage> {
  late final PairingService _pairingService;
  late final String _parentId;
  bool _isGeneratingCode = false;

  @override
  void initState() {
    super.initState();
    _parentId = FirebaseAuth.instance.currentUser!.uid;
    _pairingService = PairingService();
  }

  Future<void> _showAddChildConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Generate Pairing Code?',
          style: AppTextStyles.titleLarge(context),
        ),
        content: Text(
          'A pairing code will be generated to link your child\'s device. This code will be valid for 15 minutes. Do you want to proceed?',
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
            child: Text(
              'Generate Code',
              style: AppTextStyles.labelLarge(context),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _generatePairingCode();
    }
  }

  Future<void> _generatePairingCode() async {
    setState(() => _isGeneratingCode = true);

    try {
      final code = await _pairingService.generatePairingCode(_parentId);
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => PairingCodeDialog(code: code),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Failed to generate pairing code');
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingCode = false);
      }
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error(context),
      ),
    );
  }

  void _navigateToChildProfile(ChildModel child) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChildProfilePage(
          parentId: _parentId,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_parentId)
            .collection('children')
            .orderBy('pairedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: AppTextStyles.bodyMedium(context),
              ),
            );
          }

          final children = snapshot.data?.docs ?? [];
          final itemCount = children.length + 1; // +1 for AddChildCard

          return ListView.builder(
            padding: AppSpacing.paddingMd,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              // AddChildCard is always the last item
              if (index == children.length) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AspectRatio(
                    aspectRatio: 1.0, // Square card
                    child: AddChildCard(
                      onTap: _isGeneratingCode ? () {} : _showAddChildConfirmation,
                    ),
                  ),
                );
              }

              // Child cards
              final child = ChildModel.fromFirestore(children[index]);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: ChildCard(
                    child: child,
                    parentId: _parentId,
                    onTap: () => _navigateToChildProfile(child),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
