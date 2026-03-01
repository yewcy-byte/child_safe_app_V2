import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../services/accessibility_service.dart';

/// Monitoring screen - follows AGENTS.MD UI rules
/// - No hard-coded colors
/// - No hard-coded text styles
/// - Uses theme only
class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  final _accessibilityService = AccessibilityService();
  bool _isEnabled = false;
  bool _isLoading = true;
  String? _currentApp;

  @override
  void initState() {
    super.initState();
    _checkAccessibilityStatus();
  }

  Future<void> _checkAccessibilityStatus() async {
    setState(() => _isLoading = true);
    final enabled = await _accessibilityService.isAccessibilityEnabled();
    setState(() {
      _isEnabled = enabled;
      _isLoading = false;
    });
    
    if (enabled) {
      await _accessibilityService.startMonitoring();
      _pollCurrentApp();
    }
  }

  void _pollCurrentApp() {
    Future.delayed(const Duration(seconds: 1), () async {
      if (!mounted || !_isEnabled) return;
      final app = await _accessibilityService.getDetectedApp();
      if (mounted) {
        setState(() => _currentApp = app);
        _pollCurrentApp();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use theme - NO hard-coded colors/styles
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Screen Monitoring',
          style: textTheme.titleLarge,
        ),
        backgroundColor: colorScheme.primaryContainer,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: colorScheme.primary,
              ),
            )
          : _buildContent(context, colorScheme, textTheme),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusCard(colorScheme, textTheme),
          SizedBox(height: AppSpacing.lg),
          if (_isEnabled) _buildCurrentAppCard(colorScheme, textTheme),
          SizedBox(height: AppSpacing.lg),
          if (!_isEnabled) _buildEnableButton(context, colorScheme, textTheme),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      color: _isEnabled
          ? colorScheme.primaryContainer
          : colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Icon(
              _isEnabled ? Icons.check_circle : Icons.error,
              color: _isEnabled
                  ? colorScheme.primary
                  : colorScheme.error,
              size: 48,
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              _isEnabled ? 'Monitoring Active' : 'Monitoring Disabled',
              style: textTheme.titleMedium?.copyWith(
                color: _isEnabled
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentAppCard(ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current App',
              style: textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              _currentApp ?? 'No app detected',
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnableButton(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return FilledButton.icon(
      onPressed: () async {
        final success = await _accessibilityService.openAccessibilitySettings();
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Please enable Child Safe App in accessibility settings',
                style: textTheme.bodyMedium,
              ),
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          );
        }
      },
      icon: Icon(Icons.settings, color: colorScheme.onPrimary),
      label: Text(
        'Enable Accessibility Service',
        style: textTheme.labelLarge?.copyWith(
          color: colorScheme.onPrimary,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        padding: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  }

  @override
  void dispose() {
    _accessibilityService.stopMonitoring();
    super.dispose();
  }
}