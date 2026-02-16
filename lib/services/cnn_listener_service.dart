import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:firebase_database/firebase_database.dart';
import '../main.dart';

typedef CnnCallback = void Function(
  String cameraId,
  double alert,
  double severity,
  String snapshotUrl,
);

class CnnListenerService {
  static final Map<String, List<CnnCallback>> _callbacks = {};
  static final Map<String, StreamSubscription<DatabaseEvent>> _subs = {};
  static final Map<String, _CameraState> _states = {};

  static void startListening(List<String> cameraIds, CnnCallback callback) {
    for (final cameraId in cameraIds) {
      // Add callback for this camera
      _callbacks.putIfAbsent(cameraId, () => []);
      if (!_callbacks[cameraId]!.contains(callback)) {
        _callbacks[cameraId]!.add(callback);
      }

      // Skip if already listening to this camera
      if (_subs.containsKey(cameraId)) continue;

      // Initialize state
      _states[cameraId] = _CameraState();

      // Start listening to this camera's CNN results
      final rtdb = FirebaseDatabase.instanceFor(app: yoloFirebaseApp);
      final ref = rtdb.ref('cnn_results/$cameraId');

      _subs[cameraId] = ref.onValue.listen((event) {
        _handleCameraUpdate(cameraId, event);
      });

      print('📹 Started listening to CNN results for: $cameraId');
    }
  }

  static void _handleCameraUpdate(String cameraId, DatabaseEvent event) {
    final raw = event.snapshot.value;
    if (raw == null || raw is! Map) return;

    final data = Map<String, dynamic>.from(raw);
    final state = _states[cameraId]!;

    final double alert = _toDouble(data["alert"]);
    final double severity = _toDouble(data["severity"]);
    final snapshotUrl = data["input"]?["image_url"]?.toString() ?? "";

    final now = DateTime.now();

    final bool valueChanged =
        (alert - state.lastAlert).abs() > state.deltaThreshold ||
        (severity - state.lastSeverity).abs() > state.deltaThreshold;

    if (state.lastEmitTime != null &&
        now.difference(state.lastEmitTime!) < state.emitInterval &&
        !valueChanged) {
      return;
    }

    state.lastAlert = alert;
    state.lastSeverity = severity;
    state.lastEmitTime = now;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      final callbacks = _callbacks[cameraId] ?? [];
      for (final cb in callbacks) {
        cb(cameraId, alert, severity, snapshotUrl);
      }
    });
  }

  static void stopListening(String cameraId) {
    _subs[cameraId]?.cancel();
    _subs.remove(cameraId);
    _callbacks.remove(cameraId);
    _states.remove(cameraId);
    print('🛑 Stopped listening to CNN results for: $cameraId');
  }

  static void stopAll() {
    for (final sub in _subs.values) {
      sub.cancel();
    }
    _subs.clear();
    _callbacks.clear();
    _states.clear();
    print('🛑 Stopped all CNN listeners');
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}

class _CameraState {
  double lastAlert = 0.0;
  double lastSeverity = 0.0;
  DateTime? lastEmitTime;
  
  final Duration emitInterval = const Duration(seconds: 5);
  final double deltaThreshold = 0.05;
}
