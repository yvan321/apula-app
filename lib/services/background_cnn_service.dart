import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class BackgroundCnnService {
  static bool _running = false;
  static Interpreter? _interpreter;

  static late DatabaseReference _yoloRef;
  static late DatabaseReference _sensorRef;

  static Future<void> initialize() async {
    if (_running) return;
    _running = true;

    print("🔥 Background CNN Service Started");

    // Load model
    _interpreter = await Interpreter.fromAsset(
      "assets/models/APULA_FUSION_CNN_v2.tflite",
    );

    // Connect YOLO + SENSOR (Realtime DB)
    _yoloRef = FirebaseDatabase.instance.ref("cam_detections/latest");
    _sensorRef = FirebaseDatabase.instance.ref("sensor_data/latest");

    _startLoop();
  }

  static void _startLoop() {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_running) return;

      final yoloSnap = await _yoloRef.get();
      final sensorSnap = await _sensorRef.get();

      if (!yoloSnap.exists || !sensorSnap.exists) {
        print("⚠️ YOLO or Sensor data missing");
        return;
      }

      final yolo = Map<String, dynamic>.from(yoloSnap.value as Map);
      final sensor = Map<String, dynamic>.from(sensorSnap.value as Map);

      final input = [
        (yolo["yolo_conf"] ?? 0).toDouble(),
        (sensor["temperature"] ?? 0).toDouble(),
        (sensor["humidity"] ?? 0).toDouble(),
        (sensor["smoke"] ?? 0).toDouble(),
        (sensor["flame"] ?? 0).toDouble(),
        (sensor["thermal_max"] ?? 0).toDouble(),
        (sensor["thermal_avg"] ?? 0).toDouble(),
        (yolo["yolo_fire_conf"] ?? 0).toDouble(),
        (yolo["yolo_smoke_conf"] ?? 0).toDouble(),
        (yolo["yolo_no_fire_conf"] ?? 0).toDouble(),
      ];

      print("📥 CNN Input: $input");

      var inputTensor = [input];
      var outputTensor = List.filled(2, 0.0).reshape([1, 2]);

      _interpreter!.run(inputTensor, outputTensor);

      final severity = outputTensor[0][0];
      final alert = outputTensor[0][1];

      print("📤 CNN Output → severity=$severity alert=$alert");

      // SAVE to Firestore (MAIN FLUTTER FIREBASE)
      await FirebaseFirestore.instance.collection("cnn_results").add({
        "device_id": "cam_01",
        "severity": severity,
        "alert": alert,
        "timestamp": FieldValue.serverTimestamp(),
      });

      print("🔥 CNN output sent to Firestore!");
    });
  }
}
