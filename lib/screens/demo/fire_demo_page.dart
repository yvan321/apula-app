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
  final String flaskStream = "http://10.198.39.202:5000/video_feed";

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

  // ===========================================================
  // ✅ ADDED: VIDEO FEED SWITCHING (Firebase → Python listener)
  // ===========================================================
  Future<void> _setVideoMode(int mode) async {
    try {
      await _rtdb.child("yolo_demo/mode").set(mode);
      setState(() {
        _status = "🎥 Video source switched to mode $mode";
      });
    } catch (e) {
      setState(() {
        _status = "❌ Failed to switch video source: $e";
      });
    }
  }

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
            // 🔥 VIDEO STREAM
            SizedBox(
              height: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MJpegView(
                  key: const ValueKey("stream_default"),
                  url: flaskStream,
                ),
              ),
            ),

            // ===================================================
            // ✅ ADDED: VIDEO SOURCE BUTTONS (5 FEEDS)
            // ===================================================
            const SizedBox(height: 16),
            const Text(
              "🎥 VIDEO SOURCE CONTROL",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: () => _setVideoMode(0),
              child: const Text("LIVE CCTV"),
            ),
            ElevatedButton(
              onPressed: () => _setVideoMode(1),
              child: const Text("DEMO 1 – NORMAL"),
            ),
            ElevatedButton(
              onPressed: () => _setVideoMode(2),
              child: const Text("DEMO 2 – SMOKE"),
            ),
            ElevatedButton(
              onPressed: () => _setVideoMode(3),
              child: const Text("DEMO 3 – FIRE"),
            ),
            ElevatedButton(
              onPressed: () => _setVideoMode(4),
              child: const Text("DEMO 4 – FULL SCENARIO"),
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

  Widget _button(String title, Color color, String state) {
    return ElevatedButton(
      onPressed: _running ? null : () => _simulate(state),
      style: ElevatedButton.styleFrom(backgroundColor: color),
      child: Text(title),
    );
  }

  String _now() => DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

  Future<void> _simulate(String level) async {
    Map<String, dynamic> entry;

    switch (level) {
      case "normal":
        entry = {
          "DHT_Temp": 30,
          "DHT_Humidity": 60,
          "MQ2_Value": 80,
          "Flame_Det": 0,
          "timestamp": _now(),
        };
        break;
      case "pre_fire":
        entry = {
          "DHT_Temp": 35,
          "DHT_Humidity": 50,
          "MQ2_Value": 300,
          "Flame_Det": 0,
          "timestamp": _now(),
        };
        break;
      case "smoldering":
        entry = {
          "DHT_Temp": 40,
          "DHT_Humidity": 45,
          "MQ2_Value": 900,
          "Flame_Det": 0,
          "timestamp": _now(),
        };
        break;
      case "ignition":
        entry = {
          "DHT_Temp": 48,
          "DHT_Humidity": 35,
          "MQ2_Value": 1300,
          "Flame_Det": 1,
          "timestamp": _now(),
        };
        break;
      case "developing":
        entry = {
          "DHT_Temp": 60,
          "DHT_Humidity": 25,
          "MQ2_Value": 2200,
          "Flame_Det": 1,
          "timestamp": _now(),
        };
        break;
      case "dangerous":
      default:
        entry = {
          "DHT_Temp": 75,
          "DHT_Humidity": 15,
          "MQ2_Value": 3500,
          "Flame_Det": 1,
          "timestamp": _now(),
        };
        break;
    }

    await _sendSensor(entry, level.toUpperCase());
  }

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
