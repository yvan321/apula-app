import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:firebase_database/firebase_database.dart';
import '../main.dart';

typedef CnnCallback = void Function(
  double alert,
  double severity,
  String snapshotUrl,
);

class CnnListenerService {
  static final List<CnnCallback> _callbacks = [];
  static StreamSubscription<DatabaseEvent>? _sub;

  static double _lastAlert = 0.0;
  static double _lastSeverity = 0.0;
  static DateTime? _lastEmitTime;

  static const Duration emitInterval = Duration(seconds: 5);
  static const double deltaThreshold = 0.05;

  static void startListening(CnnCallback callback) {
    _callbacks.add(callback);

    if (_sub != null) return;

    final rtdb = FirebaseDatabase.instanceFor(app: yoloFirebaseApp);
    final ref = rtdb.ref('cnn_results/CCTV1');

    _sub = ref.onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) return;

      final data = Map<String, dynamic>.from(raw);

      final double alert = _toDouble(data["alert"]);
      final double severity = _toDouble(data["severity"]);
      final snapshotUrl =
          data["input"]?["image_url"]?.toString() ?? "";

      final now = DateTime.now();

      final bool valueChanged =
          (alert - _lastAlert).abs() > deltaThreshold ||
          (severity - _lastSeverity).abs() > deltaThreshold;

      if (_lastEmitTime != null &&
          now.difference(_lastEmitTime!) < emitInterval &&
          !valueChanged) {
        return;
      }

      _lastAlert = alert;
      _lastSeverity = severity;
      _lastEmitTime = now;

      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final cb in _callbacks) {
          cb(alert, severity, snapshotUrl);
        }
      });
    });
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
