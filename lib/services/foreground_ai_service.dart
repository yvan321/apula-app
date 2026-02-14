import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../firebase_yolo_options.dart';

// Foreground Task Handler (runs in isolate)
@pragma('vm:entry-point')
class ForegroundAITaskHandler extends TaskHandler {
  Interpreter? _interpreter;
  List<double>? _means;
  List<double>? _stds;
  DatabaseReference? _yoloRef;
  DatabaseReference? _sensorRef;
  DatabaseReference? _cnnOutRef;
  Timer? _timer;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('🚀 Foreground AI Service Started');
    
    try {
      // Update notification - loading model
      FlutterForegroundTask.updateService(
        notificationTitle: 'APULA AI Monitoring',
        notificationText: 'Loading AI model...',
      );
      
      // Initialize Firebase apps (in isolate, need to initialize both)
      FirebaseApp yoloApp;
      try {
        // Try to get existing app
        yoloApp = Firebase.app('yoloApp');
      } catch (e) {
        // Initialize if not exists
        await Firebase.initializeApp();
        yoloApp = await Firebase.initializeApp(
          name: 'yoloApp',
          options: FirebaseYoloOptions.options,
        );
      }
      print('✅ Firebase initialized');
      
      // Load ML model - use quantized model like background_cnn_service
      _interpreter = await Interpreter.fromAsset(
        "assets/ml/cnn_model_quant.tflite",
        options: InterpreterOptions()..threads = 2,
      );
      print('✅ Model loaded');

      // Update notification - loading scaler
      FlutterForegroundTask.updateService(
        notificationTitle: 'APULA AI Monitoring',
        notificationText: 'Loading feature scaler...',
      );

      // Load scaler
      final scalerJson = await rootBundle.loadString("assets/ml/cnn_scaler.json");
      final scaler = jsonDecode(scalerJson);
      _means = List<double>.from(scaler["mean"]);
      _stds = List<double>.from(scaler["scale"]); // Note: JSON has 'scale' not 'std'
      print('✅ Scaler loaded (mean: ${_means!.length}, scale: ${_stds!.length})');

      // Firebase refs - USE YOLO FIREBASE APP
      final rtdb = FirebaseDatabase.instanceFor(app: yoloApp);
      _yoloRef = rtdb.ref("cam_detections/latest");
      _sensorRef = rtdb.ref("sensor_data/latest");
      _cnnOutRef = rtdb.ref("cnn_results/foreground");
      print('✅ Firebase RTDB refs created from yoloApp');

      // Update notification - ready
      FlutterForegroundTask.updateService(
        notificationTitle: 'APULA AI Monitoring',
        notificationText: 'Ready - Waiting for sensor data...',
      );
      print('✅ Service ready, starting inference loop');

      // Start periodic inference (every 5 seconds)
      _timer = Timer.periodic(Duration(seconds: 5), (_) => _runInference());
      
      // Run first inference immediately
      await _runInference();
      
    } catch (e) {
      print('❌ Foreground Service Init Error: $e');
      FlutterForegroundTask.updateService(
        notificationTitle: 'APULA AI Monitoring',
        notificationText: 'Error: $e',
      );
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This is called every interval set in notificationInterval
    // We use Timer instead for more control
  }

  Future<void> _runInference() async {
    try {
      if (_interpreter == null || _means == null || _stds == null) {
        print('⚠️ Not ready for inference');
        return;
      }

      // Get data
      final yoloSnap = await _yoloRef!.get();
      final sensorSnap = await _sensorRef!.get();

      if (!yoloSnap.exists || !sensorSnap.exists) {
        print('⚠️ No sensor data available yet');
        FlutterForegroundTask.updateService(
          notificationTitle: 'APULA AI Monitoring',
          notificationText: 'Waiting for sensor data from cameras...',
        );
        return;
      }

      final yoloData = yoloSnap.value as Map;
      final sensorData = sensorSnap.value as Map;

      // Build features - matching background_cnn_service.dart field names
      List<double> features = [
        (yoloData["yolo_conf"] ?? 0.0).toDouble(),
        (sensorData["DHT_Temp"] ?? 0.0).toDouble(),
        (sensorData["DHT_Humidity"] ?? 0.0).toDouble(),
        (sensorData["MQ2_Value"] ?? 0.0).toDouble(),
        (sensorData["Flame_Det"] ?? 0.0).toDouble(),
        (sensorData["thermal_max"] ?? 0.0).toDouble(),
        (sensorData["thermal_avg"] ?? 0.0).toDouble(),
        (yoloData["yolo_fire_conf"] ?? 0.0).toDouble(),
        (yoloData["yolo_smoke_conf"] ?? 0.0).toDouble(),
        (yoloData["yolo_no_fire_conf"] ?? 1.0).toDouble(),
      ];

      // Normalize
      List<double> normalized = List.generate(
        features.length,
        (i) => (features[i] - _means![i]) / _stds![i],
      );

      // Run inference - same format as background_cnn_service
      var input = [normalized.map((v) => [v]).toList()];
      var output = List.generate(1, (_) => List.filled(2, 0.0));
      
      _interpreter!.run(input, output);

      final fireProb = output[0][0]; // severity
      final alertProb = output[0][1]; // alert
      final label = fireProb > 0.5 ? "FIRE" : "NO_FIRE";

      // Update notification
      FlutterForegroundTask.updateService(
        notificationTitle: 'APULA AI Monitoring',
        notificationText: '$label - Severity: ${(fireProb * 100).toStringAsFixed(1)}% | Alert: ${(alertProb * 100).toStringAsFixed(1)}%',
      );

      // Save to Firebase
      await _cnnOutRef!.set({
        "severity": fireProb,
        "alert": alertProb,
        "prediction": label,
        "timestamp": DateTime.now().toIso8601String(),
        "source": "foreground_service",
      });

      print('🔥 AI: $label (Severity: ${(fireProb * 100).toStringAsFixed(1)}%, Alert: ${(alertProb * 100).toStringAsFixed(1)}%)');
      
    } catch (e) {
      print('❌ Inference Error: $e');
      final errorMsg = e.toString();
      FlutterForegroundTask.updateService(
        notificationTitle: 'APULA AI Monitoring',
        notificationText: 'Error: ${errorMsg.length > 50 ? errorMsg.substring(0, 50) : errorMsg}',
      );
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    print('🛑 Foreground AI Service Stopped');
    _timer?.cancel();
    _interpreter?.close();
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Handle notification button press
  }

  @override
  void onNotificationPressed() {
    // Handle notification press - open app
    FlutterForegroundTask.launchApp();
  }
}
