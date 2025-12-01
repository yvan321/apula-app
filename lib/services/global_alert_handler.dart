import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../main.dart'; // navigatorKey

class GlobalAlertHandler {
  static DateTime? _lastModalTime;
  static const Duration modalCooldown = Duration(seconds: 5);

  /// MAIN ENTRY → called by CnnListenerService
  static Future<void> showFireModal({
    required double alert,
    required double severity,
    required String snapshotUrl,
    String deviceName = "Unknown Camera",
  }) async {
    print("🔥 GlobalAlertHandler.showFireModal() | sev=$severity alert=$alert");

    // FIXED THRESHOLDS (use OR only for MEDIUM)
    final bool isHigh = severity >= 0.75 && alert >= 0.75;
    final bool isMedium = severity >= 0.10 || alert >= 0.10;

    if (!isMedium && !isHigh) {
      print("⛔ Below thresholds → ignoring");
      return;
    }

    final userData = await _getUserProfile();

    /// Always log user alert
    await _createUserAlert(alert, severity, snapshotUrl, deviceName);

    if (isHigh) {
      await _createDispatcherAlert(userData, snapshotUrl, deviceName);

      if (_shouldShowModal()) {
        _showHighModal(snapshotUrl);
      }
      return;
    }

    // MEDIUM CASE
    if (isMedium) {
      if (_shouldShowModal()) {
        _showMediumModal(userData, snapshotUrl, deviceName);
      } else {
        print("⏳ Cooldown active → MEDIUM modal not shown");
      }
    }
  }

  // ================================
  // Database Helpers
  // ================================

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
    } catch (e) {
      print("❌ Error fetching user: $e");
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
      print("❌ Failed to create user alert: $e");
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

      print("🚒 Dispatcher alert created");
    } catch (e) {
      print("❌ Failed to create dispatcher alert: $e");
    }
  }

  // ================================
  // Modal Helpers
  // ================================
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
        final bytes = base64Decode(data);
        return Image.memory(bytes, height: 150, fit: BoxFit.cover);
      } catch (_) {}
    }
    return const SizedBox(height: 150, child: Center(child: Text("No snapshot")));
  }

  // ---------------- HIGH MODAL ------------------
  static void _showHighModal(String snapshotUrl) {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) {
      print("❌ HIGH MODAL FAILED — context null");
      return;
    }

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

  // ---------------- MEDIUM MODAL ------------------
  static void _showMediumModal(
    Map<String, dynamic>? user,
    String snapshotUrl,
    String deviceName,
  ) {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) {
      print("❌ MEDIUM MODAL FAILED — context null");
      return;
    }

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
