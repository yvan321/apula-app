import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../main.dart';

class FireDemoPage extends StatefulWidget {
  const FireDemoPage({super.key});

  @override
  State<FireDemoPage> createState() => _FireDemoPageState();
}

class _FireDemoPageState extends State<FireDemoPage> {
  final DatabaseReference _rtdb =
      FirebaseDatabase.instanceFor(app: yoloFirebaseApp).ref();

  // =========================
  // VIDEO STATE
  // =========================
  late final WebViewController _webViewController;
  bool _videoLoaded = false;

  // =========================
  // DEMO / CNN STATE
  // =========================
  bool _running = false;
  String _status = "No simulation yet.";

  final List<double> severityLog = [];
  final List<double> alertLog = [];

  @override
  void initState() {
    super.initState();

    // -------------------------
    // WEBVIEW INIT (NO SPINNER LOGIC)
    // -------------------------
    final params = PlatformWebViewControllerCreationParams();

    _webViewController = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);

    if (Platform.isAndroid) {
      final androidController =
          _webViewController.platform as AndroidWebViewController;

      androidController.setMediaPlaybackRequiresUserGesture(false);
    }

    _listenToViewerUrl();
    _listenToCnn();
  }

  // =========================
  // 🔥 LISTEN TO VIEWER URL
  // =========================
  
  void _listenToViewerUrl() {
    final ref = _rtdb.child("cloudflare/cam_01/video_feed");

    ref.onValue.listen((event) {
      final url = event.snapshot.value as String?;
      if (url == null || _videoLoaded) return;

      _videoLoaded = true;

      final html = '''
  <!DOCTYPE html>
  <html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
      html, body {
        margin: 0;
        padding: 0;
        background: black;
        width: 100%;
        height: 100%;
        overflow: hidden;
      }
      img {
        width: 100%;
        height: 100%;
        object-fit: contain;
      }
    </style>
  </head>
  <body>
    <img src="$url" />
  </body>
  </html>
  ''';

      _webViewController.loadHtmlString(html);
      setState(() {});
    });
  }

  // =========================
  // 🔥 LISTEN TO CNN OUTPUTS
  // =========================
  void _listenToCnn() {
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

  // =========================
  // UI
  // =========================
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
            // =========================
            // 🎥 VIDEO VIEW
            // =========================
            SizedBox(
              height: 220,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _videoLoaded
                    ? WebViewWidget(controller: _webViewController)
                    : const Center(
                        child: Text(
                          "Waiting for video stream…",
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 20),

            _buildLiveCnnBox(),

            const SizedBox(height: 20),

            const Text(
              "Send Simulated Sensor Readings",
              style: TextStyle(fontWeight: FontWeight.bold),
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

  // =========================
  // CNN UI
  // =========================
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
        ],
      ),
    );
  }

  // =========================
  // SENSOR SIM
  // =========================
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
      default:
        entry = {
          "DHT_Temp": 75,
          "DHT_Humidity": 15,
          "MQ2_Value": 3500,
          "Flame_Det": 1,
          "timestamp": _now(),
        };
    }

    await _rtdb.child("sensor_data/latest").set(entry);

    setState(() {
      _status = "SENT:\n${const JsonEncoder.withIndent("  ").convert(entry)}";
    });
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
