import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  DatabaseReference? _rtdb;
  Timer? _timer;
  FlutterLocalNotificationsPlugin? _localNotifications;

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
      _rtdb = rtdb.ref();
      _yoloRef = rtdb.ref("cam_detections/latest");
      _sensorRef = rtdb.ref("sensor_data/latest");
      print('✅ Firebase RTDB refs created from yoloApp');

      // Initialize local notifications
      _localNotifications = FlutterLocalNotificationsPlugin();
      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await _localNotifications!.initialize(
        InitializationSettings(android: androidInit),
      );
      print('✅ Local notifications initialized');

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
      // Get camera_id from latest YOLO data
      final yoloSnap = await _yoloRef!.get();
      if (!yoloSnap.exists) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'APULA AI Monitoring',
          notificationText: 'Waiting for camera data...',
        );
        return;
      }

      final yoloData = yoloSnap.value as Map;
      final String cameraId = yoloData["camera_id"]?.toString() ?? "cam_01";

      // Get pre-computed CNN results instead of doing inference
      final cnnSnap = await _rtdb!.child("cnn_results/$cameraId").get();
      if (!cnnSnap.exists) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'APULA AI Monitoring',
          notificationText: 'Waiting for CNN analysis...',
        );
        return;
      }

      final cnnData = cnnSnap.value as Map;
      final double severity = (cnnData["severity"] ?? 0.0).toDouble();
      final double alert = (cnnData["alert"] ?? 0.0).toDouble();
      final String snapshotUrl = (cnnData["input"]?["image_url"] ?? "") as String;

      // Apply same thresholds as GlobalAlertHandler
      final bool cautionNow = severity >= 0.40 && alert >= 0.73;
      final bool ignitionNow = severity >= 0.55 && alert >= 0.75;
      final bool dangerousNow = severity >= 0.70 && alert >= 0.80;

      String label = "NO_FIRE";
      if (dangerousNow) {
        label = "🔴 EXTREME FIRE DANGER";
      } else if (ignitionNow) {
        label = "🟠 IGNITION ANOMALY";
      } else if (cautionNow) {
        label = "🟡 FIRE-LIKE ACTIVITY";
      }

      // Update notification
      final statusText =
          '$label - Severity: ${(severity * 100).toStringAsFixed(1)}% | Alert: ${(alert * 100).toStringAsFixed(1)}%';
      FlutterForegroundTask.updateService(
        notificationTitle: 'APULA AI Monitoring',
        notificationText: statusText,
      );

      // Send popup notification if alert detected
      if (label != "NO_FIRE") {
        await _showAlertNotification(
          title: label,
          body: 'Camera: $cameraId | Severity: ${(severity * 100).toStringAsFixed(1)}%',
          severity: severity,
          isExtreme: dangerousNow,
        );
        print('🔥 AI: $label (Camera: $cameraId | Severity: ${(severity * 100).toStringAsFixed(1)}%, Alert: ${(alert * 100).toStringAsFixed(1)}%)');
      } else {
        print('✅ Status: NORMAL (Camera: $cameraId)');
      }
    } catch (e) {
      print('❌ Inference Error: $e');
      final errorMsg = e.toString();
      FlutterForegroundTask.updateService(
        notificationTitle: 'APULA AI Monitoring',
        notificationText: 'Error: ${errorMsg.length > 50 ? errorMsg.substring(0, 50) : errorMsg}',
      );
    }
  }

  Future<void> _showAlertNotification({
    required String title,
    required String body,
    required double severity,
    required bool isExtreme,
  }) async {
    try {
      final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'apula_foreground_alerts',
        'APULA Fire Alerts',
        channelDescription: 'Real-time fire detection alerts',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      const NotificationDetails notificationDetails =
          NotificationDetails(android: androidDetails);

      await _localNotifications!.show(
        notificationId,
        title,
        body,
        notificationDetails,
      );

      print('📲 Alert notification shown: $title');
    } catch (e) {
      print('❌ Error showing alert notification: $e');
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
