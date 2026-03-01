import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../shared/shared.dart';
import '../../../models/child_model.dart';
import '../../../services/pairing_service.dart';
import '../children/widgets/pairing_code_dialog.dart';
import 'widgets/enhanced_child_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PairingService _pairingService = PairingService();
  bool _isGeneratingCode = false;

  @override
  void initState() {
    super.initState();
    _ensureFilterSettingsExist();
  }

  Future<void> _ensureFilterSettingsExist() async {
    final parentId = _auth.currentUser?.uid;
    if (parentId == null) return;

    try {
      final childrenSnapshot = await _firestore
          .collection('users')
          .doc(parentId)
          .collection('children')
          .get();

      for (final childDoc in childrenSnapshot.docs) {
        final childId = childDoc.id;
        final settingsDoc = await _firestore
            .collection('users')
            .doc(parentId)
            .collection('children')
            .doc(childId)
            .collection('settings')
            .doc('filter_settings')
            .get();

        if (!settingsDoc.exists) {
          await _firestore
              .collection('users')
              .doc(parentId)
              .collection('children')
              .doc(childId)
              .collection('settings')
              .doc('filter_settings')
              .set({
                'childUID': childId,
                'pornFilterEnabled': true,
                'violenceFilterEnabled': true,
                'scanIntervalSeconds': 3,
                'lastUpdated': FieldValue.serverTimestamp(),
              });
        }
      }
    } catch (e) {
      // Silently handle errors - settings will be created on first access
    }
  }

  Future<void> _showAddChildConfirmation(String parentId) async {
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
      await _generatePairingCode(parentId);
    }
  }

  Future<void> _generatePairingCode(String parentId) async {
    if (_isGeneratingCode) return;

    setState(() => _isGeneratingCode = true);

    try {
      final code = await _pairingService.generatePairingCode(parentId);
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => PairingCodeDialog(code: code),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to generate pairing code',
            style: AppTextStyles.bodyMedium(context),
          ),
          backgroundColor: AppColors.error(context),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingCode = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentUid = _auth.currentUser?.uid;

    if (parentUid == null) {
      return Center(
        child: Text(
          'Please sign in to view dashboard.',
          style: AppTextStyles.bodyMedium(context),
        ),
      );
    }

    return ListView(
      padding: AppSpacing.paddingMd,
      children: [
        Text('Home', style: AppTextStyles.headlineMedium(context)),
        AppSpacing.gapMd,
        Card(
          child: Padding(
            padding: AppSpacing.paddingMd,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add a child device',
                    style: AppTextStyles.titleMedium(context),
                  ),
                ),
                FilledButton(
                  onPressed: _isGeneratingCode
                      ? null
                      : () => _showAddChildConfirmation(parentUid),
                  child: Text(
                    _isGeneratingCode ? 'Generating...' : 'Add Child',
                    style: AppTextStyles.labelLarge(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        AppSpacing.gapLg,
        StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('users')
              .doc(_auth.currentUser?.uid)
              .collection('children')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Card(
                child: Padding(
                  padding: AppSpacing.paddingMd,
                  child: Text(
                    'No connected devices',
                    style: AppTextStyles.bodyMedium(context),
                  ),
                ),
              );
            }

            final children = snapshot.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return ChildModel(
                id: doc.id,
                name: data['name'] ?? 'Unknown Child',
                profileImageUrl: data['profileImageUrl'],
                deviceId: data['deviceId'],
                pairedAt:
                    (data['pairedAt'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
                email: data['email'],
                dateOfBirth: (data['dateOfBirth'] as Timestamp?)?.toDate(),
                age: data['age'],
              );
            }).toList();

            final parentId = parentUid;

            return Column(
              children: [
                ...children.map((child) {
                  return EnhancedChildCard(child: child, parentId: parentId);
                }),
              ],
            );
          },
        ),
      ],
    );
  }
}
