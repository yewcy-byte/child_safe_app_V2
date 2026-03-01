import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../services/market_service.dart';
import '../../shared/shared.dart';

final marketServiceProvider = Provider<MarketService>((ref) {
  return MarketService();
});

final tomatoBalanceProvider = StreamProvider.family<int, String>((ref, uid) {
  return ref.watch(marketServiceProvider).watchTomatoBalance(uid);
});

final inventoryCountProvider = StreamProvider.family<int, String>((ref, uid) {
  return ref.watch(marketServiceProvider).watchInventoryCount(uid);
});

final inventoryItemsProvider =
    StreamProvider.family<List<InventoryItem>, String>((ref, uid) {
      return ref.watch(marketServiceProvider).watchInventory(uid);
    });

final customRewardsProvider =
    StreamProvider.family<List<CustomReward>, String>((ref, uid) {
      return ref.watch(marketServiceProvider).watchAvailableCustomRewards(uid);
    });

class MarketPage extends ConsumerWidget {
  const MarketPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please sign in to open Market.',
            style: AppTextStyles.bodyMedium(context),
          ),
        ),
      );
    }

    final uid = user.uid;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/market_bg.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: AppSpacing.paddingMd,
              child: Column(
                children: [
                  _MarketTopBar(uid: uid),
                  AppSpacing.gapMd,
                  Expanded(
                    child: _MarketGrid(uid: uid),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketTopBar extends ConsumerWidget {
  final String uid;

  const _MarketTopBar({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tomatoAsync = ref.watch(tomatoBalanceProvider(uid));
    final inventoryCountAsync = ref.watch(inventoryCountProvider(uid));

    final inventoryCount = inventoryCountAsync.value ?? 0;
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: AppSpacing.paddingMd,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.85),
              borderRadius: BorderRadius.circular(AppSpacing.md),
            ),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/tomatoIcon.png',
                  width: 24,
                  height: 24,
                ),
                AppSpacing.gapSm,
                tomatoAsync.when(
                  data: (value) => Text(
                    'Tomatoes: $value',
                    style: AppTextStyles.titleMedium(
                      context,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                  loading: () => Text(
                    'Tomatoes: ...',
                    style: AppTextStyles.titleMedium(
                      context,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                  error: (_, __) => Text(
                    'Tomatoes: 0',
                    style: AppTextStyles.titleMedium(
                      context,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        AppSpacing.gapMd,
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton.filledTonal(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InventoryPage(uid: uid),
                  ),
                );
              },
              icon: const Icon(Icons.inventory_2_outlined),
            ),
            if (inventoryCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    borderRadius: BorderRadius.circular(AppSpacing.md),
                  ),
                  child: Text(
                    '$inventoryCount',
                    style: AppTextStyles.labelSmall(context).copyWith(
                      color: theme.colorScheme.onError,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MarketGrid extends ConsumerWidget {
  final String uid;

  const _MarketGrid({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewardsAsync = ref.watch(customRewardsProvider(uid));
    final tomatoAsync = ref.watch(tomatoBalanceProvider(uid));
    final tomatoes = tomatoAsync.value ?? 0;

    return rewardsAsync.when(
      data: (rewards) {
        final entries = <_MarketEntry>[
          const _MarketEntry.fixedScreenTime(
            title: '30 Mins Extra Time',
            cost: MarketService.item30MinCost,
            minutes: 30,
          ),
          const _MarketEntry.fixedScreenTime(
            title: '120 Mins Extra Time',
            cost: MarketService.item120MinCost,
            minutes: 120,
          ),
          ...rewards.map(_MarketEntry.customReward),
        ];

        return GridView.builder(
          itemCount: entries.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (context, index) {
            final item = entries[index];
            return _ItemCard(
              uid: uid,
              entry: item,
              tomatoBalance: tomatoes,
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text(
          'Unable to load market items.',
          style: AppTextStyles.bodyMedium(context),
        ),
      ),
    );
  }
}
class _ItemCard extends ConsumerWidget {
  final String uid;
  final _MarketEntry entry;
  final int tomatoBalance;

  const _ItemCard({
    required this.uid,
    required this.entry,
    required this.tomatoBalance,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canBuy = tomatoBalance >= entry.cost;
    final isCustomReward = entry.customReward != null;

    final containerDecoration = BoxDecoration(
      color: theme.colorScheme.surface.withOpacity(0.88),
      borderRadius: BorderRadius.circular(AppSpacing.md),
      // Only show border for non-custom items
      border: !isCustomReward
          ? Border.all(
              color: entry.isGoldenTicket
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.outlineVariant,
              width: AppSpacing.xs,
            )
          : null,
    );

    final cardContent = Container(
      padding: AppSpacing.paddingMd,
      decoration: containerDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.isGoldenTicket)
            Expanded(
              child: Center(
                child: Image.asset(
                  'assets/golden_ticket.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.confirmation_num_outlined,
                      size: AppSpacing.xxl,
                      color: theme.colorScheme.secondary,
                    );
                  },
                ),
              ),
            )
          else
            Icon(
              Icons.timer_outlined,
              size: AppSpacing.xl,
              color: theme.colorScheme.primary,
            ),
          AppSpacing.gapSm,
          Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleSmall(
              context,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
          if (entry.parentText != null) ...[
            AppSpacing.gapXs,
            Text(
              entry.parentText!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall(context),
            ),
          ],
          AppSpacing.gapSm,
          Row(
            children: [
              Image.asset(
                'assets/images/tomatoIcon.png',
                width: AppSpacing.md,
                height: AppSpacing.md,
              ),
              AppSpacing.gapXs,
              Text(
                '${entry.cost}',
                style: AppTextStyles.labelLarge(
                  context,
                ).copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canBuy
                  ? () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final service = ref.read(marketServiceProvider);
                      bool success = false;

                      if (entry.minutes != null) {
                        success = await service.purchaseScreenTimeItem(
                          uid: uid,
                          minutes: entry.minutes!,
                          cost: entry.cost,
                        );
                      } else if (entry.customReward != null) {
                        success = await service.purchaseGoldenTicket(
                          uid: uid,
                          reward: entry.customReward!,
                        );
                      }

                      if (!context.mounted) {
                        return;
                      }

                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? 'Purchased successfully!'
                                : 'Not enough tomatoes.',
                          ),
                          backgroundColor: success
                              ? Theme.of(context).colorScheme.tertiary
                              : Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  : null,
              child: const Text('BUY'),
            ),
          ),
        ],
      ),
    );

    // Wrap with animated golden border if custom reward
    if (isCustomReward) {
      return _AnimatedGoldenBorder(child: cardContent);
    }

    return cardContent;
  }
}

/// Animated gradient border for custom rewards
class _AnimatedGoldenBorder extends StatefulWidget {
  final Widget child;

  const _AnimatedGoldenBorder({required this.child});

  @override
  State<_AnimatedGoldenBorder> createState() => _AnimatedGoldenBorderState();
}

class _AnimatedGoldenBorderState extends State<_AnimatedGoldenBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    // Auto-start when entering market page
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Calculate swirling gradient rotation
        final angle = _controller.value * 2 * math.pi; // 2π for full rotation
        final begin = Alignment(
          0.5 + 0.5 * math.cos(angle),
          0.5 + 0.5 * math.sin(angle),
        );
        final end = Alignment(
          0.5 - 0.5 * math.cos(angle),
          0.5 - 0.5 * math.sin(angle),
        );

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFFD700)],
              begin: begin,
              end: end,
            ),
            borderRadius: BorderRadius.circular(AppSpacing.md),
          ),
          padding: const EdgeInsets.all(2),
          child: widget.child,
        );
      },
    );
  }
}

class InventoryPage extends ConsumerStatefulWidget {
  final String uid;

  const InventoryPage({super.key, required this.uid});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  bool _dialogActionHandled = false;
  final GlobalKey _captureKey = GlobalKey();

  Future<void> _captureAndShareTicket(String rewardText) async {
    try {
      final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to capture ticket')),
        );
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Failed to convert image to bytes');
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/golden_ticket.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      final message = 'Check out my earned reward: $rewardText 🎉';
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: message,
        subject: 'My Earned Golden Ticket',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing: $e')),
      );
    }
  }  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inventoryItemsProvider(widget.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
      ),
      body: itemsAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(
                'No items in inventory.',
                style: AppTextStyles.bodyMedium(context),
              ),
            );
          }

          return ListView.separated(
            padding: AppSpacing.paddingMd,
            itemCount: items.length,
            separatorBuilder: (_, __) => AppSpacing.gapSm,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: Padding(
                  padding: AppSpacing.paddingMd,
                  child: Row(
                    children: [
                      Icon(
                        item.type == InventoryItemType.screenTime
                            ? Icons.timer
                            : Icons.confirmation_num_outlined,
                      ),
                      AppSpacing.gapMd,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: AppTextStyles.titleSmall(
                                context,
                              ).copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (item.parentText != null)
                              Text(
                                item.parentText!,
                                style: AppTextStyles.bodySmall(context),
                              ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: () async {
                          if (item.type == InventoryItemType.screenTime) {
                            await ref
                                .read(marketServiceProvider)
                                .useScreenTimeInventoryItem(
                                  uid: widget.uid,
                                  item: item,
                                );

                            if (!context.mounted) {
                              return;
                            }

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${item.valueMinutes} minutes added',
                                ),
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.tertiary,
                              ),
                            );
                          } else {
                            await _showGoldenTicketDialog(item);
                          }
                        },
                        child: Text(
                          item.type == InventoryItemType.screenTime
                              ? 'USE'
                              : item.isScanned
                                  ? '✓ COMPLETED'
                                  : 'SHOW QR',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Text(
            'Unable to load inventory.',
            style: AppTextStyles.bodyMedium(context),
          ),
        ),
      ),
    );
  }

  Future<void> _showGoldenTicketDialog(InventoryItem item) async {
    _dialogActionHandled = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final stream = ref
            .read(marketServiceProvider)
            .watchInventoryItem(widget.uid, item.id);

        return Dialog.fullscreen(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snapshot) {
              final isScanned =
                  (snapshot.data?.data()?['isScanned'] as bool?) ?? false;

              if (isScanned && !_dialogActionHandled) {
                _dialogActionHandled = true;
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  await ref.read(marketServiceProvider).consumeGoldenTicket(
                        uid: widget.uid,
                        itemId: item.id,
                      );

                  if (!mounted) {
                    return;
                  }

                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: const Text('Task Complete!'),
                      backgroundColor: Theme.of(
                        this.context,
                      ).colorScheme.tertiary,
                    ),
                  );
                });
              }

              return Scaffold(
                appBar: AppBar(
                  title: const Text('Golden Ticket'),
                ),
                body: SafeArea(
                  child: Padding(
                    padding: AppSpacing.paddingLg,
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: isScanned
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        size: 120,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .tertiary,
                                      ),
                                      AppSpacing.gapMd,
                                      Text(
                                        'Item Completed! 🎉',
                                        style: AppTextStyles
                                            .headlineMedium(context)
                                            .copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      AppSpacing.gapSm,
                                      Text(
                                        'Your parent verified this reward!',
                                        style: AppTextStyles.bodyMedium(context),
                                      ),
                                    ],
                                  )
                                : RepaintBoundary(
                                    key: _captureKey,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Image.asset(
                                          'assets/golden_ticket.png',
                                          fit: BoxFit.contain,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return Icon(
                                              Icons
                                                  .confirmation_num_outlined,
                                              size: AppSpacing.xxl,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                            );
                                          },
                                        ),
                                        // Overlay reward text on ticket
                                        Positioned(
                                          child: Text(
                                            item.parentText ??
                                                'Custom reward',
                                            textAlign: TextAlign.center,
                                            style: AppTextStyles
                                                .headlineSmall(context)
                                                .copyWith(
                                              color: const Color(
                                                  0xFF8B4513), // Brown color
                                              fontWeight: FontWeight.bold,
                                              shadows: [
                                                Shadow(
                                                  offset:
                                                      const Offset(1, 1),
                                                  blurRadius: 2,
                                                  color: Colors.black
                                                      .withOpacity(0.2),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                        if (!isScanned) ...[
                          AppSpacing.gapMd,
                          QrImageView(
                            data: item.id,
                            size: 220,
                            backgroundColor:
                                Theme.of(context).colorScheme.surface,
                          ),
                          AppSpacing.gapSm,
                          Text(
                            'Show this QR to your parent',
                            style: AppTextStyles.bodyMedium(context),
                          ),
                          AppSpacing.gapLg,
                          ElevatedButton.icon(
                            onPressed: () {
                              final rewardText =
                                  item.parentText ?? 'Custom reward';
                              _captureAndShareTicket(rewardText);
                            },
                            icon: const Icon(Icons.share),
                            label: const Text('Share Golden Ticket'),
                          ),
                        ] else
                          Column(
                            children: [
                              AppSpacing.gapMd,
                              FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                },
                                icon: const Icon(Icons.check),
                                label: const Text('Close'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _MarketEntry {
  final String title;
  final int cost;
  final int? minutes;
  final CustomReward? customReward;
  final String? parentText;

  const _MarketEntry.fixedScreenTime({
    required this.title,
    required this.cost,
    required this.minutes,
  }) : customReward = null,
       parentText = null;

  _MarketEntry.customReward(CustomReward reward)
    : title = 'Golden Ticket',
      cost = MarketService.goldenTicketCost,
      minutes = null,
      customReward = reward,
      parentText = reward.title;

  bool get isGoldenTicket => customReward != null;
}
