import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';
import '../../../../models/child_model.dart';
import '../../../../ui/shared/shared.dart';
import '../parent_dashboard_scope.dart';
import 'providers/activity_provider.dart';
import 'widgets/child_selector.dart';
import 'widgets/detections_card.dart';
import 'widgets/error_banner.dart';

/// Activity page showing detections per child
/// This is the main monitoring dashboard for parents
class ActivityPage extends ConsumerStatefulWidget {
  final bool embedded;
  final String? childId;

  const ActivityPage({
    super.key,
    this.embedded = false,
    this.childId,
  });

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  final RefreshController _refreshController = RefreshController();

  @override
  void initState() {
    super.initState();
    // Auto-select first child when children are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.childId != null) {
        ref.read(selectedChildIdProvider.notifier).state = widget.childId;
        ref.read(activityProvider.notifier).loadChildData(widget.childId!);
        return;
      }
      _checkAndSelectFirstChild();
    });
  }

  void _checkAndSelectFirstChild() {
    final childrenAsync = ref.read(childrenListProvider);
    final selectedChildId = ref.read(selectedChildIdProvider);
    
    childrenAsync.whenData((children) {
      if (children.isEmpty) {
        return;
      }

      if (selectedChildId == null) {
        // Auto-select first child
        final firstChild = children.first;
        ref.read(selectedChildIdProvider.notifier).state = firstChild.id;
        ref.read(activityProvider.notifier).loadChildData(firstChild.id);
        return;
      }

      final hasSelectedChild = children.any((child) => child.id == selectedChildId);
      if (!hasSelectedChild) {
        final firstChild = children.first;
        ref.read(selectedChildIdProvider.notifier).state = firstChild.id;
        ref.read(activityProvider.notifier).loadChildData(firstChild.id);
        return;
      }

      // Ensure data loads when a child was preselected (e.g., from dashboard)
      ref.read(activityProvider.notifier).loadChildData(selectedChildId);
    });
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activityState = ref.watch(activityProvider);
    final childrenAsync = ref.watch(childrenListProvider);

    final content = SafeArea(
      child: SmartRefresher(
        controller: _refreshController,
        enablePullDown: true,
        onRefresh: _onRefresh,
        child: CustomScrollView(
          slivers: [
            // App Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: AppSpacing.paddingMd,
                child: Row(
                  children: [
                    if (widget.embedded)
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () {
                          ParentDashboardScope.of(context).closeActivity();
                        },
                      ),
                    Expanded(
                      child: Text(
                        'Activity',
                        style: AppTextStyles.headlineMedium(context),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: _showInfoDialog,
                    ),
                  ],
                ),
              ),
            ),

            // Error Banner (if sync failed)
            SliverToBoxAdapter(
              child: Padding(
                padding: AppSpacing.paddingMd.copyWith(top: 0),
                child: ErrorBanner(
                  errorMessage: activityState.syncError,
                  lastSyncTime: activityState.lastSyncTime,
                ),
              ),
            ),

            // Main Content Cards
            SliverPadding(
              padding: AppSpacing.paddingMd.copyWith(top: 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Detections Card
                  DetectionsCard(
                    detections: activityState.detections.value ?? [],
                    isLoading: activityState.detections.isLoading,
                  ),
                  AppSpacing.gapLg,
                ]),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      body: content,
    );
  }

  Future<void> _onRefresh() async {
    await ref.read(activityProvider.notifier).refresh();
    _refreshController.refreshCompleted();
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activity Monitoring'),
        content: const Text(
          'This page shows:\n\n'
          '• Content detections blocked by the AI\n'
          '\n'
          'Data syncs from your child\'s device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingChildSelector(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 100,
                  height: 14,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 4),
                Container(
                  width: 60,
                  height: 12,
                  color: Colors.grey.shade300,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorChildSelector(BuildContext context, [String? errorMessage]) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Failed to load children',
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (errorMessage != null)
                  Text(
                    errorMessage,
                    style: TextStyle(
                      color: colorScheme.onErrorContainer.withOpacity(0.8),
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
