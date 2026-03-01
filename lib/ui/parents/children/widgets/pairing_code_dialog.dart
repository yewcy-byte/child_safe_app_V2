import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dialog that displays a pairing code for child device linking
class PairingCodeDialog extends StatelessWidget {
  final String code;

  const PairingCodeDialog({
    super.key,
    required this.code,
  });

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pairing code copied to clipboard',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onInverseSurface,
              ),
        ),
        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return AlertDialog(
      title: Text(
        'Pairing Code Generated',
        style: textTheme.titleLarge,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Share this code with your child to pair their device:',
            style: textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: textTheme.bodyLarge?.height ?? 16),
          Container(
            padding: EdgeInsets.all(textTheme.bodyLarge?.height ?? 16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outline,
                width: 2,
              ),
            ),
            child: SelectableText(
              code,
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: textTheme.bodyMedium?.height ?? 12),
          Text(
            'This code will expire in 15 minutes',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _copyToClipboard(context),
          child: Text(
            'Copy Code',
            style: textTheme.labelLarge,
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Done',
            style: textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}
