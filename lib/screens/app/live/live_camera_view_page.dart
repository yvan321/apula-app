// ignore_for_file: avoid_unnecessary_containers

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

import 'dart:html' as html; // Web MJPEG
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

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

  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(seconds: 1), () {
      setState(() => loading = false);
    });

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
    } catch (e) {}
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

  @override
  void dispose() {
    _statusTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // ⭐ EVERYTHING WHITE
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

                        // ⭐ CCTV / THERMAL BUTTONS
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
                                padding:
                                    EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                child: Text("CCTV",
                                    style: TextStyle(color: Colors.black)),
                              ),
                              Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                child: Text("THERMAL",
                                    style: TextStyle(color: Colors.black)),
                              ),
                            ],
                          ),

                        if (!isFullscreen) const SizedBox(height: 20),

                        // ⭐ CAMERA VIEW AREA
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white, // ⭐ CAMERA FRAME = WHITE
                              borderRadius: isFullscreen
                                  ? BorderRadius.zero
                                  : BorderRadius.circular(20),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              children: [
                                _selectedView == "CCTV"
                                    ? (kIsWeb
                                        ? MjpegView(url: "$flaskBaseUrl/video_feed")
                                        : Image.network(
                                            "$flaskBaseUrl/video_feed",
                                            fit: BoxFit.cover,
                                          ))
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

                        if (!isFullscreen) const SizedBox(height: 20),

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

/// ⭐ WEB MJPEG VIEWER
class MjpegView extends StatelessWidget {
  final String url;
  const MjpegView({required this.url, super.key});

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'img',
      onElementCreated: (element) {
        final img = element as html.ImageElement;
        img.src = url;
        img.style.width = '100%';
        img.style.height = '100%';
        img.style.objectFit = 'cover';
      },
    );
  }
}
