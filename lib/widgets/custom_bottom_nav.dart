import 'package:flutter/material.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;
  final List<String> availableDevices;

  const CustomBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
    required this.availableDevices,
  });

  @override
  Widget build(BuildContext context) {
    const routeByIndex = <int, String>{
      0: '/home',
      1: '/live_footage',
      2: '/predictions',
      3: '/notifications',
      4: '/settings',
    };

    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: selectedIndex > 4 ? 0 : selectedIndex,
      onTap: (index) {
        final targetRoute = routeByIndex[index];
        final currentRoute = ModalRoute.of(context)?.settings.name;

        if (targetRoute == null || currentRoute == targetRoute) {
          onItemTapped(index);
          return;
        }

        Navigator.pushReplacementNamed(context, targetRoute);
      },
      selectedItemColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.white
          : Theme.of(context).colorScheme.primary,
      unselectedItemColor: Colors.grey,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
        BottomNavigationBarItem(icon: Icon(Icons.videocam), label: "Live"),
        BottomNavigationBarItem(icon: Icon(Icons.query_stats), label: "Predict"),
        BottomNavigationBarItem(icon: Icon(Icons.notifications), label: "Alerts"),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
      ],
    );
  }
}