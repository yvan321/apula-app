import 'dart:async';
import 'package:flutter/material.dart';
import 'package:apula/screens/app/live/livefootage_page.dart';
import 'package:apula/widgets/custom_bottom_nav.dart'; 
import 'package:apula/screens/demo/fire_demo_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  String _time = "", _date = "";
  bool _isDay = true;
  int _temperature = 28;
  Timer? _timer;
  final List<String> _availableDevices = ["CCTV1", "CCTV2"];
  final List<String> _titles = [
    "APULA",
    "Live Footage",
    "Notifications",
    "Settings",
  ];

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => _updateTime(),
    );
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _time =
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      _date =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      _isDay = now.hour >= 6 && now.hour < 18;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        title: _selectedIndex == 0
            ? Row(children: [Image.asset("assets/logo.png", height: 40)])
            : Row(
                children: [
                  Image.asset("assets/apula_home_icon.png", height: 35),
                  const SizedBox(width: 8),
                  Text(
                    _titles[_selectedIndex],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeContent(context),
          const Center(child: Text("Live Footage Page")),
          const Center(child: Text("Notifications Page 🔔")),
          const Center(child: Text("Settings Page ⚙️")),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
        availableDevices: _availableDevices,
      ), // ✅ Using reusable nav
    );
  }

  Widget _buildHomeContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Prevention Starts with Detection",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // 🔥 Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.red, Colors.orange],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: const [
                Icon(
                  Icons.local_fire_department,
                  color: Colors.white,
                  size: 40,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "System is Active\nNo Fire Detected",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 🕒 Date/Time & 🌡️ Temperature Row
          Row(
            children: [
              Expanded(child: _buildTimeDateCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildTemperatureCard()),
            ],
          ),
          const SizedBox(height: 20),

          // 📺 Live Footage Section
          const Text(
            "Live Footage",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    LiveFootagePage(devices: _availableDevices),
              ),
            ),
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: _availableDevices.isNotEmpty
                    ? Colors.black
                    : Colors.grey.shade900,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _availableDevices.isNotEmpty
                    ? Image.asset("assets/examples/fire_example.jpg", fit: BoxFit.cover)
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.videocam_off,
                              color: Colors.grey,
                              size: 50,
                            ),
                            SizedBox(height: 8),
                            Text(
                              "No Devices Available",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 📊 Activity Section
          const Text(
            "Recent Activity",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _activityItem("Camera 1 - No fire detected", "2 mins ago"),
          _activityItem("Temperature sensor normal", "10 mins ago"),
          _activityItem("System check completed", "1 hr ago"),
        ],
      ),
    );
  }

  Widget _buildTimeDateCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isDay
              ? [Colors.blue.shade400, Colors.blue.shade700]
              : [Colors.indigo.shade400, Colors.indigo.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _isDay
                ? Colors.blue.withOpacity(0.4)
                : Colors.indigo.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _isDay ? Icons.wb_sunny : Icons.nightlight_round,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            _time,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _date,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildTemperatureCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _temperature >= 30
              ? [Colors.red.shade400, Colors.red.shade700]
              : [Colors.blue.shade400, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _temperature >= 30
                ? Colors.red.withOpacity(0.4)
                : Colors.blue.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.thermostat, color: Colors.white, size: 28),
          const SizedBox(height: 8),
          Text(
            "$_temperature°C",
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Room Temp",
            style: TextStyle(fontSize: 14, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _activityItem(String title, String time) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: Colors.green),
        title: Text(title),
        subtitle: Text(time),
      ),
    );
  }
}
