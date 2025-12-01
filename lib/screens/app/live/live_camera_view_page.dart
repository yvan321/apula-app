// ignore_for_file: avoid_unnecessary_containers

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_database/firebase_database.dart';

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

  // Toggle to true during dev/testing (skips cooldown)
  final bool _testingMode = true;
  static const Duration _cooldown = Duration(seconds: 10);

  bool _canSendAlert() {
    if (_testingMode) return true;
    if (_lastAlertTime == null) return true;
    return DateTime.now().difference(_lastAlertTime!) > _cooldown;
  }

  // --------------------
  // Helpers
  // --------------------
  /// Try to fetch snapshot from RTDB with a short timeout.
  /// Returns empty string if not available — caller will substitute placeholder.
  Future<String> _getLatestSnapshot() async {
    try {
      final ref = FirebaseDatabase.instance.ref("cam_detections/latest");

      DataSnapshot snap;

      try {
        snap = await ref.get().timeout(const Duration(seconds: 2));
      } catch (e) {
        // Timeout OR other read error → treat as no snapshot
        debugPrint("RTDB timeout or error: $e");
        return "";
      }

      if (!snap.exists) return "";

      final value = snap.value;

      if (value is Map) {
        final data = Map<String, dynamic>.from(value);
        return (data["image_url"] ?? "") as String;
      }

      return "";
    } catch (e, st) {
      debugPrint("RTDB snapshot error: $e\n$st");
      return "";
    }
  }


  Future<Map<String, dynamic>?> _getUserProfile() async {
    try {
      const email = "alexanderthegreat09071107@gmail.com";
      final snap = await FirebaseFirestore.instance
          .collection("users")
          .where("email", isEqualTo: email)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.data();
    } catch (e) {
      return null;
    }
  }

  // --------------------
  // Centralized CNN handler
  // --------------------
  Future<void> _handleCnnAlert(double alert, double severity) async {
    if (!_canSendAlert()) {
      debugPrint("⛔ Cooldown active - skipping CNN alert");
      return;
    }
    _lastAlertTime = DateTime.now();

    // fetch snapshot with timeout / fallback
    String snapshotUrl = "";
    try {
      snapshotUrl = await _getLatestSnapshot();
    } catch (_) {
      snapshotUrl = "";
    }
    if (snapshotUrl.isEmpty) {
      snapshotUrl = "https://via.placeholder.com/400x300?text=No+Snapshot";
    }

    final user = await _getUserProfile();

    // HIGH severity -> create user_alert + immediately send dispatcher alert, then show modal (OK only)
    if (severity >= 0.6 || alert >= 0.6) {
      debugPrint("CNN: HIGH severity detected");
      // write user_alert
      await AlertService.sendUserAlert(
        deviceName: widget.deviceName,
        snapshotUrl: snapshotUrl,
        alert: alert,
        severity: severity,
      );

      // send dispatcher immediately
      try {
        await AlertService.sendDispatcherAlert(
          deviceName: widget.deviceName,
          description: "Fire detected in ${widget.deviceName}.",
          user: user ?? {},
          snapshotUrl: snapshotUrl,
        );
        debugPrint("Dispatcher alert (HIGH) sent automatically");
      } catch (e, st) {
        debugPrint("Error sending dispatcher (HIGH): $e\n$st");
      }

      // show modal (OK only)
      await _showFireAlertModalHigh(snapshotUrl);
      return;
    }

    // MEDIUM severity -> create user_alert and show modal. Dispatcher only on user CONFIRM.
    if ((severity >= 0.3 && severity < 0.6) || (alert >= 0.3 && alert < 0.6)) {
      debugPrint("CNN: MEDIUM severity detected");
      await AlertService.sendUserAlert(
        deviceName: widget.deviceName,
        snapshotUrl: snapshotUrl,
        alert: alert,
        severity: severity,
      );

      await _showFireAlertModalMedium(snapshotUrl, user);
      return;
    }

    debugPrint("CNN: LOW - no action");
  }

  // --------------------
  // Dispatcher send helper
  // --------------------
  Future<void> _confirmAndSendDispatcherAlert({
    required String snapshotUrl,
    Map<String, dynamic>? user,
  }) async {
    try {
      await AlertService.sendDispatcherAlert(
        deviceName: widget.deviceName,
        description: "Fire detected in ${widget.deviceName}.",
        user: user ?? {},
        snapshotUrl: snapshotUrl,
      );
      debugPrint("Dispatcher alert (CONFIRM) sent");
    } catch (e, st) {
      debugPrint("Error sending dispatcher alert (CONFIRM): $e\n$st");
    }
  }

  // --------------------
  // init / dispose
  // --------------------
  @override
  void initState() {
    super.initState();


    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => loading = false);
    });

    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkFireStatus();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --------------------
  // YOLO status check
  // --------------------
  Future<void> _checkFireStatus() async {
    try {
      final response = await http.get(Uri.parse("$flaskBaseUrl/detect_status"));
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
    } catch (e) {
      // ignore
    }
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
    } catch (e) {
      debugPrint("Error sending fire alert to firestore: $e");
    }
  }

  // --------------------
  // Modal flows
  // --------------------
  // HIGH: OK-only modal (dispatcher already notified)
  Future<void> _showFireAlertModalHigh(String snapshotUrl) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("🔥 HIGH SEVERITY — Dispatcher alerted"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              snapshotUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(snapshotUrl, height: 150, fit: BoxFit.cover, errorBuilder: (c, e, st) {
                        return const SizedBox(height: 150, child: Center(child: Text("Snapshot unavailable")));
                      }),
                    )
                  : const SizedBox(height: 150, child: Center(child: Text("No snapshot available"))),
              const SizedBox(height: 12),
              const Text("A severe fire has been detected. Emergency responders have been alerted."),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("OK"),
            )
          ],
        );
      },
    );
  }

  // MEDIUM: modal with FALSE ALARM and CONFIRM FIRE
  Future<void> _showFireAlertModalMedium(String snapshotUrl, Map<String, dynamic>? user) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("⚠️ Possible Fire — Please verify"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              snapshotUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(snapshotUrl, height: 150, fit: BoxFit.cover, errorBuilder: (c, e, st) {
                        return const SizedBox(height: 150, child: Center(child: Text("Snapshot unavailable")));
                      }),
                    )
                  : const SizedBox(height: 150, child: Center(child: Text("No snapshot available"))),
              const SizedBox(height: 12),
              const Text("A moderate fire-risk was detected. Confirm to notify emergency responders."),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                debugPrint("Modal: FALSE ALARM pressed (medium)");
                Navigator.pop(dialogContext);
              },
              child: const Text("FALSE ALARM", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(dialogContext);
                // send dispatcher alert now that user confirmed
                await _confirmAndSendDispatcherAlert(snapshotUrl: snapshotUrl, user: user);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("🚒 Dispatcher notified."), backgroundColor: Colors.red),
                );
              },
              child: const Text("CONFIRM FIRE"),
            ),
          ],
        );
      },
    );
  }

  // --------------------
  // Fire alarm UI (manual test button)
  // --------------------
  void _triggerFireAlert() async {
    await _audioPlayer.play(AssetSource('sounds/fire_alarm.mp3'));
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
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
              Navigator.pop(dialogContext);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // --------------------
  // Simulation helpers (buttons)
  // --------------------
  Future<void> _simulateCnnInput(double alert, double severity) async {
    debugPrint("SIMULATE called: alert=$alert severity=$severity");

    if (!_canSendAlert()) {
      _showSeverityPopup("Cooldown active — wait a few seconds.");
      debugPrint("SIMULATE: cooldown active");
      return;
    }
    _lastAlertTime = DateTime.now();

    Map<String, dynamic>? user;
    String snapshotUrl = "";

    try {
      user = await _getUserProfile();
    } catch (e, st) {
      debugPrint("SIMULATE: getUserProfile error: $e\n$st");
    }

    try {
      snapshotUrl = await _getLatestSnapshot();
    } catch (e, st) {
      debugPrint("SIMULATE: getLatestSnapshot error: $e\n$st");
    }

    if (snapshotUrl.isEmpty) {
      snapshotUrl = "https://via.placeholder.com/400x300?text=No+Snapshot";
    }

    debugPrint("SIMULATE: snapshotUrl.length=${snapshotUrl.length} user=${user == null ? 'null' : 'ok'}");

    try {
      // HIGH
      if (alert >= 0.6 || severity >= 0.6) {
        debugPrint("SIMULATE: HIGH -> create user_alert + dispatcher");
        await AlertService.sendUserAlert(
            deviceName: widget.deviceName, snapshotUrl: snapshotUrl, alert: alert, severity: severity);

        // dispatch immediately for HIGH
        await AlertService.sendDispatcherAlert(
          deviceName: widget.deviceName,
          description: "Fire detected in ${widget.deviceName}.",
          user: user ?? {},
          snapshotUrl: snapshotUrl,
        );

        debugPrint("SIMULATE: dispatched (HIGH) -> showing modal (OK only)");
        await _showFireAlertModalHigh(snapshotUrl);
        return;
      }

      // MEDIUM
      if (alert >= 0.3 || severity >= 0.3) {
        debugPrint("SIMULATE: MEDIUM -> create user_alert + show modal (need confirm)");
        await AlertService.sendUserAlert(
            deviceName: widget.deviceName, snapshotUrl: snapshotUrl, alert: alert, severity: severity);

        await _showFireAlertModalMedium(snapshotUrl, user);
        debugPrint("SIMULATE: returned from modal (MEDIUM)");
        return;
      }

      // LOW
      _showSeverityPopup("🟢 LOW severity\nNo alert dispatched.");
      debugPrint("SIMULATE: LOW -> no alert");
    } catch (e, st) {
      debugPrint("SIMULATE: unexpected error: $e\n$st");
      _showSeverityPopup("Error during simulation: ${e.toString()}");
    }
  }

  void _showSeverityPopup(String message) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("CNN Alert Simulation"),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text("OK"),
            onPressed: () => Navigator.pop(dialogContext),
          )
        ],
      ),
    );
  }

  // --------------------
  // camera widget (non-blocking)
  // --------------------
  Widget _buildCameraViewFixed() {
    final streamUrl = "$flaskBaseUrl/video_feed";
    return IgnorePointer(
      ignoring: true,
      child: MJpegView(url: streamUrl),
    );
  }

  // --------------------
  // UI build
  // --------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            if (!isFullscreen)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.chevron_left, size: 32, color: Colors.black),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isFullscreen ? 0 : 20),
                child: Column(
                  children: [
                    if (!isFullscreen)
                      const Text("Live Footage",
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    if (!isFullscreen) const SizedBox(height: 10),

                    if (!isFullscreen)
                      ToggleButtons(
                        borderRadius: BorderRadius.circular(12),
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
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            child: Text("CCTV", style: TextStyle(color: Colors.black)),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            child: Text("THERMAL", style: TextStyle(color: Colors.black)),
                          ),
                        ],
                      ),

                    if (!isFullscreen) const SizedBox(height: 20),

                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: isFullscreen ? BorderRadius.zero : BorderRadius.circular(20),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          children: [
                            _selectedView == "CCTV"
                                ? _buildCameraViewFixed()
                                : IgnorePointer(
                                    ignoring: true,
                                    child: Image.asset("assets/examples/thermal_example.png", fit: BoxFit.cover),
                                  ),

                            if (loading) const Center(child: CircularProgressIndicator()),

                            if (!isFullscreen)
                              Positioned(
                                top: 10,
                                right: 10,
                                child: IconButton(
                                  icon: const Icon(Icons.fullscreen, color: Colors.black, size: 30),
                                  onPressed: () => setState(() => isFullscreen = true),
                                ),
                              ),

                            if (isFullscreen)
                              Positioned(
                                top: 20,
                                right: 20,
                                child: IconButton(
                                  icon: const Icon(Icons.fullscreen_exit, color: Colors.black, size: 32),
                                  onPressed: () => setState(() => isFullscreen = false),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // TEST FIRE ALERT (always available)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.warning_amber_rounded),
                      label: const Text("TEST FIRE ALERT",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        debugPrint("BUTTON: TEST FIRE ALERT pressed");
                        _triggerFireAlert();
                        _sendFireAlertToFirestore();
                      },
                    ),

                    const SizedBox(height: 10),

                    // CNN TEST BUTTONS (visible when not fullscreen)
                    Visibility(
                      visible: !isFullscreen,
                      maintainState: false,
                      child: Column(
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              debugPrint("BUTTON: TEST LOW pressed");
                              _simulateCnnInput(0.1, 0.1);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                            child: const Text("TEST: Low Severity (No Alert)"),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () {
                              debugPrint("BUTTON: TEST MEDIUM pressed");
                              _simulateCnnInput(0.4, 0.4);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                            child: const Text("TEST: Medium Severity (User Only)"),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () {
                              debugPrint("BUTTON: TEST HIGH pressed");
                              _simulateCnnInput(0.8, 0.8);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text("TEST: HIGH Severity (Dispatcher + User)"),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    if (!isFullscreen)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.local_fire_department, color: Colors.red, size: 30),
                                SizedBox(width: 10),
                                Text("Fire Detection", style: TextStyle(fontSize: 18, color: Colors.black)),
                              ],
                            ),
                            Switch(value: fireDetected, activeColor: Colors.red, onChanged: (_) {}),
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
