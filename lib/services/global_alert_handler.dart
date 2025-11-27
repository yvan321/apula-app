import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../main.dart'; // navigatorKey

class GlobalAlertHandler {
  static DateTime? _lastModalTime;
  static const Duration modalCooldown = Duration(seconds: 8);

  /// Entry: will write user_alerts and dispatcher alerts and show modal
  static Future<void> showFireModal({
    required double alert,
    required double severity,
    required String snapshotUrl,
    String deviceName = "Unknown Camera",
  }) async {
    final isHigh = severity >= 0.6 || alert >= 0.6;
    final isMedium = severity >= 0.3 || alert >= 0.3;

    if (!isMedium && !isHigh) return; // low severity → ignore

    // fetch user data (if logged in)
    final userData = await _getUserProfile();

    // Always write to user_alerts (no modal cooldown for DB writes)
    await _createUserAlert(alert, severity, snapshotUrl, deviceName);

    // High severity → auto dispatcher alert & modal
    if (isHigh) {
      await _createDispatcherAlert(userData, snapshotUrl, deviceName);
      if (_shouldShowModal()) _showHighModal(snapshotUrl);
      return;
    }

    // Medium → show confirm modal (cooldown enforced for UI only)
    if (isMedium && _shouldShowModal()) {
      _showMediumModal(userData, snapshotUrl, deviceName);
    }
  }

  // -------------------------
  // Firestore helpers
  // -------------------------
  static Future<Map<String, dynamic>?> _getUserProfile() async {
    try {
      final email = FirebaseAuth.instance.currentUser?.email;
      if (email == null) return null;
      final snap = await FirebaseFirestore.instance
          .collection("users")
          .where("email", isEqualTo: email)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.data();
    } catch (e) {
      print("❌ Error fetching user profile: $e");
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
      if (kDebugMode) print("📌 user_alerts created");
    } catch (e) {
      print("❌ Failed to create user_alert: $e");
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
        "read": false,
        "timestamp": FieldValue.serverTimestamp(),
        "userName": user?["name"] ?? "Unknown",
        "userAddress": user?["address"] ?? "N/A",
        "userContact": user?["contact"] ?? "N/A",
        "userEmail": user?["email"] ?? "N/A",
        "userLatitude": user?["latitude"] ?? 0,
        "userLongitude": user?["longitude"] ?? 0,
      });
      if (kDebugMode) print("🚒 Dispatcher alert created");
    } catch (e) {
      print("❌ Failed to create dispatcher alert: $e");
    }
  }

  // -------------------------
  // Modal helpers
  // -------------------------
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
    if (data.isNotEmpty) {
      try {
        Uint8List bytes = base64Decode(data);
        return Image.memory(bytes, height: 150, fit: BoxFit.cover);
      } catch (_) {}
    }
    return const SizedBox(height: 150, child: Center(child: Text("No snapshot")));
  }

  static void _showHighModal(String snapshotUrl) {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("🔥 FIRE DETECTED"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _snapshotWidget(snapshotUrl),
            const SizedBox(height: 10),
            const Text("A severe fire risk was detected.\nDispatcher notified."),
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
  ) {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ POSSIBLE FIRE"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _snapshotWidget(snapshotUrl),
            const SizedBox(height: 10),
            const Text("A moderate fire risk was detected.\nConfirm if real."),
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
              await _createDispatcherAlert(user, snapshotUrl, deviceName);
            },
            child: const Text("CONFIRM FIRE"),
          ),
        ],
      ),
    );
  }
}
