// ignore_for_file: avoid_unnecessary_containers

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:apula/services/cnn_listener_service.dart';
import 'package:apula/services/alert_service.dart';

// CONDITIONAL MJPEG IMPORTS
import 'mjpeg/mobile_mjpeg_view.dart'
    if (dart.library.html) 'mjpeg/web_mjpeg_view.dart';

class LiveCameraViewPage extends StatefulWidget {
  final String deviceName;
  const LiveCameraViewPage({super.key, required this.deviceName});

  @override
  State<LiveCameraViewPage> createState() => _LiveCameraViewPageState();
}

class _LiveCameraViewPageState extends State<LiveCameraViewPage> {
  bool fireDetected = false;
  bool loading = true;
  bool isFullscreen = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final String flaskBaseUrl = "http://10.238.220.202:5000";

  String _selectedView = "CCTV";
  Timer? _statusTimer;

  DateTime? _lastAlertTime;

  bool _canSendAlert() {
    if (_lastAlertTime == null) return true;
    return DateTime.now().difference(_lastAlertTime!) >
        const Duration(seconds: 10);
  }


  @override
  void initState() {
    super.initState();

    // ⭐ START CNN LISTENER HERE
    CnnListenerService.startListening((alert, severity) {
      print("📡 CNN UPDATE → alert=$alert  severity=$severity");

      // Cooldown inside UI (optional but recommended)
      if (!_canSendAlert()) {
        print("⛔ Cooldown active – skipping alert");
        return;
      }
      _lastAlertTime = DateTime.now();

      // 🔥 HIGH severity → dispatcher + user
      if (alert >= 0.6 || severity >= 0.6) {
        _sendDispatcherAlert();
        _sendUserAlert();
      }
      // ⚠️ Medium severity → user only
      else if (alert >= 0.3 || severity >= 0.3) {
        _sendUserAlert();
      }
    });

    // Existing loading delay
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => loading = false);
      }
    });

    // Existing YOLO status check
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkFireStatus();
    });
  }

  Future<void> _checkFireStatus() async {
    try {
      final response =
          await http.get(Uri.parse("$flaskBaseUrl/detect_status"));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bool detected = (data["fire_detected"] == 1);

        if (detected && !fireDetected) {
          setState(() => fireDetected = true);
          _triggerFireAlert();
          _sendFireAlertToFirestore();
        } else if (!detected && fireDetected) {
          setState(() => fireDetected = false);
        }
      }
    } catch (_) {}
  }

  Future<void> _sendFireAlertToFirestore() async {
    try {
      const String email = "alexanderthegreat09071107@gmail.com";

      final snapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return;

      final user = snapshot.docs.first.data();

      await _firestore.collection('alerts').add({
        'type': '🔥 Fire Detected',
        'location': widget.deviceName,
        'description': 'Fire detected in ${widget.deviceName}.',
        'status': 'Pending',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'userName': user['name'] ?? 'Unknown',
        'userAddress': user['address'] ?? 'N/A',
        'userContact': user['contact'] ?? 'N/A',
        'userEmail': email,
        'userLatitude': user['latitude'],
        'userLongitude': user['longitude'],
      });
    } catch (e) {}
  }

  void _triggerFireAlert() async {
    await _audioPlayer.play(AssetSource('sounds/fire_alarm.mp3'));

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: Column(
          children: const [
            Icon(Icons.local_fire_department, color: Colors.red, size: 60),
            SizedBox(height: 10),
            Text("🔥 FIRE DETECTED",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: Text(
          "Fire detected in ${widget.deviceName}.",
          textAlign: TextAlign.center,
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              _audioPlayer.stop();
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _sendUserAlert() {
    print("🔔 Sending USER alert...");
    AlertService.sendUserAlert(deviceName: widget.deviceName);
  }

  void _sendDispatcherAlert() {
    print("🚨 Sending DISPATCHER alert...");
    AlertService.sendDispatcherAlert(deviceName: widget.deviceName);
  }

  void _showSeverityPopup(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("CNN Alert Simulation"),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text("OK"),
            onPressed: () => Navigator.pop(context),
          )
        ],
      ),
    );
  }


  void _simulateCnnInput(double alert, double severity) {
    if (!_canSendAlert()) {
      _showSeverityPopup("Cooldown active — wait a few seconds.");
      return;
    }

    _lastAlertTime = DateTime.now();

    if (alert >= 0.6 || severity >= 0.6) {
      AlertService.sendDispatcherAlert(deviceName: widget.deviceName);
      AlertService.sendUserAlert(deviceName: widget.deviceName);

      _showSeverityPopup(
        "🔥 HIGH severity\nDispatcher + User alerted (Firestore updated)",
      );
    } 
    else if (alert >= 0.3 || severity >= 0.3) {
      AlertService.sendUserAlert(deviceName: widget.deviceName);

      _showSeverityPopup(
        "⚠ MEDIUM severity\nUser alerted (Firestore updated)",
      );
    } 
    else {
      _showSeverityPopup(
        "🟢 LOW severity\nNo alert dispatched.",
      );
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Widget _buildCameraView() {
    final streamUrl = "$flaskBaseUrl/video_feed";

    return MJpegView(url: streamUrl); // auto selects web or mobile version
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                if (!isFullscreen)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.chevron_left,
                              size: 32, color: Colors.black),
                        ),
                      ],
                    ),
                  ),

                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(isFullscreen ? 0 : 20),
                    child: Column(
                      children: [
                        if (!isFullscreen) ...[
                          const Text(
                            "Live Footage",
                            style: TextStyle(
                                fontSize: 28,
                                color: Colors.black,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                        ],

                        if (!isFullscreen)
                          ToggleButtons(
                            borderRadius: BorderRadius.circular(12),
                            isSelected: [
                              _selectedView == "CCTV",
                              _selectedView == "THERMAL",
                            ],
                            onPressed: (index) {
                              setState(() {
                                _selectedView =
                                    index == 0 ? "CCTV" : "THERMAL";
                              });
                            },
                            children: const [
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                child: Text("CCTV",
                                    style: TextStyle(color: Colors.black)),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                child: Text("THERMAL",
                                    style: TextStyle(color: Colors.black)),
                              ),
                            ],
                          ),

                        if (!isFullscreen) const SizedBox(height: 20),

                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: isFullscreen
                                  ? BorderRadius.zero
                                  : BorderRadius.circular(20),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              children: [
                                _selectedView == "CCTV"
                                    ? _buildCameraView()
                                    : Image.asset(
                                        "assets/examples/thermal_example.png",
                                        fit: BoxFit.cover,
                                      ),

                                if (loading)
                                  const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.black,
                                    ),
                                  ),

                                if (!isFullscreen)
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: IconButton(
                                      icon: const Icon(Icons.fullscreen,
                                          color: Colors.black, size: 30),
                                      onPressed: () {
                                        setState(() => isFullscreen = true);
                                      },
                                    ),
                                  ),

                                if (isFullscreen)
                                  Positioned(
                                    top: 20,
                                    right: 20,
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.fullscreen_exit,
                                        color: Colors.black,
                                        size: 32,
                                      ),
                                      onPressed: () {
                                        setState(() => isFullscreen = false);
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        if (!isFullscreen)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.warning_amber_rounded),
                            label: const Text(
                              "TEST FIRE ALERT",
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              _triggerFireAlert();
                              _sendFireAlertToFirestore();
                            },
                          ),

                        if (!isFullscreen) ...[
                          const SizedBox(height: 10),

                          ElevatedButton(
                            onPressed: () => _simulateCnnInput(0.1, 0.1),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                            child: const Text("TEST: Low Severity (No Alert)"),
                          ),

                          const SizedBox(height: 10),

                          ElevatedButton(
                            onPressed: () => _simulateCnnInput(0.4, 0.4),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                            child: const Text("TEST: Medium Severity (User Only)"),
                          ),

                          const SizedBox(height: 10),

                          ElevatedButton(
                            onPressed: () => _simulateCnnInput(0.8, 0.8),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text("TEST: HIGH Severity (Dispatcher + User)"),
                          ),
                        ],

                        if (!isFullscreen)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                )
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.local_fire_department,
                                        color: Colors.red, size: 30),
                                    SizedBox(width: 10),
                                    Text("Fire Detection",
                                        style: TextStyle(
                                            fontSize: 18,
                                            color: Colors.black)),
                                  ],
                                ),
                                Switch(
                                  value: fireDetected,
                                  activeColor: Colors.red,
                                  onChanged: (_) {},
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
          ],
        ),
      ),
    );
  }
}
