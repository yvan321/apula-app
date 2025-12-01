import 'package:flutter/material.dart';
import 'app/home/home_page.dart';
import 'camera_page.dart';
import 'package:apula/screens/demo/fire_demo_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // 5 titles (matches bottom nav)
  final List<String> _titles = [
    "Home",
    "Camera",
    "Activity",
    "Settings",
    "CNN Test",
  ];

  // 5 pages (same order)
  final List<Widget> _pages = const [
    HomePage(),
    CameraPage(),
    Center(child: Text("Activity Page")),    // placeholder
    Center(child: Text("Settings Page")),    // placeholder
    FireDemoPage(),                          // CNN Test Page
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        backgroundColor: const Color(0xFFA30000),
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: Colors.black12, width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              spreadRadius: 2,
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedItemColor: const Color(0xFFA30000),
          unselectedItemColor: Colors.grey,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
            BottomNavigationBarItem(icon: Icon(Icons.videocam), label: "Camera"),
            BottomNavigationBarItem(icon: Icon(Icons.notifications), label: "Activity"),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
            BottomNavigationBarItem(icon: Icon(Icons.science), label: "CNN Test"),
          ],
        ),
      ),
    );
  }
}
