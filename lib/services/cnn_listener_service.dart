import 'package:firebase_database/firebase_database.dart';

class CnnListenerService {
  static bool _listening = false;
  static DateTime? _lastAlertTime;

  static bool _canSendAlert() {
    if (_lastAlertTime == null) return true;
    return DateTime.now().difference(_lastAlertTime!) > Duration(seconds: 10);
  }

  static Future<void> startListening(
      Function(double alert, double severity) onData) async {
    if (_listening) return;
    _listening = true;

    final ref = FirebaseDatabase.instance.ref("cnn_results/CCTV1");

    ref.onValue.listen((event) {
      if (!event.snapshot.exists) return;

      final data = Map<String, dynamic>.from(event.snapshot.value as Map);

      // CNN MODEL OUTPUT = "prediction"
      final double prediction =
          double.tryParse(data["prediction"].toString()) ?? 0.0;

      // Convert 1-output model → 2 signals
      final double alert = prediction;
      final double severity = prediction;

      // ⭐ Cooldown — prevent alert spam
      if (!_canSendAlert()) return;
      _lastAlertTime = DateTime.now();

      // Send numbers to handler (LiveCameraViewPage)
      onData(alert, severity);
    });
  }
}
