// lib/services/cnn_listener_service.dart
import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:firebase_database/firebase_database.dart';

typedef CnnCallback = void Function(double alert, double severity);

class CnnListenerService {
  static StreamSubscription<DatabaseEvent>? _sub;
  // If you want to disable live DB listening and just use simulation, set to true.
  static bool simulationOnly = false;

  /// Start listening for CNN updates. callback must be non-null.
  /// This function is idempotent (multiple calls won't create multiple listeners).
  static void startListening(CnnCallback callback) {
    if (simulationOnly) {
      // nothing to start, use simulateUpdate to test
      return;
    }

    try {
      if (_sub != null) return; // already listening

      final ref = FirebaseDatabase.instance.ref('cnn_results/CCTV1');

      _sub = ref.onValue.listen((event) {
        try {
          final val = event.snapshot.value;
          double alert = 0.0;
          double severity = 0.0;

          if (val is Map) {
            // adapt field names to whatever your backend writes
            final map = Map<String, dynamic>.from(val);
            alert = _toDouble(map['alert'] ?? map['probability'] ?? map['confidence'] ?? 0.0);
            severity = _toDouble(map['severity'] ?? map['severity_score'] ?? map['score'] ?? alert);
          } else if (val is num) {
            alert = val.toDouble();
            severity = alert;
          }

          // Ensure callback runs on the main/UI loop so showDialog works
          SchedulerBinding.instance.addPostFrameCallback((_) {
            try {
              callback(alert, severity);
            } catch (cbErr, cbStack) {
              // don't let UI exceptions kill the listener
              // use print so it shows in debug/console
              print('CnnListenerService: callback error: $cbErr\n$cbStack');
            }
          });
        } catch (e, st) {
          print('CnnListenerService: onValue handling error: $e\n$st');
        }
      }, onError: (err) {
        print('CnnListenerService: subscription error: $err');
      });
    } catch (e, st) {
      print('CnnListenerService: startListening failed: $e\n$st');
    }
  }

  /// Stop the DB listener (useful for disposal / tests).
  static Future<void> stopListening() async {
    try {
      await _sub?.cancel();
    } catch (e) {
      print('CnnListenerService: stopListening error: $e');
    } finally {
      _sub = null;
    }
  }

  /// For manual testing: call this to simulate a CNN update that will call the callback.
  static void simulate(CnnCallback callback, {double alert = 0.0, double severity = 0.0}) {
    // call on next frame so behavior matches DB-driven updates
    SchedulerBinding.instance.addPostFrameCallback((_) {
      try {
        callback(alert, severity);
      } catch (e, st) {
        print('CnnListenerService.simulate callback error: $e\n$st');
      }
    });
  }

  static double _toDouble(dynamic v) {
    try {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      if (v is num) return v.toDouble();
    } catch (_) {}
    return 0.0;
  }
}
