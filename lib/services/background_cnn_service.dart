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

  // -------------------------------------------------------------
  // SCALER VALUES (from cnn_scaler.pkl)
  // -------------------------------------------------------------
  static final List<double> _mean = [
    0.24948899260189591,
    35.69337547159195,
    57.22471392762661,
    507.37272470223854,
    0.083375,
    50.20280826854706,
    43.195395507574084,
    0.09111851083429622,
    0.12289206686148176,
    0.6887884528734644,
  ];

  static final List<double> _scale = [
    0.30690666882130047,
    19.928479916699356,
    19.868865084499838,
    1175.5076962186,
    0.27644820378325663,
    53.512729085106955,
    40.598639881563464,
    0.26213261535207977,
    0.24665386924017169,
    0.44858458096243303,
  ];

  static List<double> _scaleInput(List<double> x) {
    return List.generate(x.length, (i) => ((x[i] - _mean[i]) / _scale[i]));
  }

  // -------------------------------------------------------------
  // INITIALIZE
  // -------------------------------------------------------------
  static Future<void> initialize(FirebaseApp yoloApp) async {
    if (_running) return;
    _running = true;

    print("🔥 Background CNN Service Started");

    try {
      _interpreter = await Interpreter.fromAsset(
        "assets/ml/cnn_model_quant.tflite",
        options: InterpreterOptions()..threads = 4,
      );
      print("✓ CNN Model Loaded");
    } catch (e) {
      print("❌ Failed to load CNN model: $e");
      return;
    }

    final rtdb = FirebaseDatabase.instanceFor(app: yoloApp);

    _yoloRef = rtdb.ref("cam_detections/latest");
    _sensorRef = rtdb.ref("sensor_data/latest");
    _cnnOutRef = rtdb.ref("cnn_results/CCTV1");

    _startLoop();
  }

  // -------------------------------------------------------------
  // LOOP — runs every 2 seconds
  // -------------------------------------------------------------
  static void _startLoop() {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_running || _interpreter == null) return;

      try {
        final yoloSnap = await _yoloRef.get();
        final sensorSnap = await _sensorRef.get();

        if (!yoloSnap.exists) {
          print("⚠ YOLO data missing.");
          return;
        }

        final yolo = Map<String, dynamic>.from(yoloSnap.value as Map);
        final sensor = sensorSnap.exists
            ? Map<String, dynamic>.from(sensorSnap.value as Map)
            : {};

        // ---------------------------------------------------------
        // RAW INPUT → 10 FEATURES
        // ---------------------------------------------------------
        final List<double> raw = [
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

        // ---------------------------------------------------------
        // SCALE + RESHAPE → (1,10,1)
        // ---------------------------------------------------------
        final scaled = _scaleInput(raw);
        final formattedInput = [
          scaled.map((v) => [v]).toList(),
        ];

        // ---------------------------------------------------------
        // MODEL OUTPUT: (1,2) → [severity, alert]
        // ---------------------------------------------------------
        var output = List.generate(1, (_) => List.filled(2, 0.0));

        _interpreter!.run(formattedInput, output);

        final double severity = output[0][0];
        final double alert = output[0][1];

        print("📤 CNN OUTPUT → severity=$severity  alert=$alert");

        // ---------------------------------------------------------
        // WRITE TO REALTIME DATABASE
        // ---------------------------------------------------------
        await _cnnOutRef.set({
          "severity": severity,
          "alert": alert,
          "timestamp": ServerValue.timestamp,
        });

      } catch (e, st) {
        print("❌ CNN Loop Error: $e\n$st");
      }
    });
  }

  static Future<void> stop() async {
    _running = false;
    _interpreter = null;
  }
}
