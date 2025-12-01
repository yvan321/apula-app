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

  /// 🔥 Default MJPEG stream from Python
  final String flaskStream = "http://192.168.1.4:5000/video_feed";

  /// CNN LIVE DATA HISTORY (for graphs)
  final List<double> severityLog = [];
  final List<double> alertLog = [];

  @override
  void initState() {
    super.initState();

    // Listen to CNN outputs LIVE
    final cnnRef = _rtdb.child("cnn_results/CCTV1");
    cnnRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) return;

      double sev = _toDouble(data["severity"]);
      double alert = _toDouble(data["alert"]);

      setState(() {
        severityLog.add(sev);
        alertLog.add(alert);

        if (severityLog.length > 50) severityLog.removeAt(0);
        if (alertLog.length > 50) alertLog.removeAt(0);
      });
    });
  }

  double _toDouble(v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fire Demo"),
        backgroundColor: Color(0xFFA30000),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 🔥 VIDEO STREAM
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
            _buildLiveCnnBox(),

            const SizedBox(height: 20),
            const Text(
              "Send Simulated Sensor Readings",
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 20),

            _button("Normal", Colors.green, "normal"),
            const SizedBox(height: 10),
            _button("Pre-Fire", Colors.yellow, "pre_fire"),
            const SizedBox(height: 10),
            _button("Smoldering", Colors.orangeAccent, "smoldering"),
            const SizedBox(height: 10),
            _button("Ignition", Colors.deepOrange, "ignition"),
            const SizedBox(height: 10),
            _button("Developing Fire", Colors.red, "developing"),
            const SizedBox(height: 10),
            _button("DANGEROUS FIRE", Colors.red.shade900, "dangerous"),

            const SizedBox(height: 20),
            _buildStatusBox(),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // 🔥 LIVE CNN OVERLAY BOX
  // ===========================================================
  Widget _buildLiveCnnBox() {
    double latestSeverity = severityLog.isEmpty ? 0 : severityLog.last;
    double latestAlert = alertLog.isEmpty ? 0 : alertLog.last;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            "🔎 LIVE CNN OUTPUT",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            "Severity: ${latestSeverity.toStringAsFixed(3)}\n"
            "Alert: ${latestAlert.toStringAsFixed(3)}",
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          _buildMiniGraph("Severity", severityLog, Colors.orange),
          const SizedBox(height: 10),
          _buildMiniGraph("Alert", alertLog, Colors.redAccent),
        ],
      ),
    );
  }

  // MINI HISTOGRAM-LIKE GRAPH (no external libs)
  Widget _buildMiniGraph(String label, List<double> values, Color color) {
    return Container(
      height: 60,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: values.map((v) {
          double h = (v.clamp(0, 1)) * 50;
          return Expanded(
            child: Container(
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              color: color,
            ),
          );
        }).toList(),
      ),
    );
  }

  // ===========================================================
  // BUTTON MAKER
  // ===========================================================
  Widget _button(String title, Color color, String state) {
    return ElevatedButton(
      onPressed: _running ? null : () => _simulate(state),
      style: ElevatedButton.styleFrom(backgroundColor: color),
      child: Text(title),
    );
  }

  // ===========================================================
  // SENSOR SIMULATION
  // ===========================================================
  String _now() => DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

  Future<void> _simulate(String level) async {
    Map<String, dynamic> entry;

    switch (level) {
      case "normal":
        entry = {
          "detected": "no",
          "flame": 0,
          "humidity": 60,
          "smoke": 30,
          "temperature": 30,
          "thermal_max": 28,
          "thermal_avg": 26,
          "timestamp": _now(),
        };
        break;

      case "pre_fire":
        entry = {
          "detected": "yes",
          "flame": 0,
          "humidity": 45,
          "smoke": 300,
          "temperature": 36,
          "thermal_max": 45,
          "thermal_avg": 42,
          "timestamp": _now(),
        };
        break;

      case "smoldering":
        entry = {
          "detected": "yes",
          "flame": 0,
          "humidity": 40,
          "smoke": 900,
          "temperature": 41,
          "thermal_max": 58,
          "thermal_avg": 54,
          "timestamp": _now(),
        };
        break;

      case "ignition":
        entry = {
          "detected": "yes",
          "flame": 1,
          "humidity": 32,
          "smoke": 1300,
          "temperature": 48,
          "thermal_max": 78,
          "thermal_avg": 72,
          "timestamp": _now(),
        };
        break;

      case "developing":
        entry = {
          "detected": "yes",
          "flame": 1,
          "humidity": 25,
          "smoke": 2200,
          "temperature": 60,
          "thermal_max": 98,
          "thermal_avg": 92,
          "timestamp": _now(),
        };
        break;

      case "dangerous":
      default:
        entry = {
          "detected": "yes",
          "flame": 1,
          "humidity": 15,
          "smoke": 3500,
          "temperature": 75,
          "thermal_max": 115,
          "thermal_avg": 108,
          "timestamp": _now(),
        };
        break;
    }

    await _sendSensor(entry, level.toUpperCase());
  }

  // ===========================================================
  // PUSH SENSOR DATA TO FIREBASE
  // ===========================================================
  Future<void> _sendSensor(Map<String, dynamic> entry, String label) async {
    final pretty = const JsonEncoder.withIndent("  ").convert(entry);

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

  // STATUS BOX
  Widget _buildStatusBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(_status),
    );
  }
}
