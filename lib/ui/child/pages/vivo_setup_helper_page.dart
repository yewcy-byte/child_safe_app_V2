import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../shared/shared.dart';

class VivoSetupHelperPage extends StatefulWidget {
  const VivoSetupHelperPage({
    super.key,
    required this.childId,
    required this.initialDontShowAgain,
  });

  final String childId;
  final bool initialDontShowAgain;

  @override
  State<VivoSetupHelperPage> createState() => _VivoSetupHelperPageState();
}

class _VivoSetupHelperPageState extends State<VivoSetupHelperPage> {
  bool _dontShowAgain = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dontShowAgain = widget.initialDontShowAgain;
  }

  Future<void> _savePreferenceAndClose() async {
    if (_saving) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .collection('deviceSettings')
          .doc('vivoSetupHelper')
          .set({
        'dontShowAgain': _dontShowAgain,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(_dontShowAgain);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save preference: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Widget _buildStep(String step) {
    return Padding(
      padding: AppSpacing.paddingXs,
      child: Text(
        step,
        style: AppTextStyles.bodyMedium(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Vivo Setup Helper', style: AppTextStyles.titleLarge(context)),
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lock this app in Recent Apps so it is less likely to be cleared.',
                style: AppTextStyles.bodyMedium(context),
              ),
              AppSpacing.gapMd,
              Card(
                child: Padding(
                  padding: AppSpacing.paddingMd,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStep('1. Open this app.'),
                      _buildStep('2. Swipe up and hold to open Recent Apps.'),
                      _buildStep('3. Tap the app name or icon on this app card.'),
                      _buildStep('4. Tap "Lock" so a padlock appears.'),
                    ],
                  ),
                ),
              ),
              AppSpacing.gapMd,
              SwitchListTile.adaptive(
                value: _dontShowAgain,
                onChanged: (value) {
                  setState(() {
                    _dontShowAgain = value;
                  });
                },
                title: Text(
                  'Don\'t show again',
                  style: AppTextStyles.bodyMedium(context),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _savePreferenceAndClose,
                  child: Text(
                    _saving ? 'Saving...' : 'Done',
                    style: AppTextStyles.labelLarge(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
