import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DevicesInfoScreen extends StatefulWidget {
  const DevicesInfoScreen({super.key});

  @override
  State<DevicesInfoScreen> createState() => _DevicesInfoScreenState();
}

class _DevicesInfoScreenState extends State<DevicesInfoScreen> {
  List<String> devices = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email;
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final userData = query.docs.first.data();
        final List<dynamic>? cameraIds = userData['cameraIds'];
        
        if (cameraIds != null) {
          setState(() {
            devices = List<String>.from(cameraIds);
            loading = false;
          });
        } else {
          setState(() {
            loading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading devices: $e');
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _addScannedDevice(String cameraId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email;
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final docRef = query.docs.first.reference;
        
        // Add camera ID if not already in list
        if (!devices.contains(cameraId)) {
          devices.add(cameraId);
          await docRef.update({
            'cameraIds': FieldValue.arrayUnion([cameraId])
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Camera $cameraId added!'),
              backgroundColor: Colors.green,
            ),
          );
          
          setState(() {});
        }
      }
    } catch (e) {
      print('Error adding device: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to add camera'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Get scanned QR code from arguments
    final String? scannedCode =
        ModalRoute.of(context)?.settings.arguments as String?;

    // Add scanned device when navigated from QR scanner
    if (scannedCode != null && !devices.contains(scannedCode)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addScannedDevice(scannedCode);
      });
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
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : devices.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam_off,
                                  size: 80, color: Colors.grey),
                              SizedBox(height: 12),
                              Text(
                                "No Cameras Added",
                                style:
                                    TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                              SizedBox(height: 8),
                              Text(
                                "Scan a QR code to add a camera",
                                style:
                                    TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
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
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () async {
                                    // Remove device
                                    final cameraId = devices[index];
                                    try {
                                      final user =
                                          FirebaseAuth.instance.currentUser;
                                      if (user == null) return;

                                      final email = user.email;
                                      final query = await FirebaseFirestore
                                          .instance
                                          .collection('users')
                                          .where('email', isEqualTo: email)
                                          .limit(1)
                                          .get();

                                      if (query.docs.isNotEmpty) {
                                        final docRef =
                                            query.docs.first.reference;
                                        await docRef.update({
                                          'cameraIds': FieldValue.arrayRemove(
                                              [cameraId])
                                        });

                                        setState(() {
                                          devices.removeAt(index);
                                        });

                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                'Camera $cameraId removed'),
                                            backgroundColor: Colors.orange,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      print('Error removing device: $e');
                                    }
                                  },
                                ),
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
