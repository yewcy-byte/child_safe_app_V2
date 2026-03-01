import 'package:flutter/material.dart';
import '../../../models/detection_model.dart';

class DetectionTypeBadge extends StatelessWidget {
  final DetectionType detectionType;
  final double size;

  const DetectionTypeBadge({
    super.key,
    required this.detectionType,
    this.size = 40.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (icon, color, label) = _getBadgeProperties(colorScheme);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(
        icon,
        color: color,
        size: size * 0.5,
      ),
    );
  }

  (IconData, Color, String) _getBadgeProperties(ColorScheme colorScheme) {
    switch (detectionType) {
      case DetectionType.nsfw:
        return (
          Icons.block,
          colorScheme.error,
          'NSFW',
        );
      case DetectionType.gun:
        return (
          Icons.gavel,
          colorScheme.secondary,
          'GUN',
        );
      case DetectionType.gore:
        return (
          Icons.warning_amber_rounded,
          colorScheme.tertiary,
          'GORE',
        );
      case DetectionType.grooming:
        return (
          Icons.record_voice_over,
          colorScheme.error,
          'GROOMING',
        );
    }
  }
}
