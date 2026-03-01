import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../services/ai_summary_service.dart';
import '../../../shared/shared.dart';
import '../../chatbot/chatbot_page.dart';

class AISafetySummaryCard extends StatefulWidget {
  const AISafetySummaryCard({
    super.key,
    required this.parentUid,
    this.childId,
    this.childName,
  });

  final String parentUid;
  final String? childId;
  final String? childName;

  @override
  State<AISafetySummaryCard> createState() => _AISafetySummaryCardState();
}

class _AISafetySummaryCardState extends State<AISafetySummaryCard> {
  final AISummaryService _summaryService = AISummaryService();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _summarySubscription;
  Timer? _clockTicker;
  DateTime _clockNow = DateTime.now();
  String? _lastTriggeredChildId;

  @override
  void initState() {
    super.initState();
    _clockTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {
        _clockNow = DateTime.now();
      });
    });
    // Auto-trigger disabled: AI insights now trigger only on button click
  }

  @override
  void didUpdateWidget(covariant AISafetySummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-trigger disabled: AI insights now trigger only on button click
  }

  @override
  void dispose() {
    _summarySubscription?.cancel();
    _clockTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summaryStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('chat')
        .orderBy('createTime', descending: true)
        .limit(50)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: summaryStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ProcessingShimmerCard();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildCard(
            context,
            insightText: 'No AI insight available yet.',
            lastUpdatedLabel: 'just now',
          );
        }

        final docs = snapshot.data!.docs;
        final summaryDoc = _findLatestSummaryDoc(docs);
        if (summaryDoc == null) {
          return _buildCard(
            context,
            insightText: 'No AI insight available yet.',
            lastUpdatedLabel: 'just now',
          );
        }

        final latest = summaryDoc.data();
        final status = latest['status'];
        final state = status is Map<String, dynamic>
            ? status['state'] as String?
            : status as String?;
        final response = (latest['response'] as String?)?.trim();
        final updatedAt = (latest['createTime'] as Timestamp?)?.toDate();
        final lastUpdatedLabel = _formatRelativeUpdate(updatedAt);

        if (response != null && response.isNotEmpty) {
          final insightLines = _firstLines(response, maxLines: 5);
          return _buildCard(
            context,
            insightText: insightLines,
            lastUpdatedLabel: lastUpdatedLabel,
          );
        }

        if (state == 'PROCESSING') {
          return const _ProcessingShimmerCard();
        }

        return _buildCard(
          context,
          insightText: 'AI summary is not ready yet.',
          lastUpdatedLabel: lastUpdatedLabel,
        );
      },
    );
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _findLatestSummaryDoc(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final selectedChildId = widget.childId;
    for (final doc in docs) {
      final data = doc.data();
      final isSummary = data['requestType'] == 'child_safety_summary';
      if (!isSummary) {
        continue;
      }

      if (selectedChildId == null || selectedChildId.isEmpty) {
        return doc;
      }

      if (data['childId'] == selectedChildId) {
        return doc;
      }
    }

    return null;
  }

  Widget _buildCard(
    BuildContext context, {
    required String insightText,
    required String lastUpdatedLabel,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: colorScheme.onPrimaryContainer,
                  size: AppSpacing.lg,
                ),
                AppSpacing.gapSm,
                Text(
                  'AI Insight',
                  style: AppTextStyles.titleMedium(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            AppSpacing.gapSm,
            _InsightPreview(text: _sanitizeInsightText(insightText)),
            AppSpacing.gapXs,
            Text(
              'Last updated $lastUpdatedLabel',
              style: AppTextStyles.bodySmall(context),
            ),
            AppSpacing.gapMd,
            Align(
              alignment: Alignment.centerRight,
              child: _RainbowBorderButton(
                onPressed: () async {
                  try {
                    final docRef = await _summaryService.startConsultantSession(
                      childId: widget.childId,
                      childName: widget.childName,
                    );

                    if (mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatbotPage(
                            childId: widget.childId,
                            childName: widget.childName,
                            sessionId: docRef.id,
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (!mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Unable to start session: $e'),
                        backgroundColor: AppColors.error(context),
                      ),
                    );
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 18),
                    AppSpacing.gapXs,
                    const Text('Talk to AI Consultant'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _firstLines(String text, {required int maxLines}) {
    if (text.trim().isEmpty) {
      return 'AI summary is not ready yet.';
    }

    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) {
      return 'AI summary is not ready yet.';
    }

    return lines.take(maxLines).join('\n');
  }

  String _sanitizeInsightText(String input) {
    final normalized = input.trim();
    final prefixes = <RegExp>[
      RegExp(r'^here\s+is\s+a\s+summary\s+of\s+the\s+log\s+message\s*[:\-]?\s*', caseSensitive: false),
      RegExp(r'^summary\s*[:\-]\s*', caseSensitive: false),
      RegExp(r'^here\s+is\s+the\s+summary\s*[:\-]?\s*', caseSensitive: false),
    ];

    var cleaned = normalized;
    for (final pattern in prefixes) {
      cleaned = cleaned.replaceFirst(pattern, '');
    }

    return cleaned.isEmpty ? normalized : cleaned;
  }

  String _formatRelativeUpdate(DateTime? timestamp) {
    if (timestamp == null) {
      return 'just now';
    }

    final difference = _clockNow.difference(timestamp);
    if (difference.inMinutes <= 0) {
      return 'just now';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    }

    if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    }

    return DateFormat('MMM d, h:mm a').format(timestamp);
  }
}

class _InsightPreview extends StatelessWidget {
  const _InsightPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: AppSpacing.xl + AppSpacing.xl + AppSpacing.sm,
      child: Stack(
        children: [
          Positioned.fill(
            child: Text(
              text,
              maxLines: 5,
              overflow: TextOverflow.clip,
              style: AppTextStyles.bodyMedium(context),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              child: Container(
                height: AppSpacing.lg,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colorScheme.primaryContainer.withValues(alpha: 0),
                      colorScheme.primaryContainer,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessingShimmerCard extends StatefulWidget {
  const _ProcessingShimmerCard();

  @override
  State<_ProcessingShimmerCard> createState() => _ProcessingShimmerCardState();
}

class _ProcessingShimmerCardState extends State<_ProcessingShimmerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Insight',
              style: AppTextStyles.titleMedium(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            AppSpacing.gapSm,
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final progress = _controller.value;
                final opacity = 0.35 + (math.sin(progress * math.pi * 2) + 1) * 0.2;
                return Opacity(
                  opacity: opacity,
                  child: child,
                );
              },
              child: Column(
                children: [
                  Container(
                    height: AppSpacing.md,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                    ),
                  ),
                  AppSpacing.gapSm,
                  Container(
                    height: AppSpacing.md,
                    width: MediaQuery.sizeOf(context).width * 0.6,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.gapMd,
            const Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 148,
                child: LinearProgressIndicator(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/// Button with rainbow gradient border (Gemini themed)
class _RainbowBorderButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;

  const _RainbowBorderButton({
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF0000), // Red
            Color(0xFFFF7F00), // Orange
            Color(0xFFFFFF00), // Yellow
            Color(0xFF00FF00), // Green
            Color(0xFF0000FF), // Blue
            Color(0xFF4B0082), // Indigo
            Color(0xFF9400D3), // Violet
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xs,
        horizontal: AppSpacing.xs,
      ),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const SizedBox(),
        label: child,
      ),
    );
  }
}