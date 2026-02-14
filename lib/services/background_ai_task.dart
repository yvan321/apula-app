import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_yolo_options.dart';

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
      
      // Show result notification
      if (result != null) {
        await _showNotification(
          notifications,
          '🔥 AI Detection Result',
          '${result['label']} - Severity: ${result['fireProb']}%',
          channelId: 'background_task',
          importance: result['label'] == 'FIRE' ? Importance.high : Importance.defaultImportance,
        );
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
  final yoloSnap = await rtdb.ref("cam_detections/latest").get();
  final sensorSnap = await rtdb.ref("sensor_data/latest").get();
  print("📡 Fetching data from yoloApp RTDB");

  if (!yoloSnap.exists || !sensorSnap.exists) {
    print("⚠️ No data available");
    interpreter.close();
    return null;
  }

  final yoloData = yoloSnap.value as Map;
  final sensorData = sensorSnap.value as Map;

  // Build input features - matching background_cnn_service.dart field names
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
    (i) => (features[i] - means[i]) / stds[i],
  );

  // Run inference - same format as background_cnn_service
  var input = [normalized.map((v) => [v]).toList()];
  var output = List.generate(1, (_) => List.filled(2, 0.0));
  
  interpreter.run(input, output);

  // Parse results
  final severity = output[0][0];
  final alert = output[0][1];
  final label = severity > 0.5 ? "FIRE" : "NO_FIRE";

  print("🔥 AI Result: $label (Severity: ${(severity * 100).toStringAsFixed(1)}%, Alert: ${(alert * 100).toStringAsFixed(1)}%)");

  // Save to Firebase (reuse yoloApp and rtdb from above)
  await rtdb.ref("cnn_results/background").set({
    "severity": severity,
    "alert": alert,
    "prediction": label,
    "timestamp": DateTime.now().toIso8601String(),
    "source": "background_task",
  });

  interpreter.close();
  
  // Return result for notification
  return {
    'label': label,
    'fireProb': (severity * 100).toStringAsFixed(1),
  };
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
