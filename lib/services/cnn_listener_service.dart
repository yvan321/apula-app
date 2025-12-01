// lib/services/cnn_listener_service.dart
import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:firebase_database/firebase_database.dart';
import '../main.dart';  // to access yoloFirebaseApp

typedef CnnCallback = void Function(double alert, double severity);

class CnnListenerService {
  static StreamSubscription<DatabaseEvent>? _sub;

  /// old variable you used in main.dart
  static bool simulationOnly = false;

  /// ORIGINAL FUNCTION you call in main.dart
  static void startListening(
    void Function(double alert, double severity, String snapshotUrl) callback,
  ) {
    if (simulationOnly) return;

    try {
      if (_sub != null) return;

      final rtdb = FirebaseDatabase.instanceFor(app: yoloFirebaseApp);

      // Listen to CNN prediction output
      final cnnRef = rtdb.ref('cnn_results/CCTV1');

      // Listen to latest YOLO snapshot
      final snapRef = rtdb.ref('cam_detections/latest');

      String lastSnapshot = "";

      // Listen to snapshots
      snapRef.onValue.listen((event) {
        try {
          final data = event.snapshot.value as Map?;
          if (data != null) {
            lastSnapshot = data["image_url"] ?? "";
          }
        } catch (_) {}
      });

      // Listen to CNN outputs
      _sub = cnnRef.onValue.listen((event) {
        try {
          final map = (event.snapshot.value ?? {}) as Map;

          final double alert = _toDouble(map['alert']);
          final double severity = _toDouble(map['severity']);

          SchedulerBinding.instance.addPostFrameCallback((_) {
            callback(alert, severity, lastSnapshot);
          });

        } catch (e, st) {
          print("CnnListenerService error → $e\n$st");
        }
      });

    } catch (e, st) {
      print("CnnListenerService startListening failed → $e\n$st");
    }
  }


  /// STOP LISTENING
  static Future<void> stopListening() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
  }

  /// SIMULATION SUPPORT (your old code)
  static void simulate(CnnCallback callback,
      {double alert = 0.0, double severity = 0.0}) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      callback(alert, severity);
    });
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    if (v is num) return v.toDouble();
    return 0.0;
  }
}
