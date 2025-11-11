import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart'; // ✅ Firestore
import 'package:flutter/foundation.dart' show kIsWeb;

// ⛔ REMOVE THESE imports completely!
// import '../../../utils/web_view_registry.dart';
// import 'dart:html' as html;

class LiveCameraViewPage extends StatefulWidget {
  final String deviceName;
  const LiveCameraViewPage({super.key, required this.deviceName});

  @override
  State<LiveCameraViewPage> createState() => _LiveCameraViewPageState();
}

class _LiveCameraViewPageState extends State<LiveCameraViewPage> {
  bool fireDetected = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final String flaskBaseUrl = "http://192.168.1.8:5000";
  String _selectedView = "CCTV";
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();



    // 🔁 Check Flask detection every 3 seconds
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkFireStatus();
    });
  }

  // 🔥 Check Flask detection API
  Future<void> _checkFireStatus() async {
    try {
      final response = await http.get(Uri.parse("$flaskBaseUrl/detect_status"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bool detected = data["fire_detected"] ?? false;

        if (detected && !fireDetected) {
          setState(() => fireDetected = true);
          _triggerFireAlert();
          _sendFireAlertToFirestore();
        } else if (!detected && fireDetected) {
          setState(() => fireDetected = false);
        }
      }
    } catch (e) {
      debugPrint("⚠️ Error checking fire status: $e");
    }
  }

  // ✅ Send simulated or real alert to Firestore
  // ✅ Send simulated or real alert to Firestore (with user info)
  Future<void> _sendFireAlertToFirestore() async {
    try {
      // 1️⃣ Get the current user info
      // Replace this with your actual logged-in user email (from FirebaseAuth)
      final String currentUserEmail = "alexanderthegreat09071107@gmail.com";

      final userSnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: currentUserEmail)
          .limit(1)
          .get();

      if (userSnapshot.docs.isEmpty) {
        debugPrint("⚠️ No user found for $currentUserEmail");
        return;
      }

      final userData = userSnapshot.docs.first.data();
      final userName = userData['name'] ?? 'Unknown';
      final userAddress = userData['address'] ?? 'N/A';
      final userContact = userData['contact'] ?? 'N/A';

      // 2️⃣ Add Fire alert with user info
      await _firestore.collection('alerts').add({
        'type': '🔥 Fire Detected',
        'location': widget.deviceName,
        'description':
            'Fire detected in ${widget.deviceName}. Immediate response needed.',
        'status': 'Pending',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'userName': userName,
        'userAddress': userAddress,
        'userContact': userContact,
        'userEmail': currentUserEmail,
      });

      debugPrint("✅ Fire alert sent to Firestore with user info!");
    } catch (e) {
      debugPrint("❌ Failed to send Firestore alert: $e");
    }
  }

  // 🔔 Fire Alert popup
  void _triggerFireAlert() async {
    await _audioPlayer.play(AssetSource('sounds/fire_alarm.mp3'));
    if (!mounted) return;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? Colors.grey[900] : theme.colorScheme.surface,
        titlePadding: const EdgeInsets.only(top: 24),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              color: theme.colorScheme.primary,
              size: 60,
            ),
            const SizedBox(height: 12),
            Text(
              "🔥 FIRE DETECTED",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(
              "A fire has been detected in ${widget.deviceName}.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/fire_preview.jpg',
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 20,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              _audioPlayer.stop();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text(
              "OK",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // 🧠 TEST BUTTON (Manual Fire Alert)
  void _simulateFire() {
    setState(() {
      fireDetected = !fireDetected;
    });
    if (fireDetected) {
      _triggerFireAlert();
      _sendFireAlertToFirestore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔙 Back Button
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 10),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withOpacity(0.1),
                  ),
                  child: Icon(
                    Icons.chevron_left,
                    size: 30,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 📺 Title
                    Text(
                      "Live Footage",
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 🔄 View Toggle
                    Center(
                      child: ToggleButtons(
                        borderRadius: BorderRadius.circular(12),
                        borderColor: colorScheme.primary,
                        selectedBorderColor: colorScheme.primary,
                        fillColor: colorScheme.primary.withOpacity(0.2),
                        color: colorScheme.primary,
                        selectedColor: colorScheme.primary,
                        isSelected: [
                          _selectedView == "CCTV",
                          _selectedView == "THERMAL",
                        ],
                        onPressed: (index) {
                          setState(() {
                            _selectedView = index == 0 ? "CCTV" : "THERMAL";
                          });
                        },
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            child: Text("CCTV"),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            child: Text("THERMAL"),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 🎥 Camera Feed (iframe or placeholder)
                    Expanded(
                      flex: 3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: _selectedView == "CCTV"
                            ? (kIsWeb
                                  ? const HtmlElementView(
                                      viewType: 'flaskVideoFeed',
                                    ) // ✅ For web
                                  : Image.network(
                                      // ✅ For phone: directly show Flask stream image
                                      "http://192.168.1.8:5000/video_feed",
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Center(
                                                child: Text(
                                                  "Unable to load live feed",
                                                  style: TextStyle(
                                                    color: Color.fromARGB(
                                                      179,
                                                      212,
                                                      151,
                                                      151,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                    ))
                            : Image.asset(
                                'assets/examples/thermal_example.png',
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 🔥 Fire Detection Card + Test Button
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[900]
                            : Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                widget.deviceName,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const Icon(
                                Icons.circle,
                                color: Colors.green,
                                size: 14,
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: const [
                                  Icon(
                                    Icons.local_fire_department,
                                    color: Colors.red,
                                    size: 28,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    "Fire Detection",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              Switch(
                                value: fireDetected,
                                activeColor: Colors.red,
                                onChanged: (_) =>
                                    _simulateFire(), // ✅ test fire
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: _simulateFire,
                            icon: const Icon(
                              Icons.warning,
                              color: Colors.white,
                            ),
                            label: const Text("Simulate Fire Alert"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


