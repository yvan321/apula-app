import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';

class GlobalAlertHandler {
  static DateTime? _lastModalTime;
  static const Duration modalCooldown = Duration(seconds: 8);

  // Stability counters
  static int _dangerCounter = 0;
  static int _ignitionCounter = 0;
  static const int requiredStableCycles = 2;

  // =======================================================
  // MAIN ENTRY POINT
  // =======================================================
  static Future<void> showFireModal({
    required double alert,
    required double severity,
    required String snapshotUrl,
    String deviceName = "Unknown Camera",
  }) async {
    print("🔥 FireModal | severity=$severity | alert=$alert");

    // ===================================================
    // CNN DECISION LOGIC
    // ===================================================
    final bool cautionNow =
        severity >= 0.40 && alert >= 0.73;

    final bool ignitionNow =
        severity >= 0.55 && alert >= 0.75;

    final bool dangerousNow =
        severity >= 0.70 && alert >= 0.80;

    // Immediate override for very high confidence spikes
    final bool strongSpike =
        severity >= 0.90 && alert >= 0.90;

    // ===================================================
    // STABILITY LOGIC
    // ===================================================
    if (dangerousNow) {
      _dangerCounter++;
    } else {
      _dangerCounter = 0;
    }

    if (ignitionNow) {
      _ignitionCounter++;
    } else {
      _ignitionCounter = 0;
    }

    final bool isDangerous =
        strongSpike || _dangerCounter >= requiredStableCycles;

    final bool isIgnition =
        _ignitionCounter >= requiredStableCycles && !isDangerous;

    final bool isCaution =
        cautionNow && !isDangerous && !isIgnition;

    print(
      "Counters → danger=$_dangerCounter ignition=$_ignitionCounter "
      "States → danger=$isDangerous ignition=$isIgnition caution=$isCaution"
    );

    // Ignore fully normal state
    if (!isDangerous && !isIgnition && !isCaution) {
      print("ℹ️ NORMAL → no alert");
      return;
    }

    // ===================================================
    // ALERT TYPE
    // ===================================================
    final String alertType = isDangerous
        ? "🔥 EXTREME FIRE DANGER"
        : isIgnition
            ? "🔥 IGNITION ANOMALY DETECTED"
            : "⚠️ CAUTION: FIRE-LIKE ACTIVITY";

    // ===================================================
    // USER CONTEXT
    // ===================================================
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final userProfile = await _getUserProfile();

    // ===================================================
    // ALWAYS LOG USER ALERT
    // ===================================================
    await _createUserAlert(
      alert,
      severity,
      snapshotUrl,
      deviceName,
      uid,
      alertType,
    );

    // ===================================================
    // DISPATCHER ALERT FOR REAL EVENTS
    // ===================================================
    if (isDangerous || isIgnition) {
      await _createDispatcherAlert(
        userProfile,
        snapshotUrl,
        deviceName,
        alertType,
      );

      _dangerCounter = 0;
      _ignitionCounter = 0;

      if (_shouldShowModal()) {
        _showHighModal(snapshotUrl, alertType);
      }
      return;
    }

    // ===================================================
    // CAUTION MODE
    // ===================================================
    if (isCaution && _shouldShowModal()) {
      _showMediumModal(
        userProfile,
        snapshotUrl,
        deviceName,
        alertType,
      );
    }
  }

  // =======================================================
  // FIRESTORE HELPERS
  // =======================================================
  static Future<Map<String, dynamic>?> _getUserProfile() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return null;

    final snap = await FirebaseFirestore.instance
        .collection("users")
        .where("email", isEqualTo: email)
        .limit(1)
        .get();

    return snap.docs.isEmpty ? null : snap.docs.first.data();
  }

  static Future<void> _createUserAlert(
    double alert,
    double severity,
    String snapshotUrl,
    String deviceName,
    String? uid,
    String type,
  ) async {
    try {
      await FirebaseFirestore.instance.collection("user_alerts").add({
        "alert": alert,
        "severity": severity,
        "type": type,
        "snapshotUrl": snapshotUrl,
        "device": deviceName,
        "timestamp": FieldValue.serverTimestamp(),
        "read": false,
        "userId": uid,
        "userEmail": FirebaseAuth.instance.currentUser?.email,
      });

      print("📌 user_alerts logged → $type");
    } catch (e) {
      print("❌ user alert error: $e");
    }
  }

  static Future<void> _createDispatcherAlert(
    Map<String, dynamic>? user,
    String snapshotUrl,
    String deviceName,
    String alertType,
  ) async {
    try {
      await FirebaseFirestore.instance.collection("alerts").add({
        "type": alertType,
        "location": deviceName,
        "description": "Fire detected in $deviceName",
        "snapshotUrl": snapshotUrl,
        "status": "Pending",
        "timestamp": FieldValue.serverTimestamp(),
        "read": false,
        "userName": user?["name"] ?? "Unknown",
        "userAddress": user?["address"] ?? "N/A",
        "userContact": user?["contact"] ?? "N/A",
        "userEmail": user?["email"] ?? "N/A",
        "userLatitude": user?["latitude"] ?? 0,
        "userLongitude": user?["longitude"] ?? 0,
      });

      print("🚒 dispatcher alert created");
    } catch (e) {
      print("❌ dispatcher alert error: $e");
    }
  }

  // =======================================================
  // MODAL HELPERS
  // =======================================================
  static bool _shouldShowModal() {
    if (_lastModalTime == null ||
        DateTime.now().difference(_lastModalTime!) > modalCooldown) {
      _lastModalTime = DateTime.now();
      return true;
    }
    return false;
  }

  static Widget _snapshotWidget(String url) {
    if (url.startsWith("http")) {
      return Image.network(url, height: 160, fit: BoxFit.cover);
    }
    return const SizedBox(
      height: 160,
      child: Center(child: Text("No snapshot available")),
    );
  }

  static void _showHighModal(String snapshotUrl, String alertType) {
    final ctx = navigatorKey.currentState?.overlay?.context;
    if (ctx == null) return;

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(alertType),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _snapshotWidget(snapshotUrl),
            const SizedBox(height: 12),
            const Text(
              "Emergency responders have been notified automatically.",
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  static void _showMediumModal(
    Map<String, dynamic>? user,
    String snapshotUrl,
    String deviceName,
    String alertType,
  ) {
    final ctx = navigatorKey.currentState?.overlay?.context;
    if (ctx == null) return;

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(alertType),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _snapshotWidget(snapshotUrl),
            const SizedBox(height: 12),
            const Text("Please confirm if this is a real fire."),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("FALSE ALARM"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _createDispatcherAlert(
                user,
                snapshotUrl,
                deviceName,
                "🔥 FIRE CONFIRMED BY USER",
              );
            },
            child: const Text("CONFIRM FIRE"),
          ),
        ],
      ),
    );
  }
}
