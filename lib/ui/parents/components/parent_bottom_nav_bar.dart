import 'package:flutter/material.dart';

class ParentBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const ParentBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      type: BottomNavigationBarType.fixed,
      onTap: onTap,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_remote_outlined),
          activeIcon: Icon(Icons.settings_remote),
          label: 'Control',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.location_on_outlined),
          activeIcon: Icon(Icons.location_on),
          label: 'Location',
        ),
      ],
    );
  }
}
