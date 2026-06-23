import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_yolo_options.dart';
import 'package:apula/utils/alert_source_attribution.dart';

// This function runs in a separate isolate
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print("🔥 Background AI Task Started: $task");
      
      // Initialize Firebase (required in isolate)
      await Firebase.initializeApp();
      await Firebase.initializeApp(
        name: 'yoloApp',
        options: FirebaseYoloOptions.options,
      );
      
      // Initialize notifications
      final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
      const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await notifications.initialize(InitializationSettings(android: androidInit));
      
      // Show start notification
      await _showNotification(
        notifications,
        'APULA Background Task',
        'Running AI analysis...',
        channelId: 'background_task',
      );
      
      // Run AI inference
      final result = await _runBackgroundAI();
      
      // Show alert notification ONLY if there's fire/warning detected (not NO_FIRE)
      if (result != null) {
        final isExtreme = result['label']?.contains('EXTREME') ?? false;
        final importance = isExtreme ? Importance.high : Importance.defaultImportance;
        
        await _showNotification(
          notifications,
          '🚨 ${result['label']}',
          'Camera: ${result['cameraId']} | Severity: ${result['fireProb']}%',
          channelId: 'background_alert',
          importance: importance,
        );
        print('📲 Notification sent for: ${result['label']}');
      } else {
        print('✅ No alerts - Status normal');
      }
      
      print("✅ Background AI Task Completed");
      return Future.value(true);
    } catch (e) {
      print("❌ Background Task Error: $e");
      return Future.value(false);
    }
  });
}

Future<Map<String, String>?> _runBackgroundAI() async {
  // Load TFLite model - use quantized model like background_cnn_service
  final interpreter = await Interpreter.fromAsset(
    "assets/ml/cnn_model_quant.tflite",
    options: InterpreterOptions()..threads = 2,
  );

  // Load scaler
  final scalerJson = await rootBundle.loadString("assets/ml/cnn_scaler.json");
  final scaler = jsonDecode(scalerJson);
  final means = List<double>.from(scaler["mean"]);
  final stds = List<double>.from(scaler["scale"]); // Note: JSON has 'scale' not 'std'
  print("✅ Scaler loaded: ${means.length} features");

  // Get latest data from Firebase - USE YOLO APP
  final yoloApp = Firebase.app('yoloApp');
  final rtdb = FirebaseDatabase.instanceFor(app: yoloApp);
  final yoloSnap = await rtdb.ref("cam_detections").get();
  print("📡 Fetching data from yoloApp RTDB");

  if (!yoloSnap.exists) {
    print("⚠️ No data available");
    interpreter.close();
    return null;
  }

  final yoloEntries = _extractYoloEntries(yoloSnap.value);
  if (yoloEntries.isEmpty) {
    interpreter.close();
    return null;
  }

  Map<String, String>? topAlert;
  double topScore = -1;

  for (final entry in yoloEntries.entries) {
    final cameraId = entry.key;
    final yoloData = entry.value;

    // Camera-scoped sensor path: sensor_data/{cameraId}/latest
    // Keep legacy fallback for backward compatibility.
    DataSnapshot sensorSnap = await rtdb.ref("sensor_data/$cameraId/latest").get();
    if (!sensorSnap.exists) {
      sensorSnap = await rtdb.ref("sensor_data/latest").get();
    }

    if (!sensorSnap.exists || sensorSnap.value is! Map) {
      print("⚠️ No sensor data available for $cameraId");
      continue;
    }

    final sensorData = sensorSnap.value as Map;

    // Build input features - matching background_cnn_service.dart field names
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

    // Normalize
    final List<double> normalized = List.generate(
      features.length,
      (i) => (features[i] - means[i]) / stds[i],
    );

    // Run inference - same format as background_cnn_service
    final input = [normalized.map((v) => [v]).toList()];
    final output = List.generate(1, (_) => List.filled(2, 0.0));
    interpreter.run(input, output);

    // Parse results
    final severity = output[0][0];
    final alert = output[0][1];

    // Match GlobalAlertHandler thresholds
    final bool cautionNow = severity >= 0.40 && alert >= 0.73;
    final bool ignitionNow = severity >= 0.55 && alert >= 0.75;
    final bool dangerousNow = severity >= 0.70 && alert >= 0.80;

    String label = "NO_FIRE";
    if (dangerousNow) {
      label = "EXTREME FIRE DANGER";
    } else if (ignitionNow) {
      label = "IGNITION ANOMALY";
    } else if (cautionNow) {
      label = "FIRE-LIKE ACTIVITY";
    }

    print("🔥 AI Result [$cameraId]: $label (Severity: ${(severity * 100).toStringAsFixed(1)}%, Alert: ${(alert * 100).toStringAsFixed(1)}%)");

    // Save to Firebase - camera-specific path
    await rtdb.ref("cnn_results/$cameraId").set({
      "severity": severity,
      "alert": alert,
      "prediction": label,
      "timestamp": DateTime.now().toIso8601String(),
      "source": "background_task",
      "input": {
        "image_url": yoloData["image_url"],
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

    if (label != "NO_FIRE") {
      final score = severity + alert;
      if (score > topScore) {
        topScore = score;
        topAlert = {
          'label': label,
          'fireProb': (severity * 100).toStringAsFixed(1),
          'cameraId': cameraId,
        };
      }
    }
  }

  interpreter.close();
  return topAlert;
}

Map<String, Map<String, dynamic>> _extractYoloEntries(dynamic rawRoot) {
  final entries = <String, Map<String, dynamic>>{};
  if (rawRoot is! Map) return entries;

  final root = Map<String, dynamic>.from(rawRoot as Map);

  final latest = root['latest'];
  if (latest is Map) {
    final payload = Map<String, dynamic>.from(latest as Map);
    final cameraId = payload['camera_id']?.toString().trim() ?? '';
    if (cameraId.isNotEmpty) {
      payload['camera_id'] = cameraId;
      entries[cameraId] = payload;
    }
  }

  for (final entry in root.entries) {
    final key = entry.key.toString();
    if (key == 'latest') continue;

    final value = entry.value;
    if (value is! Map) continue;

    Map<String, dynamic>? payload;
    if (value['latest'] is Map) {
      payload = Map<String, dynamic>.from(value['latest'] as Map);
    } else {
      payload = Map<String, dynamic>.from(value as Map);
    }

    final cameraId = (payload['camera_id']?.toString().trim().isNotEmpty == true)
        ? payload['camera_id'].toString().trim()
        : key;
    if (cameraId.isEmpty) continue;

    payload['camera_id'] = cameraId;
    entries[cameraId] = payload;
  }

  return entries;
}

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

// Helper to show notifications from background task
Future<void> _showNotification(
  FlutterLocalNotificationsPlugin plugin,
  String title,
  String body, {
  String channelId = 'apula_background',
  Importance importance = Importance.defaultImportance,
}) async {
  final androidDetails = AndroidNotificationDetails(
    channelId,
    'APULA Background Task',
    channelDescription: 'Periodic AI fire detection',
    importance: importance,
    priority: Priority.high,
    showWhen: true,
  );
  
  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    NotificationDetails(android: androidDetails),
  );
}
