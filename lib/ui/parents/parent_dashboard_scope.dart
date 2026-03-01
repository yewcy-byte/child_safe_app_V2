import 'package:flutter/material.dart';

class ParentDashboardScope extends InheritedWidget {
  final void Function(String childId) openActivity;
  final VoidCallback closeActivity;

  const ParentDashboardScope({
    super.key,
    required this.openActivity,
    required this.closeActivity,
    required Widget child,
  }) : super(child: child);

  static ParentDashboardScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ParentDashboardScope>();
    assert(scope != null, 'ParentDashboardScope not found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(covariant ParentDashboardScope oldWidget) {
    return false;
  }
}
