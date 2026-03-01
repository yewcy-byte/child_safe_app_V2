import 'package:flutter/material.dart';

class AppColors {
  static Color primary(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  static Color onPrimary(BuildContext context) {
    return Theme.of(context).colorScheme.onPrimary;
  }

  static Color surface(BuildContext context) {
    return Theme.of(context).colorScheme.surface;
  }

  static Color onSurface(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  static Color error(BuildContext context) {
    return Theme.of(context).colorScheme.error;
  }

  static Color onError(BuildContext context) {
    return Theme.of(context).colorScheme.onError;
  }

  static Color outline(BuildContext context) {
    return Theme.of(context).colorScheme.outline;
  }

  static Color surfaceContainerHighest(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainerHighest;
  }

  static Color onSurfaceVariant(BuildContext context) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  static Color success(BuildContext context) {
    return Theme.of(context).colorScheme.tertiary;
  }

  static Color surfaceContainer(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainer;
  }

  static Color surfaceContainerHigh(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainerHigh;
  }
}
