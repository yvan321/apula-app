import 'package:flutter/material.dart';
import 'package:apula/widgets/custom_bottom_nav.dart';
import 'package:lottie/lottie.dart';

class LiveFootagePage extends StatefulWidget {
  final List<String> devices;

  const LiveFootagePage({super.key, required this.devices});

  @override
  State<LiveFootagePage> createState() => _LiveFootagePageState();
}

class _LiveFootagePageState extends State<LiveFootagePage> {
  int _selectedIndex = 1; // 📍 'Live' tab is selected

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);

    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
        // Stay on Live
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/notifications');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/settings');
        break;
    }
  }

  // 🔥 Loading dialog before opening camera view
  void _showLoadingDialog(String deviceName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 200,
              width: 400,
              child: Lottie.asset('assets/fireloading.json', repeat: true),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                "Opening $deviceName...",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFA30000),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Simulate connecting, then navigate
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context); // Close dialog
        Navigator.pushNamed(
          context,
          '/live_camera_view',
          arguments: {
            "deviceName": deviceName,
            "cameraId": "cam_01", // or dynamic later
          },
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔙 Custom Back Button
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 10),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: Icon(
                    Icons.chevron_left,
                    size: 30,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),

            // 📌 Main Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✨ Title
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Text(
                        "Live Footage",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // 📹 Device List / No Devices
                    Expanded(
                      child: widget.devices.isEmpty
                          ? _buildNoDevices(context)
                          : _buildDeviceList(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // ➕ Floating “Add Device” button
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/add_device');
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),

      // 🔽 Bottom Navigation Bar
      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
        availableDevices: widget.devices,
      ),
    );
  }

  /// Widget if there are no devices
  Widget _buildNoDevices(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.videocam_off, size: 80, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            "No Devices Available",
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  /// Widget if devices exist
  Widget _buildDeviceList(BuildContext context) {
    return ListView.builder(
      itemCount: widget.devices.length,
      itemBuilder: (context, index) {
        final deviceName = widget.devices[index];
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 6,
          margin: const EdgeInsets.only(bottom: 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showLoadingDialog(deviceName),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: Container(
                    height: 180,
                    color: Colors.black,
                    child: const Center(
                      child: Icon(
                        Icons.videocam,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    deviceName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
