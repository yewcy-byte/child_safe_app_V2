import 'package:flutter/material.dart';
import '../widgets/rule_tile.dart';
import '../../shared/shared.dart';

class RulesPage extends StatelessWidget {
  final VoidCallback onProfileButtonPressed;

  const RulesPage({super.key, required this.onProfileButtonPressed});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rules'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (value) {
              if (value == 'logout') {
                onProfileButtonPressed();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: AppSpacing.lg),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Log out',
                      style: AppTextStyles.labelLarge(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.paddingLg,
        children: const [
          RuleTile(
            title: 'What is blocked',
            text:
                'Adult content, strong violence, and unsafe images/videos are blocked automatically.',
          ),
          RuleTile(
            title: 'What happens if unsafe content appears',
            text:
                'The content is hidden and a friendly message will appear instead.',
          ),
          RuleTile(
            title: 'What parents can see',
            text:
                'Parents can see safety alerts and app activity to keep you safe.',
          ),
        ],
      ),
    );
  }
}
