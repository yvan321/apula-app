import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../firebase_yolo_options.dart';
import '../utils/alert_source_attribution.dart';

// Foreground Task Handler (runs in isolate)
@pragma('vm:entry-point')
class ForegroundAITaskHandler extends TaskHandler {
  Interpreter? _interpreter;
  List<double>? _means;
  List<double>? _stds;
  DatabaseReference? _yoloRef;
  DatabaseReference? _rtdb;
  FlutterLocalNotificationsPlugin? _localNotifications;
  bool _isInferenceRunning = false;
  final Map<String, int> _eventNotificationCounts = {};
  final Map<String, DateTime> _lastNotificationTimeByCamera = {};
  DateTime? _lastAlertTime;
  static const int _maxNotificationsPerEvent = 2;
  static const Duration _eventResetSilence = Duration(minutes: 2);
  static const Duration _notificationCooldown = Duration(seconds: 45);

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
      _yoloRef = rtdb.ref("cam_detections");
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
    if (_isInferenceRunning) {
      return;
    }
    _isInferenceRunning = true;
    unawaited(
      _runInference().whenComplete(() {
        _isInferenceRunning = false;
      }),
    );
  }

  Future<void> _runInference() async {
    try {
      if (_interpreter == null || _means == null || _stds == null) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'APULA AI Monitoring',
          notificationText: 'Model not ready yet...',
        );
        return;
      }

      // Read per-camera YOLO latest entries from cam_detections/{cameraId}/latest
      final yoloSnap = await _yoloRef!.get();
      if (!yoloSnap.exists) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'APULA AI Monitoring',
          notificationText: 'Waiting for camera data...',
        );
        return;
      }

      final yoloEntries = _extractYoloEntries(yoloSnap.value);
      if (yoloEntries.isEmpty) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'APULA AI Monitoring',
          notificationText: 'Waiting for camera data...',
        );
        return;
      }

      int activeAlerts = 0;
      int processedCameras = 0;
      double topScore = -1;
      String topLabel = "NO_FIRE";
      String topCameraId = "";
      double topSeverity = 0;
      double topAlert = 0;

      for (final entry in yoloEntries.entries) {
        final cameraId = entry.key;
        final cnnSnap = await _rtdb!.child("cnn_results/$cameraId").get();
        if (!cnnSnap.exists || cnnSnap.value is! Map) {
          continue;
        }

        processedCameras++;

        final cnnData = Map<String, dynamic>.from(cnnSnap.value as Map);
        final double severity = _toDouble(cnnData["severity"]);
        final double alert = _toDouble(cnnData["alert"]);

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

        final score = severity + alert;
        if (score > topScore) {
          topScore = score;
          topLabel = label;
          topCameraId = cameraId;
          topSeverity = severity;
          topAlert = alert;
        }

        if (label != "NO_FIRE") {
          activeAlerts++;
          await _showAlertNotification(
            title: label,
            body: 'Camera: $cameraId | Severity: ${(severity * 100).toStringAsFixed(1)}%',
            severity: severity,
            isExtreme: dangerousNow,
            eventKey: '$cameraId|$label',
            cameraId: cameraId,
          );
          print('🔥 AI: $label (Camera: $cameraId | Severity: ${(severity * 100).toStringAsFixed(1)}%, Alert: ${(alert * 100).toStringAsFixed(1)}%)');
        }
      }

      if (processedCameras == 0) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'APULA AI Monitoring',
          notificationText: 'Waiting for valid camera + sensor data...',
        );
      } else if (activeAlerts == 0) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'APULA AI Monitoring',
          notificationText: '✅ NORMAL | Monitoring ${yoloEntries.length} cameras',
        );

        _eventNotificationCounts.clear();
        _lastNotificationTimeByCamera.clear();
        _lastAlertTime = null;
        print('✅ Status: NORMAL (${yoloEntries.length} cameras)');
      } else {
        FlutterForegroundTask.updateService(
          notificationTitle: 'APULA AI Monitoring',
          notificationText:
              '$topLabel | $topCameraId | Severity: ${(topSeverity * 100).toStringAsFixed(1)}% | Alert: ${(topAlert * 100).toStringAsFixed(1)}% | Active: $activeAlerts',
        );
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

  Future<Map<String, dynamic>?> _runInferenceForCamera(
    String cameraId,
    Map<String, dynamic> yoloData,
  ) async {
    DataSnapshot sensorSnap = await _rtdb!.child("sensor_data/$cameraId/latest").get();
    if (!sensorSnap.exists) {
      sensorSnap = await _rtdb!.child("sensor_data/latest").get();
    }

    if (!sensorSnap.exists || sensorSnap.value is! Map) {
      return null;
    }

    final sensorData = Map<String, dynamic>.from(sensorSnap.value as Map);

    final List<double> features = [
      _toDouble(yoloData["yolo_conf"]),
      _toDouble(sensorData["DHT_Temp"]),
      _toDouble(sensorData["DHT_Humidity"]),
      _toDouble(sensorData["MQ2_Value"]),
      _toDouble(sensorData["Flame_Det"]),
      _toDouble(sensorData["thermal_max"]),
      _toDouble(sensorData["thermal_avg"]),
      _toDouble(yoloData["yolo_fire_conf"]),
      _toDouble(yoloData["yolo_smoke_conf"]),
      _toDouble(yoloData["yolo_no_fire_conf"] == null ? 1.0 : yoloData["yolo_no_fire_conf"]),
    ];

    final normalized = List<double>.generate(
      features.length,
      (i) => (features[i] - _means![i]) / _stds![i],
    );

    final input = [normalized.map((v) => [v]).toList()];
    final output = List.generate(1, (_) => List.filled(2, 0.0));
    _interpreter!.run(input, output);

    final severity = output[0][0];
    final alert = output[0][1];

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

    final attribution = AlertSourceAttribution.fromSignals(
      yoloConf: features[0],
      temperature: features[1],
      humidity: features[2],
      mq2: features[3],
      flame: features[4],
      thermalMax: features[5],
      thermalAvg: features[6],
      yoloFireConf: features[7],
      yoloSmokeConf: features[8],
      yoloNoFireConf: features[9],
    );

    await _rtdb!.child("cnn_results/$cameraId").set({
      "severity": severity,
      "alert": alert,
      "prediction": label,
      "timestamp": DateTime.now().toIso8601String(),
      "source": "foreground_service",
      "input": {
        "image_url": (yoloData["image_url"] ?? "").toString(),
        "yolo_conf": features[0],
        "yolo_fire_conf": features[7],
        "yolo_smoke_conf": features[8],
        "yolo_no_fire_conf": features[9],
      },
      "sensor": {
        "DHT_Temp": features[1],
        "DHT_Humidity": features[2],
        "MQ2_Value": features[3],
        "Flame_Det": features[4],
        "thermal_max": features[5],
        "thermal_avg": features[6],
      },
      "attribution": attribution,
    });

    return {
      'severity': severity,
      'alert': alert,
      'label': label,
      'dangerousNow': dangerousNow,
    };
  }

  Map<String, Map<String, dynamic>> _extractYoloEntries(dynamic rawRoot) {
    final entries = <String, Map<String, dynamic>>{};
    if (rawRoot is! Map) return entries;

    final root = Map<String, dynamic>.from(rawRoot as Map);

    final latest = root['latest'];
    if (latest is Map) {
      final latestId = latest['camera_id']?.toString().trim() ?? '';
      if (latestId.isNotEmpty) {
        final payload = Map<String, dynamic>.from(latest as Map);
        payload['camera_id'] = latestId;
        entries[latestId] = payload;
      }
    }

    for (final entry in root.entries) {
      final key = entry.key.toString();
      if (key == 'latest') continue;

      final value = entry.value;
      if (value is! Map) continue;

      Map<String, dynamic> payload;
      if (value['latest'] is Map) {
        final inner = value['latest'] as Map;
        payload = Map<String, dynamic>.from(inner);
      } else {
        payload = Map<String, dynamic>.from(value);
      }

      final id = payload['camera_id']?.toString().trim() ?? key;
      if (id.isEmpty) continue;
      payload['camera_id'] = id;
      entries[id] = payload;
    }

    return entries;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Future<void> _showAlertNotification({
    required String title,
    required String body,
    required double severity,
    required bool isExtreme,
    required String eventKey,
    required String cameraId,
  }) async {
    try {
      final now = DateTime.now();

      final lastForCamera = _lastNotificationTimeByCamera[cameraId];
      if (lastForCamera != null &&
          now.difference(lastForCamera) < _notificationCooldown) {
        return;
      }

      if (_lastAlertTime != null &&
          now.difference(_lastAlertTime!) > _eventResetSilence) {
        _eventNotificationCounts.clear();
      }

      final int currentCount = _eventNotificationCounts[eventKey] ?? 0;

      if (currentCount >= _maxNotificationsPerEvent) {
        return;
      }

      final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'apula_foreground_alerts',
        'APULA Fire Alerts',
        channelDescription: 'Real-time fire detection alerts',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        ongoing: isExtreme,
        autoCancel: !isExtreme,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'confirm_fire',
            'OPEN & CONFIRM',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            'dismiss_alert',
            'Dismiss',
            cancelNotification: true,
          ),
        ],
        showWhen: true,
        enableVibration: true,
        playSound: true,
        vibrationPattern: Int64List.fromList([0, 1100, 300, 1100, 300, 1300, 300, 1300]),
      );

      final NotificationDetails notificationDetails =
          NotificationDetails(android: androidDetails);

      await _localNotifications!.show(
        notificationId,
        title,
        body,
        notificationDetails,
      );

      _eventNotificationCounts[eventKey] = currentCount + 1;
      _lastNotificationTimeByCamera[cameraId] = now;
      _lastAlertTime = now;

      print('📲 Alert notification shown: $title');
    } catch (e) {
      print('❌ Error showing alert notification: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    print('🛑 Foreground AI Service Stopped');
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
