import 'package:flutter/material.dart';
import '../../../../services/child_profile_service.dart';
import '../../../shared/shared.dart';

class FilterConfigSheet extends StatefulWidget {
  final String parentId;
  final String childId;
  final VoidCallback onSettingsUpdated;

  const FilterConfigSheet({
    super.key,
    required this.parentId,
    required this.childId,
    required this.onSettingsUpdated,
  });

  @override
  State<FilterConfigSheet> createState() => _FilterConfigSheetState();
}

class _FilterConfigSheetState extends State<FilterConfigSheet> {
  final ChildProfileService _profileService = ChildProfileService();
  bool _pornographyFilter = true;
  bool _violenceFilter = true;
  int _scanInterval = 3;
  bool _isLoading = true;
  bool _isSaving = false;

  final List<int> _scanIntervals = [1, 3, 10];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _profileService.getFilterSettings(
        widget.parentId,
        widget.childId,
      );

      if (settings != null && mounted) {
        setState(() {
          _pornographyFilter = settings['pornFilterEnabled'] ?? true;
          _violenceFilter = settings['violenceFilterEnabled'] ?? true;
          _scanInterval = settings['scanIntervalSeconds'] ?? 3;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      await _profileService.updateFilterSettings(
        parentId: widget.parentId,
        childId: widget.childId,
        pornFilterEnabled: _pornographyFilter,
        violenceFilterEnabled: _violenceFilter,
        scanIntervalSeconds: _scanInterval,
      );

      widget.onSettingsUpdated();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('Failed to save settings: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error(context),
      ),
    );
  }

  String _getIntervalLabel(int seconds) {
    return 'Every $seconds second${seconds == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: _isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              : SingleChildScrollView(
                  padding: AppSpacing.paddingLg,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Configure Filters',
                            style: AppTextStyles.titleLarge(context),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: AppSpacing.xl),
                      
                      // Pornography Filter
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pornography Filter',
                                  style: AppTextStyles.titleMedium(context).copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'Block adult and inappropriate content',
                                  style: AppTextStyles.bodySmall(context).copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _pornographyFilter,
                            onChanged: (value) => setState(() => _pornographyFilter = value),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: AppSpacing.lg),
                      
                      // Violence Filter
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Violence Filter',
                                  style: AppTextStyles.titleMedium(context).copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'Block violent and harmful content',
                                  style: AppTextStyles.bodySmall(context).copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _violenceFilter,
                            onChanged: (value) => setState(() => _violenceFilter = value),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: AppSpacing.lg),
                      
                      // Scan Interval
                      Text(
                        'Scan Interval',
                        style: AppTextStyles.titleMedium(context).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'How often to scan the screen for inappropriate content',
                        style: AppTextStyles.bodySmall(context).copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: colorScheme.outline),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _scanInterval,
                            isExpanded: true,
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _scanInterval = value);
                              }
                            },
                            items: _scanIntervals.map((interval) {
                              return DropdownMenuItem(
                                value: interval,
                                child: Text(_getIntervalLabel(interval)),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: AppSpacing.xl),
                      
                      // Save Button
                      FilledButton(
                        onPressed: _isSaving ? null : _saveSettings,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save Changes'),
                      ),
                      
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
