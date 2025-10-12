import 'package:flutter/material.dart';

class DevicesInfoScreen extends StatelessWidget {
  const DevicesInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Get scanned QR code from arguments
    final String? scannedCode =
        ModalRoute.of(context)?.settings.arguments as String?;

    // Example list of devices
    final List<String> devices = ["CCTV 1", "CCTV 2", "CCTV 3"];

    // Add scanned code dynamically (for debugging/demo)
    if (scannedCode != null && !devices.contains(scannedCode)) {
      devices.add(scannedCode);
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔙 Back Button (copied style from SetPasswordScreen)
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 10),
              child: InkWell(
                onTap: () => Navigator.pushReplacementNamed(context, '/home'),
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

            // 📌 Title (same style as SetPasswordScreen)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                "Devices",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // 📋 Devices List
            Expanded(
              child: ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.videocam,
                        color: Color(0xFFA30000),
                      ),
                      title: Text(devices[index]),
                    ),
                  );
                },
              ),
            ),

            // 🔴 Add Device Button
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    // Future: open QR scanner again
                    Navigator.pushNamed(context, '/add_device');
                  },
                  child: const Text(
                    "Add device",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
