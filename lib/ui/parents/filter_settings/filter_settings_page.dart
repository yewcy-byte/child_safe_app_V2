import 'package:flutter/material.dart';
import '../../../models/filter_settings_model.dart';
import '../../../services/filter_settings_service.dart';
import '../../shared/shared.dart';

class FilterSettingsPage extends StatefulWidget {
  final String parentId;
  final String childId;
  final String childName;

  const FilterSettingsPage({
    super.key,
    required this.parentId,
    required this.childId,
    required this.childName,
  });

  @override
  State<FilterSettingsPage> createState() => _FilterSettingsPageState();
}

class _FilterSettingsPageState extends State<FilterSettingsPage> {
  final FilterSettingsService _filterSettingsService = FilterSettingsService();
  static const int _minScanIntervalSeconds = 1;
  static const int _maxScanIntervalSeconds = 15;
  late FilterSettings _settings;
  FixedExtentScrollController? _scanFrequencyController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFilterSettings();
  }

  @override
  void dispose() {
    _scanFrequencyController?.dispose();
    super.dispose();
  }

  Future<void> _loadFilterSettings() async {
    try {
      final settings = await _filterSettingsService.getFilterSettings(widget.parentId, widget.childId);
      final resolvedSettings = settings ??
          FilterSettings(
            childUID: widget.childId,
            pornFilterEnabled: true,
            violenceFilterEnabled: true,
            scanIntervalSeconds: 3,
            lastUpdated: DateTime.now(),
          );
      final scanIntervalSeconds = resolvedSettings.scanIntervalSeconds
          .clamp(_minScanIntervalSeconds, _maxScanIntervalSeconds)
          .toInt();

      if (mounted) {
        setState(() {
          _settings = resolvedSettings.copyWith(
            scanIntervalSeconds: scanIntervalSeconds,
          );
          _scanFrequencyController?.dispose();
          _scanFrequencyController = FixedExtentScrollController(
            initialItem: scanIntervalSeconds - _minScanIntervalSeconds,
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading settings: $e'),
            backgroundColor: AppColors.error(context),
          ),
        );
      }
    }
  }

  Future<void> _saveFilterSettings() async {
    try {
      await _filterSettingsService.saveFilterSettings(widget.parentId, widget.childId, _settings);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: AppColors.error(context),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Filter Settings'),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Filter Settings'),
        centerTitle: true,
      ),
      body: ListView(
        padding: AppSpacing.paddingMd,
        children: [
          // Child Information
          Card(
            child: Padding(
              padding: AppSpacing.paddingMd,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configuring filters for:',
                    style: AppTextStyles.bodyMedium(context).copyWith(
                      color: AppColors.onSurfaceVariant(context),
                    ),
                  ),
                  AppSpacing.gapSm,
                  Text(
                    widget.childName,
                    style: AppTextStyles.titleLarge(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AppSpacing.gapLg,

          // Pornography Filter
          _buildFilterSection(
            label: 'Pornography Filter',
            value: _settings.pornFilterEnabled,
            onChanged: (enabled) {
              setState(() {
                _settings = _settings.copyWith(
                  pornFilterEnabled: enabled,
                );
              });
              _saveFilterSettings();
            },
          ),
          AppSpacing.gapMd,

          // Violence Filter
          _buildFilterSection(
            label: 'Violence Filter',
            value: _settings.violenceFilterEnabled,
            onChanged: (enabled) {
              setState(() {
                _settings = _settings.copyWith(
                  violenceFilterEnabled: enabled,
                );
              });
              _saveFilterSettings();
            },
          ),
          AppSpacing.gapLg,

          // Scan Frequency Section
          _buildSectionTitle('Scan Frequency'),
          AppSpacing.gapSm,
          _buildScanFrequencySelector(),
          AppSpacing.gapMd,
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTextStyles.titleMedium(context).copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildFilterSection({
    required String label,
    required bool value,
    required Function(bool) onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.titleMedium(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => onChanged(!value),
              style: ElevatedButton.styleFrom(
                backgroundColor: value ? colorScheme.primary : AppColors.surfaceContainerHigh(context),
                foregroundColor: value ? colorScheme.onPrimary : AppColors.onSurfaceVariant(context),
              ),
              child: Text(
                value ? 'Active' : 'Activate',
                style: AppTextStyles.labelMedium(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanFrequencySelector() {
    final colorScheme = Theme.of(context).colorScheme;
    final frequencies = List<int>.generate(
      _maxScanIntervalSeconds - _minScanIntervalSeconds + 1,
      (index) => index + _minScanIntervalSeconds,
    );

    return Card(
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Frequency',
              style: AppTextStyles.labelMedium(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            AppSpacing.gapMd,
            Container(
              height: AppSpacing.xxl * 3,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.surfaceContainerHighest(context),
                ),
              ),
              child: ListWheelScrollView.useDelegate(
                controller: _scanFrequencyController,
                itemExtent: AppSpacing.xxl,
                diameterRatio: 1.5,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (index) {
                  final seconds = frequencies[index];
                  if (seconds == _settings.scanIntervalSeconds) {
                    return;
                  }

                  setState(() {
                    _settings = _settings.copyWith(
                      scanIntervalSeconds: seconds,
                    );
                  });
                  _saveFilterSettings();
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: frequencies.length,
                  builder: (context, index) {
                    if (index == null) {
                      return null;
                    }

                    final seconds = frequencies[index];
                    final isSelected = seconds == _settings.scanIntervalSeconds;

                    return Center(
                      child: Text(
                        '$seconds ${seconds == 1 ? 'second' : 'seconds'}',
                        style: AppTextStyles.bodyLarge(context).copyWith(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : AppColors.onSurfaceVariant(context),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            AppSpacing.gapSm,
            Text(
              'Current: ${_settings.scanIntervalSeconds} ${_settings.scanIntervalSeconds == 1 ? 'second' : 'seconds'}',
              style: AppTextStyles.bodyMedium(context).copyWith(
                color: AppColors.onSurfaceVariant(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
