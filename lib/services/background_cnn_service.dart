import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:apula/utils/alert_source_attribution.dart';

class BackgroundCnnService {
  static bool _running = false;
  static Interpreter? _interpreter;

  static late DatabaseReference _yoloRef;
  static late DatabaseReference _rtdb;

  static final List<double> _mean = [
    0.24949, 35.6933, 57.2247, 507.3727, 0.0833,
    50.2028, 43.1953, 0.0911, 0.1228, 0.6887
  ];

  static final List<double> _scale = [
    0.3069, 19.9284, 19.8688, 1175.5076, 0.2764,
    53.5127, 40.5986, 0.2621, 0.2466, 0.4485
  ];

  static List<double> _scaleInput(List<double> x) {
    return List.generate(x.length, (i) => (x[i] - _mean[i]) / _scale[i]);
  }

  static Future<void> initialize(FirebaseApp app) async {
    if (_running) return;
    _running = true;

    _interpreter = await Interpreter.fromAsset(
      "assets/ml/cnn_model_quant.tflite",
      options: InterpreterOptions()..threads = 4,
    );

    final rtdb = FirebaseDatabase.instanceFor(app: app);
    _rtdb = rtdb.ref();
    _yoloRef = rtdb.ref("cam_detections/latest");

    _startLoop();
  }

  static void _startLoop() {
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!_running || _interpreter == null) return;

      final yoloSnap = await _yoloRef.get();
      if (!yoloSnap.exists) return;

      final yolo = Map<String, dynamic>.from(yoloSnap.value as Map);
      
      // Extract camera_id from YOLO data
      final String cameraId = yolo["camera_id"]?.toString() ?? "cam_01";

      // Read camera-scoped sensor path first: sensor_data/{cameraId}/latest
      DataSnapshot sensorSnap = await _rtdb.child("sensor_data/$cameraId/latest").get();
      if (!sensorSnap.exists) {
        sensorSnap = await _rtdb.child("sensor_data/latest").get();
      }
      
      // Get sensor data for this camera (or legacy shared sensor fallback)
      final Map<String, dynamic> sensor = sensorSnap.exists
          ? Map<String, dynamic>.from(sensorSnap.value as Map)
          : <String, dynamic>{};

      final Map<String, dynamic> cameraSensor = sensor;

      final List<double> raw = [
        (yolo["yolo_conf"] ?? 0).toDouble(),
        (cameraSensor["DHT_Temp"] ?? 0).toDouble(),
        (cameraSensor["DHT_Humidity"] ?? 0).toDouble(),
        (cameraSensor["MQ2_Value"] ?? 0).toDouble(),
        (cameraSensor["Flame_Det"] ?? 0).toDouble(),
        (cameraSensor["thermal_max"] ?? 0).toDouble(),
        (cameraSensor["thermal_avg"] ?? 0).toDouble(),
        (yolo["yolo_fire_conf"] ?? 0).toDouble(),
        (yolo["yolo_smoke_conf"] ?? 0).toDouble(),
        (yolo["yolo_no_fire_conf"] ?? 1).toDouble(),
      ];

      final scaled = _scaleInput(raw);
      final input = [scaled.map((v) => [v]).toList()];
      final output = List.generate(1, (_) => List.filled(2, 0.0));

      _interpreter!.run(input, output);

      final attribution = AlertSourceAttribution.fromSignals(
        yoloConf: raw[0],
        temperature: raw[1],
        humidity: raw[2],
        mq2: raw[3],
        flame: raw[4],
        thermalMax: raw[5],
        thermalAvg: raw[6],
        yoloFireConf: raw[7],
        yoloSmokeConf: raw[8],
        yoloNoFireConf: raw[9],
      );

      // Write CNN results to camera-specific path
      final cnnOutRef = _rtdb.child("cnn_results/$cameraId");
      await cnnOutRef.set({
        "severity": output[0][0],
        "alert": output[0][1],
        "timestamp": ServerValue.timestamp,
        "input": {
          "image_url": yolo["image_url"],
          "yolo_conf": raw[0],
          "yolo_fire_conf": raw[7],
          "yolo_smoke_conf": raw[8],
          "yolo_no_fire_conf": raw[9],
        },
        "sensor": {
          "DHT_Temp": raw[1],
          "DHT_Humidity": raw[2],
          "MQ2_Value": raw[3],
          "Flame_Det": raw[4],
          "thermal_max": raw[5],
          "thermal_avg": raw[6],
        },
        "attribution": attribution,
      });
    });
  }
}
