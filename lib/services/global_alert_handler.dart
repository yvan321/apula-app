import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';

class GlobalAlertHandler {
  static DateTime? _lastModalTime;
  static const Duration modalCooldown = Duration(seconds: 5);

  static Future<void> showFireModal({
    required double alert,
    required double severity,
    required String snapshotUrl,
    String deviceName = "Unknown Camera",
  }) async {
    print("🔥 FireModal | sev=$severity alert=$alert");

    // ---------------------------------------------------
    // NEW PROACTIVE CNN THRESHOLDS
    // ---------------------------------------------------
    final bool isDangerous = severity > 0.70 && alert > 0.95;
    final bool isIgnition  = severity > 0.50 && alert > 0.80;
    final bool isSmoke     = severity > 0.30 && alert > 0.60;
    final bool isPreFire   = severity > 0.20 && alert > 0.40;

    if (!isDangerous && !isIgnition && !isSmoke && !isPreFire) {
      print("⛔ Below thresholds → ignoring");
      return;
    }

    // ---------------------------------------------------
    // DETERMINE ALERT TYPE (THIS WAS MISSING)
    // ---------------------------------------------------
    String alertType = "";
    if (isDangerous)      alertType = "🔥 EXTREME FIRE RISK";
    else if (isIgnition)  alertType = "🔥 Ignition Stage";
    else if (isSmoke)     alertType = "⚠️ Heavy Smoke Detected";
    else if (isPreFire)   alertType = "⚠️ Pre-Fire Indicators";

    final userData = await _getUserProfile();

    // Always store user alert
    await _createUserAlert(alert, severity, snapshotUrl, deviceName);

    // ---------------------------------------------------
    // HIGH LEVEL → DISPATCH AUTOMATICALLY
    // ---------------------------------------------------
    if (isDangerous || isIgnition) {
      await _createDispatcherAlert(userData, snapshotUrl, deviceName);

      if (_shouldShowModal()) {
        _showHighModal(snapshotUrl, alertType);
      }
      return;
    }

    // ---------------------------------------------------
    // MEDIUM LEVEL → ask for confirmation
    // ---------------------------------------------------
    if (_shouldShowModal()) {
      _showMediumModal(userData, snapshotUrl, deviceName, alertType);
    } else {
      print("⏳ Cooldown active → modal skipped");
    }
  }

  // Firestore helpers ---------------------------------------------------

  static Future<Map<String, dynamic>?> _getUserProfile() async {
    try {
      final email = FirebaseAuth.instance.currentUser?.email;
      if (email == null) return null;

      final snap = await FirebaseFirestore.instance
          .collection("users")
          .where("email", isEqualTo: email)
          .limit(1)
          .get();

      return snap.docs.isEmpty ? null : snap.docs.first.data();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _createUserAlert(
    double alert,
    double severity,
    String snapshotUrl,
    String deviceName,
  ) async {
    try {
      await FirebaseFirestore.instance.collection("user_alerts").add({
        "alert": alert,
        "severity": severity,
        "snapshotUrl": snapshotUrl,
        "device": deviceName,
        "timestamp": FieldValue.serverTimestamp(),
        "read": false,
      });

      print("📌 user_alerts created");
    } catch (e) {
      print("❌ user alert error: $e");
    }
  }

  static Future<void> _createDispatcherAlert(
    Map<String, dynamic>? user,
    String snapshotUrl,
    String deviceName,
  ) async {
    try {
      await FirebaseFirestore.instance.collection("alerts").add({
        "type": "🔥 Fire Detected",
        "location": deviceName,
        "description": "Fire detected in $deviceName.",
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

      print("🚒 Dispatcher alert created");
    } catch (e) {
      print("❌ dispatcher alert error: $e");
    }
  }

  // Modal helpers -------------------------------------------------------

  static bool _shouldShowModal() {
    if (_lastModalTime == null ||
        DateTime.now().difference(_lastModalTime!) > modalCooldown) {
      _lastModalTime = DateTime.now();
      return true;
    }
    return false;
  }

  static Widget _snapshotWidget(String data) {
    if (data.startsWith("http")) {
      return Image.network(data, height: 150, fit: BoxFit.cover);
    }
    return const SizedBox(height: 150, child: Center(child: Text("No snapshot")));
  }

  // ---------------- HIGH FIRE ----------------
  static void _showHighModal(String snapshotUrl, String alertType) {
    final ctx = navigatorKey.currentState?.overlay?.context;
    if (ctx == null) return;

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(alertType),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _snapshotWidget(snapshotUrl),
            const SizedBox(height: 10),
            const Text("Dispatcher notified automatically."),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK")),
        ],
      ),
    );
  }

  // --------------- MEDIUM FIRE ----------------
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
      builder: (c) => AlertDialog(
        title: Text(alertType),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _snapshotWidget(snapshotUrl),
            const SizedBox(height: 10),
            const Text("Confirm if this fire warning is real."),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("FALSE ALARM"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(c);
              await _createDispatcherAlert(user, snapshotUrl, deviceName);
            },
            child: const Text("CONFIRM FIRE"),
          ),
        ],
      ),
    );
  }
}
