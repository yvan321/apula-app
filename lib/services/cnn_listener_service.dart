import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:firebase_database/firebase_database.dart';
import '../main.dart';

typedef CnnCallback = void Function(double alert, double severity, String snapshotUrl);

class CnnListenerService {
  static StreamSubscription<DatabaseEvent>? _sub;
  static bool simulationOnly = false;

  static void startListening(CnnCallback callback) {
    if (simulationOnly) return;
    if (_sub != null) return;

    try {
      final rtdb = FirebaseDatabase.instanceFor(app: yoloFirebaseApp);

      final cnnRef = rtdb.ref('cnn_results/CCTV1');
      final snapRef = rtdb.ref('cam_detections/latest');

      String lastSnapshot = "";

      snapRef.onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        if (data != null) {
          lastSnapshot = data["image_url"] ?? "";
        }
      });

      _sub = cnnRef.onValue.listen((event) {
        final map = (event.snapshot.value ?? {}) as Map;

        final double alert = _toDouble(map["alert"]);
        final double severity = _toDouble(map["severity"]);

        SchedulerBinding.instance.addPostFrameCallback((_) {
          callback(alert, severity, lastSnapshot);
        });
      });

    } catch (e) {
      print("CnnListenerService error: $e");
    }
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}
