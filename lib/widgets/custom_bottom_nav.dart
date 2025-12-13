import 'package:flutter/material.dart';
import 'package:apula/screens/app/live/livefootage_page.dart';
import 'package:apula/screens/app/notification/notification_page.dart';
import 'package:apula/screens/app/settings/settings_page.dart';
import 'package:apula/screens/demo/fire_demo_page.dart';

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
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: selectedIndex,
      onTap: (index) {
        if (index == 1) {
          // 🎥 LIVE FOOTAGE
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LiveFootagePage(devices: availableDevices),
            ),
          );
        } else if (index == 2) {
          // 🔔 NOTIFICATIONS → NotificationPage no longer needs devices
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NotificationPage(availableDevices: availableDevices),
            ),
          );
        } else if (index == 3) {
          // ⚙ SETTINGS (only keep availableDevices if SettingsPage needs it)
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SettingsPage(availableDevices: availableDevices),
            ),
          );
        } else if (index == 4) {
          // 🧪 CNN TEST
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const FireDemoPage(),
            ),
          );
        } else {
          // 🏠 HOME
          onItemTapped(index);
        }
      },
      selectedItemColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.white
          : const Color(0xFFA30000),
      unselectedItemColor: Colors.grey,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
        BottomNavigationBarItem(icon: Icon(Icons.videocam), label: "Live"),
        BottomNavigationBarItem(icon: Icon(Icons.notifications), label: "Alerts"),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
        BottomNavigationBarItem(icon: Icon(Icons.science), label: "CNN Test"),
      ],
    );
  }
}
