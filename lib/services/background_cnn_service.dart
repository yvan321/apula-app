import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';

import 'global_alert_handler.dart';

class BackgroundCnnService {
  static bool _running = false;
  static Interpreter? _interpreter;

  static late DatabaseReference _yoloRef;
  static late DatabaseReference _sensorRef;
  static late DatabaseReference _cnnOutRef;

  // modal cooldown so UI isn't spammed
  static DateTime? _lastModalTime;
  static const Duration modalCooldown = Duration(seconds: 8);

  /// Initialize with the YOLO Firebase app (the RTDB project)
  static Future<void> initialize(FirebaseApp yoloApp) async {
    if (_running) return;
    _running = true;

    print("🔥 Background CNN Service Started");

    try {
      _interpreter = await Interpreter.fromAsset(
        "assets/models/APULA_FUSION_CNN_v2.tflite",
      );
    } catch (e) {
      print("❌ Error loading CNN model: $e");
      return;
    }

    // Use the YOLO RTDB FirebaseApp to access the correct Realtime DB
    final rtdb = FirebaseDatabase.instanceFor(app: yoloApp);

    _yoloRef = rtdb.ref("cam_detections/latest");
    _sensorRef = rtdb.ref("sensor_data/latest");
    _cnnOutRef = rtdb.ref("cnn_results/CCTV1");

    _startLoop();
  }

  static void _startLoop() {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_running || _interpreter == null) return;

      try {
        final yoloSnap = await _yoloRef.get();
        final sensorSnap = await _sensorRef.get();

        if (!yoloSnap.exists) {
          print("⚠️ YOLO data missing.");
          return;
        }

        if (!sensorSnap.exists) {
          print("⚠️ Sensor data missing (using defaults).");
        }

        final yolo = Map<String, dynamic>.from(yoloSnap.value as Map);
        final sensor = sensorSnap.exists
            ? Map<String, dynamic>.from(sensorSnap.value as Map)
            : {};

        // safe defaults if sensors missing (for testing you can tweak these)
        double mlxMax = (sensor["thermal_max"] ?? 0).toDouble();
        double mlxAvg = (sensor["thermal_avg"] ?? 0).toDouble();

        final input = [
          (yolo["yolo_conf"] ?? 0).toDouble(),
          (sensor["temperature"] ?? 0).toDouble(),
          (sensor["humidity"] ?? 0).toDouble(),
          (sensor["smoke"] ?? 0).toDouble(),
          (sensor["flame"] ?? 0).toDouble(),
          mlxMax,
          mlxAvg,
          (yolo["yolo_fire_conf"] ?? 0).toDouble(),
          (yolo["yolo_smoke_conf"] ?? 0).toDouble(),
          (yolo["yolo_no_fire_conf"] ?? 0).toDouble(),
        ];

        // debug: always print the input so you can see activity
        if (kDebugMode) print("📥 CNN INPUT: $input");

        var inputTensor = [input];
        var outputTensor = List.filled(2, 0.0).reshape([1, 2]);

        _interpreter!.run(inputTensor, outputTensor);

        double severity = outputTensor[0][0];
        double alert = outputTensor[0][1];

        if (kDebugMode) print("📤 CNN OUTPUT → severity=$severity alert=$alert");

        // Save to RTDB (CNN results)
        await _cnnOutRef.set({
          "severity": severity,
          "alert": alert,
          "timestamp": ServerValue.timestamp,
        });

        // prevent modal spam: but do NOT prevent alerts from being written
        if (_lastModalTime != null &&
            DateTime.now().difference(_lastModalTime!) < modalCooldown) {
          // still update RTDB, but skip showing modal
          if (kDebugMode) print("⏱ modal cooldown active - skipping UI modal");
          return;
        }

        // choose snapshot URL from YOLO node (supports image_url or frame)
        String snapshotUrl = "";
        try {
          snapshotUrl = (yolo["image_url"] ?? yolo["frame"] ?? "") as String;
        } catch (_) {
          snapshotUrl = "";
        }

        // Show modal anywhere in the app (GlobalAlertHandler writes Firestore alerts)
        GlobalAlertHandler.showFireModal(
          alert: alert,
          severity: severity,
          snapshotUrl: snapshotUrl,
          deviceName: yolo["camera_id"] ?? "Unknown Camera",
        );

        _lastModalTime = DateTime.now();
      } catch (e, st) {
        print("❌ BackgroundCnnService loop error: $e\n$st");
      }
    });
  }

  /// Optional: stop the service if needed
  static Future<void> stop() async {
    _running = false;
    // Interpreter disposal not strictly necessary here, but could be added
    _interpreter = null;
  }
}
