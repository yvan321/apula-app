import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class BackgroundCnnService {
  static bool _running = false;
  static Interpreter? _interpreter;

  static late DatabaseReference _yoloRef;
  static late DatabaseReference _sensorRef;
  static late DatabaseReference _cnnOutRef;

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
    _yoloRef = rtdb.ref("cam_detections/latest");
    _sensorRef = rtdb.ref("sensor_data/latest");
    _cnnOutRef = rtdb.ref("cnn_results/CCTV1");

    _startLoop();
  }

  static void _startLoop() {
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!_running || _interpreter == null) return;

      final yoloSnap = await _yoloRef.get();
      final sensorSnap = await _sensorRef.get();
      if (!yoloSnap.exists) return;

      final yolo = Map<String, dynamic>.from(yoloSnap.value as Map);
      final sensor = sensorSnap.exists
          ? Map<String, dynamic>.from(sensorSnap.value as Map)
          : {};

      final List<double> raw = [
        (yolo["yolo_conf"] ?? 0).toDouble(),
        (sensor["DHT_Temp"] ?? 0).toDouble(),
        (sensor["DHT_Humidity"] ?? 0).toDouble(),
        (sensor["MQ2_Value"] ?? 0).toDouble(),
        (sensor["Flame_Det"] ?? 0).toDouble(),
        (sensor["thermal_max"] ?? 0).toDouble(),
        (sensor["thermal_avg"] ?? 0).toDouble(),
        (yolo["yolo_fire_conf"] ?? 0).toDouble(),
        (yolo["yolo_smoke_conf"] ?? 0).toDouble(),
        (yolo["yolo_no_fire_conf"] ?? 1).toDouble(),
      ];

      final scaled = _scaleInput(raw);
      final input = [scaled.map((v) => [v]).toList()];
      final output = List.generate(1, (_) => List.filled(2, 0.0));

      _interpreter!.run(input, output);

      await _cnnOutRef.set({
        "severity": output[0][0],
        "alert": output[0][1],
        "timestamp": ServerValue.timestamp,
        "input": {"image_url": yolo["image_url"]},
      });
    });
  }
}
