import 'package:flutter/material.dart';
import '../shared/shared.dart';
import 'components/components.dart';
import 'home/home_page.dart';
import 'activity/activity_page.dart';
import 'control/control_page.dart';
import 'location/location_page.dart';
import 'parent_dashboard_scope.dart';

class ParentDashboard extends StatefulWidget {
  const ParentDashboard({super.key});

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  int _currentIndex = 0;
  String? _activityChildId;



  void _handleInfoPressed() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'About Guarden',
          style: AppTextStyles.titleLarge(context),
        ),
        content: Text(
          'Guarden is an AI-powered parental control app that helps keep your children safe online.',
          style: AppTextStyles.bodyMedium(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: AppTextStyles.labelLarge(context)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ParentDashboardScope(
      openActivity: (childId) {
        setState(() {
          _activityChildId = childId;
        });
      },
      closeActivity: () {
        setState(() {
          _activityChildId = null;
        });
      },
      child: Scaffold(
        appBar: PersistentHeader(onInfoPressed: _handleInfoPressed),
        body: Stack(
          children: [
            _activityChildId != null
                ? ActivityPage(embedded: true, childId: _activityChildId)
                : IndexedStack(
                    index: _currentIndex,
                    children: [
                      const HomePage(),
                      const ControlPage(),
                      const LocationPage(),
                    ],
                  ),
          ],
        ),
        bottomNavigationBar: ParentBottomNavBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _activityChildId = null;
              _currentIndex = index;
            });
          },
        ),
      ),
    );
  }
}
