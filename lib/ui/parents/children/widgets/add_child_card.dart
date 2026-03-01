import 'package:flutter/material.dart';
import '../../../shared/shared.dart';

/// Card with dotted border for adding a new child
/// Matches the same square size as ChildCard
class AddChildCard extends StatelessWidget {
  final VoidCallback onTap;

  const AddChildCard({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: DottedBorderPainter(
            color: colorScheme.outline,
            strokeWidth: 2,
            gap: 4,
            borderRadius: 16,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Plus icon in circle
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Icon(
                    Icons.add,
                    size: 32,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Add Child',
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for dotted border
class DottedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double borderRadius;

  DottedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.gap,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(borderRadius),
    );

    // Create dotted path
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final start = distance;
        final end = distance + strokeWidth * 2;
        
        if (end <= metric.length) {
          final segment = metric.extractPath(start, end);
          canvas.drawPath(segment, paint);
        }
        
        distance += strokeWidth * 2 + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
