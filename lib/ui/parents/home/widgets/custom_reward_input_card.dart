import 'dart:math';

import 'package:flutter/material.dart';
import '../../../shared/shared.dart';
import '../../../../../services/market_service.dart';

class CustomRewardInputCard extends StatefulWidget {
  final String childId;
  final String childName;

  const CustomRewardInputCard({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<CustomRewardInputCard> createState() => _CustomRewardInputCardState();
}

class _CustomRewardInputCardState extends State<CustomRewardInputCard> {
  final TextEditingController _controller = TextEditingController();
  final MarketService _marketService = MarketService();
  final Random _random = Random();
  bool _saving = false;

  static const List<String> _presets = [
    'Movie Night',
    'New Toy',
    'Ice Cream Trip',
    'Park Adventure',
    'Favorite Dinner',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Custom Reward for ${widget.childName}',
              style: AppTextStyles.titleSmall(
                context,
              ).copyWith(fontWeight: FontWeight.bold),
            ),
            AppSpacing.gapSm,
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Enter reward text',
                border: OutlineInputBorder(),
              ),
            ),
            AppSpacing.gapSm,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            _controller.text =
                                _presets[_random.nextInt(_presets.length)];
                          },
                    icon: const Icon(Icons.casino_outlined),
                    label: const Text('Randomize'),
                  ),
                ),
                AppSpacing.gapSm,
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            final reward = _controller.text.trim();
                            if (reward.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Reward text is required.'),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.error,
                                ),
                              );
                              return;
                            }

                            setState(() {
                              _saving = true;
                            });

                            try {
                              await _marketService.addCustomReward(
                                childId: widget.childId,
                                title: reward,
                              );

                              if (!mounted) {
                                return;
                              }

                              _controller.clear();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Custom reward added.'),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.tertiary,
                                ),
                              );
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _saving = false;
                                });
                              }
                            }
                          },
                    icon: const Icon(Icons.add),
                    label: Text(_saving ? 'Saving...' : 'Add Reward'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
