import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../../main.dart';

// MJPEG viewer
import '../app/live/mjpeg/mobile_mjpeg_view.dart'
    if (dart.library.html) '../app/live/mjpeg/web_mjpeg_view.dart';

class FireDemoPage extends StatefulWidget {
  const FireDemoPage({super.key});

  @override
  State<FireDemoPage> createState() => _FireDemoPageState();
}

class _FireDemoPageState extends State<FireDemoPage> {
  final DatabaseReference _rtdb =
      FirebaseDatabase.instanceFor(app: yoloFirebaseApp).ref();

  bool _running = false;
  String _status = "No simulation yet.";

  /// 🔥 Default MJPEG stream (ALWAYS 1 video)
  final String flaskStream = "http://192.168.1.4:5000/video_feed";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fire Demo"),
        backgroundColor: const Color(0xFFA30000),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // =============================================================
            // 🔥 MJPEG VIDEO (stable, works without switching)
            // =============================================================
            SizedBox(
              height: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MJpegView(
                  key: ValueKey("stream_default"),
                  url: flaskStream,
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              "Simulate Sensor Readings (YOLO stays real from Python video)",
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 20),

            // LOW
            ElevatedButton(
              onPressed: _running ? null : () => _simulate("low"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text("Simulate LOW (No Fire)"),
            ),
            const SizedBox(height: 10),

            // MEDIUM
            ElevatedButton(
              onPressed: _running ? null : () => _simulate("medium"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text("Simulate MEDIUM (Smoke)"),
            ),
            const SizedBox(height: 10),

            // HIGH
            ElevatedButton(
              onPressed: _running ? null : () => _simulate("high"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("Simulate HIGH (Fire + Flame)"),
            ),

            const SizedBox(height: 20),

            // STATUS BOX
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _status,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // SENSOR SIMULATION
  // ===========================================================
  String _now() => DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

  Future<void> _simulate(String level) async {
    Map<String, dynamic> entry;

    if (level == "low") {
      entry = {
        "detected": "no",
        "flame": 0,
        "humidity": 60.0,
        "smoke": 0.0,
        "temperature": 30.0,
        "thermal_max": 25.0,
        "thermal_avg": 22.0,
        "timestamp": _now(),
      };
    } else if (level == "medium") {
      entry = {
        "detected": "yes",
        "flame": 1,
        "humidity": 80.0,
        "smoke": 1200.0,
        "temperature": 42.0,
        "thermal_max": 60.0,
        "thermal_avg": 50.0,
        "timestamp": _now(),
      };
    } else {
      entry = {
        "detected": "yes",
        "flame": 1,
        "humidity": 20.0,
        "smoke": 300.0,
        "temperature": 50.0,
        "thermal_max": 65.0,
        "thermal_avg": 50.0,
        "timestamp": _now(),
      };
    }

    await _sendSensor(entry, level.toUpperCase());
  }

  Future<void> _sendSensor(Map<String, dynamic> entry, String label) async {
    final pretty = const JsonEncoder.withIndent('  ').convert(entry);

    setState(() {
      _running = true;
      _status = "Sending $label sensor data...\n$pretty";
    });

    try {
      await _rtdb.child("sensor_data").push().set(entry);
      await _rtdb.child("sensor_data/latest").set(entry);

      setState(() {
        _status = "$label SENSOR SENT:\n$pretty";
      });
    } catch (e) {
      setState(() => _status = "❌ FAILED: $e");
    }

    setState(() => _running = false);
  }
}
